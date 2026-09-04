#!/usr/bin/env python3
"""Drive the self-hosted language server over a pipe, one session per
fixture, and check what it publishes against two hand-maintained
manifests and the fixture's own bytes.

WHAT THIS USED TO DO. The second half of this driver ran the Rust
compiler: for every fixture it called `stage0 check --diagnostic-format
ai`, parsed the AXDL line, converted stage0's 1-based CHARACTER column
into the 0-based UTF-16 code unit LSP requires, and required the set of
(severity, code, line, column) tuples the server published to equal it.
That was the half a `--bless` could not satisfy, and it is gone with the
compiler that produced it.

WHAT REPLACES IT. A differential says two implementations agree. It does
not say either is right, and - the trap this repository names most often
- it does not FAIL when its reference disappears: point it at a
self-hosted binary and every comparison becomes a compiler against
itself, 7 fixtures swept, zero differences, exit 0, nothing tested. So
the reference is now a second implementation IN PYTHON of the one
quantity the old half existed to check, computed from the fixture's own
bytes:

    column = len(line[:char_index].encode("utf-16-le")) // 2

plus two files no compiler writes: expected-diagnostics.txt and
expected-outline.txt.

WHAT IS PINNED WITHOUT A GOLDEN, and therefore survives a `--bless` from
any compiler at all:

  1. EVERY DIAGNOSTIC, AS A COUNTED LIST. For each fixture, the sorted
     list of (LSP severity integer, code, line, UTF-16 start, UTF-16
     end, first line of the message) must equal the list derived from
     expected-diagnostics.txt and the fixture's bytes. Positions are
     computed here, never read; the severity is the protocol's integer
     and not a two-way projection of it; the message's first line is
     written by hand in the manifest with `%N` for the anchor; and the
     comparison is of LISTS, so a document with two diagnostics has two
     obligations.

  2. EVERY SYMBOL. expected-outline.txt is total over the fixtures: a
     document must publish exactly the listed symbols, in order, with
     the listed SymbolKind, each `selectionRange` equal to a position
     derived here from an anchor. A fixture with no rows must publish
     an empty outline.

  3. TWO INVARIANTS ON EVERY SYMBOL of every document including the
     6001-symbol generated one: `selectionRange` contained in `range`,
     which is what LSP requires and what self_host/lsp.ax's comment
     claims; and the source sliced at `selectionRange` spelling the
     symbol's own `name`.

  4. THE RANGE MUST SPELL WHAT THE MESSAGE NAMES. For every published
     diagnostic with a non-empty range, the UTF-16 slice of the source
     line at [start, end) must equal the first backticked name in the
     message - the analogue of tests/tools/verify-axsym.py.

WHAT IS GOLDEN-ONLY, and is therefore exactly as strong as the compiler
that last blessed it: the framed byte stream itself - framing, field
order, JSON escaping, the `initialize` capabilities, the -32601 error
body - and the `help:` paragraph after a message's first line. Those are
protocol shape and prose. Everything a reader would call "is the answer
right" is in the list above.

None of the four was a regression when the stage0 half was deleted: the
differential compared the same E/W tuple SET over the same
one-diagnostic-per-fixture corpus, so it could not see a dropped
diagnostic, a wrong severity beyond error/non-error, a corrupted message
or a wrong SymbolKind either. They were added because a drill proved a
green run did not mean the server was right; the numbers are in
scripts/check-lsp-selfhost.sh's header.

Anti-vacuousness. The floors are DERIVED, not constant: before any
server starts, this file reads the selected fixtures and computes how
many positions it is about to assert, how many name-at-range checks
those imply, how many of them discriminate UTF-16 from bytes and
characters, and how many symbols it is about to verify. At the end the
counts must match EXACTLY - too few means a check was skipped, too many
means one ran twice. Filtering scales them; it does not switch them off,
and a filtered run exits non-zero whatever it finds, because it asserted
part of the corpus and its status must not read as "the gate passed".

Usage: drive.py STAGE1 FIXTURE_DIR [--bless] [filter]
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

stage1, fixdir = sys.argv[1], sys.argv[2]
rest = sys.argv[3:]
bless = "--bless" in rest
filt = next((a for a in rest if not a.startswith("--")), "")

DOC_URI = "file:///DOC.ax"
MANIFEST = os.path.join(fixdir, "expected-diagnostics.txt")
OUTLINE = os.path.join(fixdir, "expected-outline.txt")

FIXTURE_FLOOR = 9
MANIFEST_FLOOR = 6
OUTLINE_FLOOR = 10

# LSP's own constants, transcribed from the protocol specification.
# Writing the integers in the manifests instead would be copying down
# whatever the server under test happens to emit.
LSP_SEVERITY = {"E": 1, "W": 2}
LSP_SYMBOL_KIND = {"Function": 12, "Enum": 10, "Struct": 23}


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


# --------------------------------------------------------------------
# The second implementation. Everything below computes LSP positions
# from source text, in Python, with no compiler involved.
# --------------------------------------------------------------------

def u16(s):
    """UTF-16 code units in `s`. The whole gate turns on this being a
    different number from len(s) and from len(s.encode("utf-8")) for at
    least one fixture."""
    return len(s.encode("utf-16-le")) // 2


def line_of(src, index):
    """(0-based line number, that line's text, character offset within
    it) for a character index into `src`."""
    start = src.rfind("\n", 0, index) + 1
    nl = src.find("\n", start)
    text = src[start:] if nl < 0 else src[start:nl]
    return src.count("\n", 0, start), text, index - start


def locate(src, anchor, occurrence):
    """Where the N-th occurrence of `anchor` sits, in the coordinates
    LSP asks for: 0-based line, 0-based UTF-16 start and end. Also
    answers the byte and character columns, which nothing asserts - they
    exist so the gate can prove the three encodings are distinguishable
    on at least one fixture."""
    idx = -1
    for _ in range(occurrence):
        nxt = src.find(anchor, idx + 1)
        if nxt < 0:
            raise LookupError(f"anchor {anchor!r} has fewer than {occurrence} "
                              f"occurrences")
        idx = nxt
    ln, text, col = line_of(src, idx)
    start = u16(text[:col])
    return {"line": ln, "start": start, "end": start + u16(anchor),
            "byte_col": len(text[:col].encode("utf-8")), "char_col": col}


def parse_anchor(anchor):
    """`TEXT` or `N@TEXT` -> (occurrence, text)."""
    n, _, text = anchor.partition("@")
    if not text:
        return 1, n
    return int(n), text


def discriminates(p):
    """True when this derived position tells the three encodings apart:
    its UTF-16 column is neither the byte column nor the character
    column, so a server reporting either of those is caught."""
    return p["start"] != p["byte_col"] and p["start"] != p["char_col"]


def slice_u16(text, start, end):
    """The source text a published range actually covers. Raises if the
    range splits a surrogate pair - which is itself a bug worth
    failing on, since no character begins there."""
    return text.encode("utf-16-le")[2 * start:2 * end].decode("utf-16-le")


def first_line(msg):
    return msg.split("\n", 1)[0]


def render(template, name, where):
    """The message first line a row demands. `%N` stands for the
    anchor's text, so the manifest says the SHAPE of the message once
    and the name comes from the same place the position does."""
    if "%N" not in template:
        return template
    if name is None:
        sys.exit(f"FAIL: {where}: message template uses %N but the anchor "
                 f"names nothing")
    return template.replace("%N", name)


def check_range(srclines, d):
    """Check one published diagnostic against the source it points into,
    with no manifest and no golden involved: the line must exist, the
    range must end within the line's UTF-16 length, and - when the range
    is non-empty and the message quotes a name in backticks - the source
    at exactly those UTF-16 units must spell that name.

    Answers (reason it is wrong or None, 1 if a name was actually
    checked else 0). The second number is counted so the gate can refuse
    a run where this check silently applied to nothing."""
    ln = d["range"]["start"]["line"]
    st, en = d["range"]["start"]["character"], d["range"]["end"]["character"]
    if ln >= len(srclines):
        return f"range on line {ln}, document has {len(srclines)} lines", 0
    if en > u16(srclines[ln]):
        return (f"range ends at UTF-16 unit {en} on line {ln}, which is "
                f"{u16(srclines[ln])} units long"), 0
    if en <= st:
        return None, 0
    quoted = re.search(r"`([^`]+)`", d.get("message", ""))
    if not quoted:
        return None, 0
    try:
        covers = slice_u16(srclines[ln], st, en)
    except UnicodeDecodeError:
        return f"range {ln}:{st}-{en} splits a surrogate pair", 0
    if covers != quoted.group(1):
        return (f"{d['code']} at {ln}:{st}-{en} says `{quoted.group(1)}` "
                f"but the source spells {covers!r} there"), 0
    return None, 1


def symbol_invariants(srclines, syms):
    """The two things every symbol must satisfy in every document, with
    no manifest: `selectionRange` inside `range`, and the source at
    `selectionRange` spelling the symbol's own name.

    Answers (reason or None, number of names actually read back out of
    the source). Between them these catch a symbol placed anywhere it
    does not belong: collapse `range` and the containment fails,
    collapse both and the name no longer spells."""
    checked = 0
    for s in syms:
        if not isinstance(s, dict) or "name" not in s or "kind" not in s:
            return f"symbol is not a DocumentSymbol: {s!r:.120}", checked
        if not isinstance(s["kind"], int):
            return f"symbol {s['name']!r} has non-integer kind {s['kind']!r}", checked
        for key in ("range", "selectionRange"):
            if key not in s:
                return f"symbol {s['name']!r} has no {key}", checked
        rg, sel = s["range"], s["selectionRange"]
        def pos(p):
            return (p["line"], p["character"])
        if not (pos(rg["start"]) <= pos(sel["start"])
                and pos(sel["end"]) <= pos(rg["end"])):
            return (f"symbol {s['name']!r}: selectionRange "
                    f"{pos(sel['start'])}-{pos(sel['end'])} is not contained in "
                    f"range {pos(rg['start'])}-{pos(rg['end'])}, which the "
                    f"protocol requires"), checked
        ln = sel["start"]["line"]
        if sel["end"]["line"] != ln:
            return f"symbol {s['name']!r}: selectionRange spans lines", checked
        if ln >= len(srclines):
            return (f"symbol {s['name']!r}: selectionRange on line {ln}, "
                    f"document has {len(srclines)} lines"), checked
        st, en = sel["start"]["character"], sel["end"]["character"]
        if en <= st:
            return (f"symbol {s['name']!r}: selectionRange {ln}:{st}-{en} is "
                    f"empty, so it spells nothing"), checked
        if en > u16(srclines[ln]):
            return (f"symbol {s['name']!r}: selectionRange ends at UTF-16 unit "
                    f"{en} on line {ln}, which is {u16(srclines[ln])} units "
                    f"long"), checked
        try:
            covers = slice_u16(srclines[ln], st, en)
        except UnicodeDecodeError:
            return (f"symbol {s['name']!r}: selectionRange {ln}:{st}-{en} "
                    f"splits a surrogate pair"), checked
        if covers != s["name"]:
            return (f"symbol says its name is {s['name']!r} but the source at "
                    f"{ln}:{st}-{en} spells {covers!r}"), checked
        checked += 1
    return None, checked


def read_rows(path, ncols, what):
    """Rows of a hand-maintained manifest: `#` comments, blank lines
    skipped, exactly `ncols` whitespace-separated fields with the last
    one allowed to contain spaces."""
    if not os.path.exists(path):
        sys.exit(f"FAIL: no {what} at {path} - without it this gate is a "
                 f"golden comparison and nothing else, and a bless would "
                 f"satisfy all of it")
    rows = []
    for raw in open(path, encoding="utf-8"):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split(None, ncols - 1)
        if len(parts) != ncols:
            sys.exit(f"FAIL: malformed {what} row: {raw.rstrip()!r}")
        rows.append(tuple(parts))
    return rows


def expected_for(fx, rows, src):
    """The (severity, code, line, start, end, message-first-line) tuples
    fixture `fx` must publish, derived from `src` and the manifest's own
    text - the positions never read, the severity the protocol's
    integer, the message written by hand.

    A LIST, not a set: two rows that differ only in their anchor are two
    obligations, and a server that drops one of them or emits either
    twice must fail."""
    want, spanless_names, probes = [], [], []
    for f, sev, code, anchor, template in rows:
        if f != fx:
            continue
        lsp_sev = LSP_SEVERITY[sev]
        if anchor == "<eof>":
            lines = src.split("\n")
            ln, pos = len(lines) - 1, u16(lines[-1])
            want.append((lsp_sev, code, ln, pos, pos,
                         render(template, None, f"{fx} {code}")))
        elif anchor.startswith("<spanless>"):
            name = anchor[len("<spanless>"):]
            if name not in src:
                sys.exit(f"FAIL: manifest anchor <spanless>{name} names "
                         f"something {fx} does not contain")
            spanless_names.append(name)
            want.append((lsp_sev, code, 0, 0, 0,
                         render(template, name, f"{fx} {code}")))
        else:
            n, text = parse_anchor(anchor)
            p = locate(src, text, n)
            want.append((lsp_sev, code, p["line"], p["start"], p["end"],
                         render(template, text, f"{fx} {code}")))
            probes.append((anchor, p))
    return want, spanless_names, probes


def outline_for(fx, orows, src):
    """The (name, kind, line, start, end) list fixture `fx` must publish
    as its outline, in document order. Kinds come from the hand-written
    SymbolKind names; positions are derived here."""
    want = []
    for f, kind, anchor in orows:
        if f != fx:
            continue
        if kind not in LSP_SYMBOL_KIND:
            sys.exit(f"FAIL: {OUTLINE} names SymbolKind {kind!r}, which is not "
                     f"one of {sorted(LSP_SYMBOL_KIND)}")
        n, text = parse_anchor(anchor)
        p = locate(src, text, n)
        want.append((text, LSP_SYMBOL_KIND[kind], p["line"], p["start"], p["end"]))
    return want


# --------------------------------------------------------------------
# Manifest sanity, before a single server is started. A manifest whose
# rows are all one thing proves nothing: it would be satisfied by a
# server that answers the same way to everything.
# --------------------------------------------------------------------
rows = read_rows(MANIFEST, 5, "diagnostic manifest")
orows = read_rows(OUTLINE, 3, "outline manifest")

if len(rows) < MANIFEST_FLOOR:
    sys.exit(f"FAIL: manifest has {len(rows)} rows, floor is {MANIFEST_FLOOR}")
if len({r[1] for r in rows}) < 2:
    sys.exit("FAIL: every manifest row has the same severity - it cannot "
             "distinguish an error from a warning")
if len({r[2] for r in rows}) < 2:
    sys.exit("FAIL: every manifest row has the same code - it cannot "
             "distinguish one diagnostic from another")
for r in rows:
    if r[1] not in LSP_SEVERITY:
        sys.exit(f"FAIL: manifest severity {r[1]!r} is not one of "
                 f"{sorted(LSP_SEVERITY)}")
# The counted-list comparison is only worth more than the set it replaced
# if some document actually expects more than one diagnostic.
per_fixture = {}
for r in rows:
    per_fixture[r[0]] = per_fixture.get(r[0], 0) + 1
if max(per_fixture.values()) < 2:
    sys.exit("FAIL: every fixture in the manifest expects exactly one "
             "diagnostic, so comparing lists is the same as comparing sets "
             "and a server that publishes only the first diagnostic of a "
             "document would pass. Restore the multi-diagnostic fixture.")

if len(orows) < OUTLINE_FLOOR:
    sys.exit(f"FAIL: {OUTLINE} has {len(orows)} rows, floor is {OUTLINE_FLOOR}")
if len({r[1] for r in orows}) < 3:
    sys.exit("FAIL: the outline manifest names fewer than 3 distinct "
             "SymbolKinds, so it cannot tell an enum from a struct from a "
             "function and a server that answered 12 to everything would pass")

# `.axbad` is a fixture that deliberately does NOT parse. It cannot be
# called `.ax`: check-fmt.sh and check-tree-sitter.sh both sweep every
# `*.ax` file in the repository and require all of them to parse, and
# they are right to - a file that the grammar cannot read is not Axiom
# source. Every other deliberately-broken fixture in tests/ is broken
# SEMANTICALLY and parses fine, so this is the first of its kind.
all_fixtures = sorted(f for f in os.listdir(fixdir)
                      if f.endswith(".ax") or f.endswith(".axbad"))
if len(all_fixtures) < FIXTURE_FLOOR:
    sys.exit(f"FAIL: {len(all_fixtures)} fixtures found, floor is "
             f"{FIXTURE_FLOOR} - a glob that stops matching removes fixtures "
             f"while the gate goes on reporting the silence it was looking for")
named_in_manifest = {r[0] for r in rows}
unknown = (named_in_manifest | {r[0] for r in orows}) - set(all_fixtures)
if unknown:
    sys.exit(f"FAIL: a manifest names fixtures that do not exist: {sorted(unknown)}")
if not named_in_manifest:
    sys.exit("FAIL: no fixture expects any diagnostic")
if not set(all_fixtures) - named_in_manifest:
    sys.exit("FAIL: every fixture expects a diagnostic - the manifest cannot "
             "tell a clean file from a broken one")

fixtures = [f for f in all_fixtures if filt in f] if filt else all_fixtures

# --------------------------------------------------------------------
# The floors, DERIVED from what this run is about to assert. Read the
# selected fixtures and the manifests now, before any server starts, and
# work out exactly how many of each check must execute. A constant floor
# has to be loose enough not to trip, and `if not filt:` around it turns
# it off entirely for `drive.py ... 010`; these numbers scale with the
# selection and are compared for EQUALITY at the end.
# --------------------------------------------------------------------
expect_anchored = expect_named = expect_discriminating = expect_symbols = 0
corpus_discriminating = []
for fx in all_fixtures:
    src = open(os.path.join(fixdir, fx), encoding="utf-8").read()
    selected = fx in fixtures
    for f, sev, code, anchor, template in rows:
        if f != fx or anchor.startswith("<"):
            continue
        n, text = parse_anchor(anchor)
        try:
            p = locate(src, text, n)
        except LookupError as e:
            sys.exit(f"FAIL: {MANIFEST}: {fx}: {e}")
        if discriminates(p):
            corpus_discriminating.append(f"{fx}:{anchor}")
        if selected:
            expect_anchored += 1
            expect_named += 1 if "`" in template else 0
            expect_discriminating += 1 if discriminates(p) else 0
    if selected:
        expect_symbols += len([r for r in orows if r[0] == fx])

# A property of the FIXTURES, not of the server, so it is checked over
# the whole corpus even when the run is filtered: delete the fixture with
# a non-BMP character before its anchor and nothing anywhere can tell a
# UTF-16 column from a byte offset.
if not corpus_discriminating:
    sys.exit("FAIL: no manifest anchor in the whole corpus sits where the "
             "UTF-16 column differs from BOTH the byte column and the "
             "character column, so no run could tell the three encodings "
             "apart and a server reporting byte offsets would pass. Restore "
             "the fixture with a non-BMP character before its anchor.")

passed = failed = 0
anchored = 0        # ranges asserted against a position derived here
named = 0           # ranges asserted to spell the name the message quotes
sym_named = 0       # symbols whose selectionRange was read back out of source
discriminating = [] # anchors where UTF-16 != bytes and UTF-16 != characters

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

    # --- 1. the golden ------------------------------------------------
    if bless:
        open(golden_path, "wb").write(normalised)
        print(f"blessed {name}")
        # and fall through: blessing rewrites the golden, it does not
        # excuse the checks below, which is what stops a bless from a
        # broken compiler being a way to make this gate green.
    else:
        if not os.path.exists(golden_path):
            print(f"FAIL {name}: no golden at {golden_path}")
            failed += 1
            continue
        want_bytes = open(golden_path, "rb").read()
        if not want_bytes.strip():
            print(f"FAIL {name}: golden is empty - it asserts nothing")
            failed += 1
            continue
        gm, gtail = unframe(want_bytes)
        if not [m for m in gm if m.get("method") == "textDocument/publishDiagnostics"]:
            print(f"FAIL {name}: golden contains no publishDiagnostics frame")
            failed += 1
            continue
        if normalised != want_bytes:
            print(f"FAIL {name}: framed output differs from golden")
            for a, b in zip(msgs, gm):
                if a != b:
                    print("     got: ", json.dumps(a, ensure_ascii=False)[:200])
                    print("     want:", json.dumps(b, ensure_ascii=False)[:200])
                    break
            if len(msgs) != len(gm):
                print(f"     message count: got {len(msgs)}, want {len(gm)}")
            failed += 1
            continue

    # --- the halves a bless cannot satisfy ----------------------------
    pubs = [m for m in msgs if m.get("method") == "textDocument/publishDiagnostics"]
    if not pubs:
        print(f"FAIL {name}: server published no diagnostics notification at all")
        failed += 1
        continue
    diags = pubs[0]["params"]["diagnostics"]

    # LSP defines exactly four severities and this compiler emits two.
    # Said separately from the comparison below because the failure
    # "severity 3 where the protocol allows 1..4 and axiom uses 1 or 2"
    # is worth naming: the projection this replaced - `1 -> E, anything
    # else -> W` - reported 2, 3 and 4 as the same thing.
    illegal = [(d.get("code"), d.get("severity")) for d in diags
               if d.get("severity") not in (1, 2)]
    if illegal:
        print(f"FAIL {name}: published severities outside LSP Error(1) and "
              f"Warning(2): {illegal}")
        failed += 1
        continue

    got = sorted((d.get("severity"),
                  d["code"],
                  d["range"]["start"]["line"],
                  d["range"]["start"]["character"],
                  d["range"]["end"]["character"],
                  first_line(d.get("message", "")))
                 for d in diags)

    try:
        want, spanless_names, probes = expected_for(fx, rows, text)
    except LookupError as e:
        print(f"FAIL {name}: {e}")
        failed += 1
        continue
    want.sort()

    if got != want:
        print(f"FAIL {name}: published diagnostics are not what the source "
              f"and the manifest say")
        if len(got) != len(want):
            print(f"     count: server published {len(got)}, manifest demands "
                  f"{len(want)}")
        for g, w in zip(got, want):
            if g != w:
                print(f"     server:  {g}")
                print(f"     derived: {w}   (from {fx}'s own bytes)")
                break
        else:
            extra = got[len(want):] or want[len(got):]
            print(f"     unmatched: {extra}")
        failed += 1
        continue

    anchored += len(probes)
    for anchor, pr in probes:
        if discriminates(pr):
            discriminating.append(f"{name}:{anchor}")

    # A spanless diagnostic asserts nothing about position, so it has to
    # assert something about content instead: the name it reports must
    # be one the file actually contains.
    bad_spanless = [n for n in spanless_names
                    if not any(n in d.get("message", "") for d in diags)]
    if bad_spanless:
        print(f"FAIL {name}: spanless diagnostic never names {bad_spanless}")
        failed += 1
        continue

    srclines = text.split("\n")
    why = None
    for d in diags:
        why, n = check_range(srclines, d)
        named += n
        if why:
            break
    if why:
        print(f"FAIL {name}: {why}")
        failed += 1
        continue

    # --- the outline, against the hand-written manifest ---------------
    resp = {m["id"]: m for m in msgs if "id" in m}
    if 2 not in resp or not isinstance(resp[2].get("result"), list):
        print(f"FAIL {name}: documentSymbol was not answered with an array")
        failed += 1
        continue
    syms = resp[2]["result"]
    why, n = symbol_invariants(srclines, syms)
    sym_named += n
    if why:
        print(f"FAIL {name}: {why}")
        failed += 1
        continue
    sym_got = [(s["name"], s["kind"], s["selectionRange"]["start"]["line"],
                s["selectionRange"]["start"]["character"],
                s["selectionRange"]["end"]["character"]) for s in syms]
    try:
        sym_want = outline_for(fx, orows, text)
    except LookupError as e:
        print(f"FAIL {name}: outline manifest: {e}")
        failed += 1
        continue
    if sym_got != sym_want:
        print(f"FAIL {name}: outline is not what "
              f"{os.path.basename(OUTLINE)} and the source say")
        print(f"     server:  {sym_got}")
        print(f"     derived: {sym_want}")
        failed += 1
        continue

    ne = len([g for g in got if g[0] == 1])
    nw = len(got) - ne
    print(f"ok   {name} ({ne} error(s), {nw} warning(s), "
          f"{len(probes)} position(s) and {len(sym_want)} symbol(s) derived "
          f"from source)")
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
# Derived the same way the fixtures are: found in the generated text,
# not written down next to the generator.
BIG_ERR = locate(BIG, "nosuchname", 1)
# And its message comes from the same hand-written column the fixtures
# use, so the generated case cannot drift away from the manifest.
BIG_MSG = [render(r[4], "nosuchname", "large-document")
           for r in rows if r[2] == "AX3001" and "%N" in r[4]]
if not BIG_MSG:
    sys.exit("FAIL: the manifest carries no AX3001 message template, so the "
             "large-document case has nothing to hold its message to")
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
bgot = ([(d.get("severity"), d["code"], d["range"]["start"]["line"],
          d["range"]["start"]["character"], d["range"]["end"]["character"],
          first_line(d.get("message", "")))
         for d in bpubs[0]["params"]["diagnostics"]] if bpubs else [])
bwant = [(1, "AX3001", BIG_ERR["line"], BIG_ERR["start"], BIG_ERR["end"],
          BIG_MSG[0])]
why = None
if bp.returncode != 0:
    why = f"server exited {bp.returncode}"
elif bp.stderr:
    why = f"stderr not empty: {bp.stderr[:120]!r}"
elif btail:
    why = f"{len(btail)} unframed trailing bytes"
elif len(bpubs) != 1:
    why = f"expected 1 publishDiagnostics, got {len(bpubs)}"
elif BIG_ERR["line"] != BIG_ERR_LINE:
    why = (f"the generator and the search disagree about where the bad name "
           f"is: {BIG_ERR['line']} vs {BIG_ERR_LINE}")
elif bgot != bwant:
    why = f"body did not arrive intact: {bgot} (want {bwant})"
elif 2 not in bresp or not isinstance(bresp[2].get("result"), list):
    why = "stream lost sync: the request after the large document was not answered"
# A CAPABILITY IS A PROMISE THE CLIENT READS. This session is the only
# one that holds both halves at once - the `initialize` result and an
# answered `textDocument/documentSymbol` - so it is where the two are
# compared. Every fixture sends the request unconditionally, the way no
# editor does; that is what let the server implement documentSymbol
# correctly, advertise nothing but `textDocumentSync`, and satisfy this
# whole gate while a conforming client would never have sent the request
# at all. Neither half of this is re-blessable: both sides come out of
# the server in one run.
elif not isinstance((bresp.get(1, {}).get("result") or {}).get("capabilities"), dict):
    why = "the initialize result carries no capabilities object"
elif bresp[1]["result"]["capabilities"].get("documentSymbolProvider") is not True:
    why = ("the server answers textDocument/documentSymbol and does not "
           "advertise documentSymbolProvider, so a conforming client never "
           "sends it: capabilities were "
           f"{sorted(bresp[1]['result']['capabilities'])}")
elif len(bresp[2]["result"]) != N + 1:
    why = f"outline over the large document has {len(bresp[2]['result'])} symbols, want {N + 1}"

big_named = big_syms = 0
if not why:
    why, big_named = check_range(BIG.split("\n"),
                                 bpubs[0]["params"]["diagnostics"][0])
if not why:
    # 6001 symbols is the only place in this gate where the two
    # manifest-free invariants run at scale, and the only outline check
    # that is not a count.
    why, big_syms = symbol_invariants(BIG.split("\n"), bresp[2]["result"])

if why:
    print(f"FAIL large-document ({len(BIG):,} bytes): {why}")
    failed += 1
else:
    anchored += 1
    named += big_named
    sym_named += big_syms
    print(f"ok   large-document ({len(BIG):,} bytes, "
          f"{N + 1} symbols each spelling its own name, error at "
          f"{BIG_ERR['line']}:{BIG_ERR['start']} derived from the generated text)")
    passed += 1
expect_anchored += 1
expect_named += 1
expect_symbols += N + 1

# ---------------------------------------------------------------------
# Navigation, hover and completion, over two documents written HERE.
#
# MAC-TOOL-2 for the navigation half: an invocation is a reference to
# its declaration. Everything in this section is DERIVED from the two
# documents' own bytes - the declaration's name position for
# `definition`, the declaration's source text and the paragraph above
# it for `hover`, the half-typed word under the cursor for
# `completion` - so no re-bless of any golden can satisfy it. The
# documents live in this file rather than in `tests/lsp/` so their
# positions cannot drift away from the text they describe.
#
# Three requests say each feature has a BOUNDARY: a position on a name
# that nothing declares must answer null for `definition` and for
# `hover`, which is the protocol's "nothing here" and what every other
# word in a file gets; and a document that does not PARSE must still
# complete keywords, because a file is unparseable exactly while a form
# is half written, which is when the question gets asked.
# ---------------------------------------------------------------------
# The head keywords, derived from the parser rather than written down.
#
# `self_host/lsp.ax` carries a copy of this set - it has to, the
# protocol wants labels - and a hand-kept copy of another module's
# vocabulary drifts. So the reference is `parseTopForm`/`parseExpr`'s
# own `kwEq name ...` call sites, and the check is an EQUALITY against
# what the server offers a document that does not parse (where nothing
# else can be offered). A keyword the parser learns and the server
# forgets fails here.
#
# `union`, `foreign` and - since 0.6.0 - `trait` and `impl` are named
# by the parser only in order to REFUSE them (AX2004), so they are not
# expected in a menu. `self_host/lsp.ax`'s `lspKeywords` carries the
# same four, and this equality is what keeps the two in step. `region`
# was the fifth until 2026-09-03; it is a keyword again and is offered.
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PARSER_AX = os.path.join(REPO, "self_host", "parser.ax")
_psrc = open(PARSER_AX, encoding="utf-8").read()
_kwdefs = dict(re.findall(r'\(pub fn \((kw[A-Za-z]+)\) "([^"]+)"\)', _psrc))
_kwlits = set(re.findall(r'kwEq\s+\w+\s+"([^"]+)"', _psrc))
_kwnames = set(re.findall(r'kwEq\s+\w+\s+(kw[A-Za-z]+)', _psrc))
_missing = _kwnames - set(_kwdefs)
if _missing:
    sys.exit(f"FAIL: {PARSER_AX} compares against {sorted(_missing)}, whose "
             f"spelling this file could not read - the keyword reference "
             f"would be short and the equality below would be wrong")
KEYWORDS = sorted((_kwlits | {_kwdefs[n] for n in _kwnames})
                  - {"union", "foreign", "trait", "impl"})
# An extraction that stops matching turns the equality into a comparison
# of two short lists that happen to agree. It is refused before any
# server starts, for the reason the manifest floors are.
if len(KEYWORDS) < 15:
    sys.exit(f"FAIL: derived only {len(KEYWORDS)} head keywords from "
             f"{PARSER_AX} ({KEYWORDS}) - the pattern has stopped matching, "
             f"and an equality against a list this short asserts nothing")

# The imported module lives in a directory of its own rather than in
# `tests/lsp/`, because a `.ax` file there joins the diagnostics sweep
# and needs a golden and a manifest row of its own - and this file is
# not a diagnostics fixture, it is the OTHER SIDE of a navigation.
NAVDIR = tempfile.mkdtemp(prefix="axiom-nav-")
NAVHELPER = """; Add one to a number.
;
; The paragraph a hover has to carry across a module boundary, past the
; blank comment line that separates two of them.
(pub :: bump (-> Int Int))

(pub fn (bump x) (+ x 1))
"""
open(os.path.join(NAVDIR, "NavHelper.ax"), "w", encoding="utf-8").write(NAVHELPER)

NAV = """(import NavHelper)

; A macro that derives a tag function.
(pub macro deriveTag
  ((deriveTag T)
   (pub :: (syntax/join tag T) Int)
   (pub fn ((syntax/join tag T)) 7)))

; A colour, with two constructors.
(data Colour (Red) (Green))

; A point in the plane.
(struct Point (x : Int) (y : Int))

(deriveTag Colour)

; The paragraph that sits above the `::` and not above the definition.
(:: helper Int)
(fn (helper) 3)

(:: main Int)
(fn (main) (+ (+ (tagColour) helper) (bump 1)))
"""
# A declaration taller than a tooltip. `lspClampLines` cuts a hover's
# fence at 40 lines and says so in the fence's own comment syntax, and
# nothing else in this corpus is long enough to reach that.
BIG_N = 45
NAV += ("\n; A type with more constructors than a tooltip should carry.\n"
        "(data Big\n" + "".join(f"  (B{i})\n" for i in range(BIG_N)) + "  )\n")
HOVER_CLAMP = 40
nav_uri = "file://" + os.path.join(NAVDIR, "nav-generated.ax")
NAV_DECL = locate(NAV, "deriveTag", 1)      # the macro's own name
NAV_USE = locate(NAV, "deriveTag", 3)       # the invocation (2 is the rule head)
FN_DECL = locate(NAV, "helper", 2)          # `(fn (helper) 3)`; 1 is the signature
FN_USE = locate(NAV, "helper", 3)           # the call in `main`
DATA_DECL = locate(NAV, "Colour", 1)        # `(data Colour (Red) (Green))`
DATA_USE = locate(NAV, "Colour", 2)         # the macro argument
STRUCT_DECL = locate(NAV, "Point", 1)       # `(struct Point ...)`
BIG_DECL = locate(NAV, "Big", 1)            # `(data Big ...)`, taller than the clamp
IMP_USE = locate(NAV, "bump", 1)            # the imported call
BUMP_DECL = locate(NAVHELPER, "bump", 2)    # its `fn` name, in the OTHER file
NOTHING = locate(NAV, "syntax/join", 1)     # a name no declaration in scope has

def between(src, opener, closer):
    """The source text of one form, sliced out of the document that
    holds it. Hover must quote exactly this, so it is cut here rather
    than written out a second time."""
    i = src.index(opener)
    j = src.index(closer, i)
    return src[i:j]

# What each hover must quote, cut out of the document it belongs to.
MACRO_TEXT = between(NAV, "(pub macro", "\n\n; A colour")
DATA_TEXT = between(NAV, "(data Colour", "\n\n; A point")
STRUCT_TEXT = between(NAV, "(struct Point", "\n\n(deriveTag")
FN_SIG_TEXT = between(NAV, "(:: helper", "\n(fn (helper)")
BUMP_SIG_TEXT = between(NAVHELPER, "(pub :: bump", "\n\n(pub fn")
# The paragraphs, as prose: the same lines with `; ` taken off, which is
# what the server publishes into the markdown below the fence.
def prose(src, form_opener):
    out, i = [], src.index(form_opener)
    while i > 0:
        ls = src.rfind("\n", 0, i - 1) + 1
        line = src[ls:i - 1]
        if not line.startswith(";"):
            break
        out.insert(0, line[1:].lstrip(" ") if line[1:2] == " " else line[1:])
        i = ls
    return "\n".join(out)

MACRO_DOC = prose(NAV, "(pub macro")
DATA_DOC = prose(NAV, "(data Colour")
FN_DOC = prose(NAV, "(:: helper")
BUMP_DOC = prose(NAVHELPER, "(pub :: bump")
# The type a completion `detail` must carry for `helper`, cut out of its
# signature: everything between the name and the closing paren.
HELPER_TYPE = FN_SIG_TEXT[FN_SIG_TEXT.index("helper") + len("helper"):].strip()[:-1].strip()
# The prefix a completion request two characters into `helper` is
# filtering on, read out of the document at the position being sent.
PREFIX_AT = 2
PREFIX = NAV.split("\n")[FN_USE["line"]][FN_USE["start"]:FN_USE["start"] + PREFIX_AT]
# A document mid-form. `(` at EOF cannot parse, so nothing but keywords
# can be offered and the menu is exactly the derived set.
BROKEN = NAV + "\n("

# Every derived string above has to be non-empty and actually present,
# or the assertions built on it are comparisons of "" against "".
for what, text, doc in (("macro", MACRO_TEXT, NAV), ("data", DATA_TEXT, NAV),
                        ("struct", STRUCT_TEXT, NAV), ("fn sig", FN_SIG_TEXT, NAV),
                        ("bump sig", BUMP_SIG_TEXT, NAVHELPER),
                        ("macro doc", MACRO_DOC, None), ("data doc", DATA_DOC, None),
                        ("fn doc", FN_DOC, None), ("bump doc", BUMP_DOC, None),
                        ("helper type", HELPER_TYPE, None),
                        ("prefix", PREFIX, None)):
    if not text.strip() or (doc is not None and text not in doc):
        sys.exit(f"FAIL: the derived {what} text is empty or is not in the "
                 f"document it was cut from ({text!r}) - every hover and "
                 f"completion assertion below rests on it")
if len(BUMP_DOC.split("\n")) < 3:
    sys.exit("FAIL: the imported paragraph is under three lines, so it no "
             "longer spans the blank comment line it exists to test")
# The clamp can only be observed on a declaration that overruns it.
if BIG_N + 2 <= HOVER_CLAMP:
    sys.exit(f"FAIL: `Big` is {BIG_N + 2} lines against a clamp of "
             f"{HOVER_CLAMP} - nothing in this corpus would reach it, and the "
             f"truncation check below would pass on an unclamped server")

def defn(rid, at):
    return {"jsonrpc": "2.0", "id": rid, "method": "textDocument/definition",
            "params": {"textDocument": {"uri": nav_uri},
                       "position": {"line": at["line"], "character": at["start"]}}}

def hov(rid, at, off=0):
    return {"jsonrpc": "2.0", "id": rid, "method": "textDocument/hover",
            "params": {"textDocument": {"uri": nav_uri},
                       "position": {"line": at["line"],
                                    "character": at["start"] + off}}}

def compl(rid, line, char):
    return {"jsonrpc": "2.0", "id": rid, "method": "textDocument/completion",
            "params": {"textDocument": {"uri": nav_uri},
                       "position": {"line": line, "character": char}}}

BROKEN_LINE = len(BROKEN.split("\n")) - 1
nav_session = b"".join(frame(m) for m in [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
    {"jsonrpc": "2.0", "method": "textDocument/didOpen",
     "params": {"textDocument": {"uri": nav_uri, "languageId": "axiom",
                                 "version": 1, "text": NAV}}},
    defn(2, NAV_USE),
    hov(3, NAV_USE),
    defn(4, FN_USE),
    defn(5, DATA_USE),
    defn(6, IMP_USE),
    defn(7, NOTHING),
    hov(10, FN_USE),
    hov(11, DATA_USE),
    hov(12, STRUCT_DECL),
    hov(13, IMP_USE),
    hov(14, NOTHING),
    hov(18, BIG_DECL),
    # Two characters into `helper`: the prefix is the document's own
    # bytes, and every label must start with it.
    compl(15, FN_USE["line"], FN_USE["start"] + PREFIX_AT),
    # On the first byte of a name, so the prefix is empty and the whole
    # menu - keywords, this document, the imported module - is offered.
    compl(16, NAV_USE["line"], NAV_USE["start"]),
    {"jsonrpc": "2.0", "method": "textDocument/didChange",
     "params": {"textDocument": {"uri": nav_uri, "version": 2},
                "contentChanges": [{"text": BROKEN}]}},
    compl(17, BROKEN_LINE, 1),
    {"jsonrpc": "2.0", "id": 8, "method": "shutdown", "params": None},
    {"jsonrpc": "2.0", "method": "exit", "params": None},
])

np_ = subprocess.run([stage1, "lsp"], input=nav_session, capture_output=True,
                     cwd=fixdir)
nmsgs, ntail = unframe(np_.stdout)
nresp = {m["id"]: m for m in nmsgs if "id" in m}
nwhy = ""
caps = (nresp.get(1, {}).get("result") or {}).get("capabilities") or {}

def rng(at):
    return {"start": {"line": at["line"], "character": at["start"]},
            "end": {"line": at["line"], "character": at["end"]}}

def landed(rid, uri, at):
    """Did request `rid` answer a Location at `at` in `uri`? Returns the
    reason it did not, or ""."""
    r = nresp.get(rid, {}).get("result")
    if r is None:
        return f"request {rid} answered null"
    if r.get("uri") != uri:
        return f"request {rid} answered {r.get('uri')}, want {uri}"
    if r.get("range") != rng(at):
        return f"request {rid} answered range {r.get('range')}, want {rng(at)}"
    return ""

def hover_says(rid, wants, at):
    """Every string in `wants` must be in the hover's markdown, and the
    hover's `range` must be the WORD under the cursor - not the
    declaration's own span, which is in another part of the file and,
    for an imported name, in another file entirely."""
    r = nresp.get(rid, {}).get("result")
    if r is None:
        return f"request {rid} answered null"
    value = (r.get("contents") or {}).get("value")
    if not isinstance(value, str):
        return f"request {rid} answered contents {r.get('contents')!r}"
    if "```axiom" not in value:
        return f"request {rid} answered no axiom code fence"
    for w in wants:
        if w not in value:
            return (f"request {rid} did not carry {w!r};\n"
                    f"          it answered {value!r}")
    if r.get("range") != rng(at):
        return (f"request {rid} covered {r.get('range')}, want the word at "
                f"{rng(at)}")
    return ""

def items(rid):
    r = nresp.get(rid, {}).get("result") or {}
    return r, r.get("items") or []

def offers(rid, label, kind, detail=None):
    """Is `label` in this menu, with the kind and detail it must have?"""
    _, its = items(rid)
    for it in its:
        if it.get("label") != label:
            continue
        if it.get("kind") != kind:
            return (f"request {rid} offered {label!r} as kind "
                    f"{it.get('kind')}, want {kind}")
        if detail is not None and it.get("detail") != detail:
            return (f"request {rid} offered {label!r} with detail "
                    f"{it.get('detail')!r}, want {detail!r}")
        return ""
    return (f"request {rid} did not offer {label!r} at all "
            f"(it offered {sorted(i.get('label') for i in its)[:12]}...)")

want_range = rng(NAV_DECL)
helper_uri = "file://" + os.path.join(NAVDIR, "NavHelper.ax")
compl_caps = caps.get("completionProvider")
_, its15 = items(15)
_, its16 = items(16)
r17, its17 = items(17)
if np_.returncode != 0:
    nwhy = f"the server exited {np_.returncode}"
elif ntail:
    nwhy = f"{len(ntail)} trailing bytes after the last frame"
elif caps.get("definitionProvider") is not True:
    nwhy = ("the server answers textDocument/definition and does not advertise "
            f"definitionProvider: capabilities were {sorted(caps)}")
elif caps.get("hoverProvider") is not True:
    nwhy = ("the server answers textDocument/hover and does not advertise "
            f"hoverProvider: capabilities were {sorted(caps)}")
elif not isinstance(compl_caps, dict):
    nwhy = ("the server answers textDocument/completion and does not advertise "
            f"completionProvider: capabilities were {sorted(caps)}")
elif compl_caps.get("triggerCharacters") != ["("]:
    nwhy = (f"completionProvider triggers on "
            f"{compl_caps.get('triggerCharacters')!r}, want ['('] - a client "
            f"sends an unprompted request only at a character it names")
elif compl_caps.get("resolveProvider") is not False:
    nwhy = ("completionProvider claims resolveProvider "
            f"{compl_caps.get('resolveProvider')!r}; there is no "
            "completionItem/resolve, and a client that believed it would wait "
            "for a round trip that never comes")
elif landed(2, nav_uri, NAV_DECL):
    nwhy = "macro: " + landed(2, nav_uri, NAV_DECL)
elif hover_says(3, ["```axiom", MACRO_TEXT, MACRO_DOC], NAV_USE):
    nwhy = "macro hover: " + hover_says(3, ["```axiom", MACRO_TEXT, MACRO_DOC], NAV_USE)
elif landed(4, nav_uri, FN_DECL):
    nwhy = "same-file fn: " + landed(4, nav_uri, FN_DECL)
elif landed(5, nav_uri, DATA_DECL):
    nwhy = "same-file data: " + landed(5, nav_uri, DATA_DECL)
elif landed(6, helper_uri, BUMP_DECL):
    nwhy = "imported fn: " + landed(6, helper_uri, BUMP_DECL)
elif nresp.get(7, {}).get("result") is not None:
    nwhy = f"a name no declaration has answered {nresp[7]['result']}, want null"
# A `fn` hovers as its SIGNATURE and its paragraph, and the paragraph is
# above the `::` rather than above the definition - so a hover read at
# the wrong one of the two carries an empty block.
elif hover_says(10, [FN_SIG_TEXT, FN_DOC], FN_USE):
    nwhy = "fn hover: " + hover_says(10, [FN_SIG_TEXT, FN_DOC], FN_USE)
elif "(fn (helper) 3)" in nresp[10]["result"]["contents"]["value"]:
    nwhy = ("fn hover quoted the body; a `fn` hovers as its type, and the "
            "body is what `definition` is for")
elif hover_says(11, [DATA_TEXT, DATA_DOC], DATA_USE):
    nwhy = "data hover: " + hover_says(11, [DATA_TEXT, DATA_DOC], DATA_USE)
elif hover_says(12, [STRUCT_TEXT], STRUCT_DECL):
    nwhy = "struct hover: " + hover_says(12, [STRUCT_TEXT], STRUCT_DECL)
# The imported one is the whole shape at once: another file's bytes,
# another file's paragraph, the module it came from, and a range in
# THIS document.
elif hover_says(13, [BUMP_SIG_TEXT, BUMP_DOC, "NavHelper"], IMP_USE):
    nwhy = "imported hover: " + hover_says(13, [BUMP_SIG_TEXT, BUMP_DOC, "NavHelper"], IMP_USE)
elif nresp.get(14, {}).get("result") is not None:
    nwhy = (f"hover on a name no declaration has answered "
            f"{nresp[14]['result']}, want null")
elif hover_says(18, ["(data Big", "(B0)", "; ..."], BIG_DECL):
    nwhy = "clamped hover: " + hover_says(18, ["(data Big", "(B0)", "; ..."], BIG_DECL)
elif f"(B{BIG_N - 1})" in nresp[18]["result"]["contents"]["value"]:
    nwhy = (f"hover on a {BIG_N + 2}-line declaration carried its last "
            f"constructor; the fence is clamped at {HOVER_CLAMP} lines, "
            f"because a tooltip that long is a wall over the code being read")
elif nresp[18]["result"]["contents"]["value"].count("\n") > HOVER_CLAMP + 6:
    nwhy = (f"the clamped hover still ran to "
            f"{nresp[18]['result']['contents']['value'].count(chr(10))} lines")
elif [i for i in its15 if not str(i.get("label", "")).startswith(PREFIX)]:
    nwhy = (f"completion filtered on {PREFIX!r} still offered "
            f"{[i['label'] for i in its15 if not str(i.get('label','')).startswith(PREFIX)][:6]}")
elif offers(15, "helper", 3, HELPER_TYPE):
    nwhy = "prefix completion: " + offers(15, "helper", 3, HELPER_TYPE)
elif (nresp.get(15, {}).get("result") or {}).get("isIncomplete") is not True:
    nwhy = ("a prefix-filtered completion answered isIncomplete false; a "
            "client is then entitled to filter that list itself and stop "
            "asking, which freezes the menu on the first letter")
elif offers(16, "Colour", 13):
    nwhy = "empty-prefix completion: " + offers(16, "Colour", 13)
elif offers(16, "Red", 20):
    nwhy = "empty-prefix completion: " + offers(16, "Red", 20)
elif offers(16, "Point", 22):
    nwhy = "empty-prefix completion: " + offers(16, "Point", 22)
elif offers(16, "deriveTag", 3):
    nwhy = "empty-prefix completion: " + offers(16, "deriveTag", 3)
elif offers(16, "bump", 3, "NavHelper"):
    nwhy = "empty-prefix completion: " + offers(16, "bump", 3, "NavHelper")
elif "tagColour" in [i.get("label") for i in its16]:
    nwhy = ("completion offered `tagColour`, which only exists after macro "
            "expansion - these requests read the raw parse tree (MAC-TOOL-3)")
# The document no longer parses, so nothing but keywords CAN be offered,
# and the menu is exactly the set derived from parser.ax.
elif [i.get("label") for i in its17] != KEYWORDS:
    nwhy = (f"a document that does not parse offered "
            f"{[i.get('label') for i in its17]},\n          want the "
            f"{len(KEYWORDS)} head keywords parser.ax dispatches on: {KEYWORDS}")
elif {i.get("kind") for i in its17} != {14}:
    nwhy = (f"keywords were offered as kinds {sorted({i.get('kind') for i in its17})}, "
            f"want 14 (CompletionItemKind.Keyword) alone")
elif r17.get("isIncomplete") is not True:
    nwhy = "the unparseable document's completion answered isIncomplete false"

if nwhy:
    print(f"FAIL navigation: {nwhy}")
    failed += 1
else:
    print("ok   navigation (a macro invocation, a same-file `fn` and `data`, an "
          f"imported `fn` in {os.path.basename(helper_uri)}, hover quoting the "
          "declaration, and null for a name nothing declares)")
    print(f"ok   hover      (a macro, a `fn` as its signature, a `data`, a "
          f"`struct`, and `bump` quoted out of NavHelper.ax with its module "
          f"and its paragraph; 5 form texts and 4 paragraphs cut from the "
          f"documents, ranges on the WORD not the declaration; null for a "
          f"name nothing declares; a {BIG_N + 2}-line `data` cut at "
          f"{HOVER_CLAMP})")
    print(f"ok   completion ({len(its15)} item(s) all starting {PREFIX!r} with "
          f"`helper` : {HELPER_TYPE!r}, {len(its16)} at an empty prefix "
          f"carrying this document's 4 kinds and NavHelper's `bump`, and "
          f"exactly the {len(KEYWORDS)} keywords derived from parser.ax on a "
          f"document that does not parse)")
    passed += 3
shutil.rmtree(NAVDIR, ignore_errors=True)

# =====================================================================
# SECTION NAV TESTS: references, rename, document highlights, and the
# local-binding half of definition. Owned by that section of
# self_host/lsp.ax; every expected answer here is DERIVED from the
# documents' own bytes, never read from a golden.
# =====================================================================

# Four documents written HERE, in a directory of their own for the
# reason NavHelper.ax has one: RefHelper.ax, imported by NavMain.ax;
# NavMain.ax, which binds every kind of local the walk knows and
# declares the names the others reference; NavUser.ax, which imports
# NavMain and references its `fn` and its constructor, so the
# cross-file half of `references` and `rename` has a second open
# document to find; and NavBroken.ax, NavMain with an unclosed paren,
# on which every request must answer null without the session dying.
# RefHelper.ax is opened too, so the reverse direction - the cursor on
# an IMPORTED name, whose declaring file happens to be open - has a
# document to answer from.
#
# Every position is found as a WHOLE identifier (`ident_at`), because
# `locate` finds substrings and `rad` is inside `radius`. Every
# expected list is built here from those positions and compared for
# EQUALITY - order, uri and range - so a server that finds one
# occurrence too many, or one too few, or lists another document's
# first, fails. The rename is applied in Python to the documents' own
# bytes, and the result is opened in a second session: the checker
# publishing NOTHING for the renamed pair is the proof that every
# occurrence was found, since a missed one would be AX3001 at the old
# spelling.
NAVREF_DIR = tempfile.mkdtemp(prefix="axiom-nav-refs-")
REF_HELPER = """; Double a number.
(pub :: twice (-> Int Int))

(pub fn (twice x) (* x 2))
"""
NAV_MAIN = """(import RefHelper)

; A shape with two constructors, one of them carrying a field.
(pub data Shape (Dot) (Circle Int))

; A struct whose field names the type above, and an alias that names
; it too: two of the type positions a rename of it has to reach.
(pub struct Box (top : Shape) (n : Int))

(pub type Shapes = [Shape])

; Two parameters; the second is shadowed by a `let` whose value
; still reads the parameter, because a `let` is not recursive.
(pub :: area (-> Int Int Int))

(pub fn (area pw ph)
  (let ((ph (+ ph 1)))
    (+ ph (twice pw))))

; A mutable binding written by `set`.
(pub :: count (-> Int Int))

(pub fn (count n)
  (let ((mut acc 0))
    {
      (set acc (+ acc n))
      acc
    }))

; A `match` with a constructor head and a pattern binder.
(pub :: radius (-> Shape Int))

(pub fn (radius s)
  (match s
    ((Dot) 0)
    ((Circle rad) (area rad rad))))

; A lambda with two parameters.
(pub :: apply2 Int)

(pub fn (apply2) ((lambda (lx ly) (+ lx ly)) 1 2))

(:: main Int)

(fn (main) (+ (count 3) (+ (apply2) (radius (Circle 4)))))
"""
NAV_USER = """(import NavMain)

; A second document that imports the first and reads its names.
(:: useArea Int)

(fn (useArea) (+ (area 2 3) (radius (Circle 9))))
"""
NAV_BROKEN = NAV_MAIN + "\n("
for _name, _text in (("RefHelper.ax", REF_HELPER), ("NavMain.ax", NAV_MAIN),
                     ("NavUser.ax", NAV_USER)):
    open(os.path.join(NAVREF_DIR, _name), "w", encoding="utf-8").write(_text)
A_URI = "file://" + os.path.join(NAVREF_DIR, "NavMain.ax")
B_URI = "file://" + os.path.join(NAVREF_DIR, "NavUser.ax")
C_URI = "file://" + os.path.join(NAVREF_DIR, "NavBroken.ax")
D_URI = "file://" + os.path.join(NAVREF_DIR, "RefHelper.ax")

# The lexer's identifier bytes, so a name is found only where the
# compiler would read it as one token.
IDENT_CHARS = r"A-Za-z0-9_'!*+/<>=%&|^-"

def ident_at(src, name, n):
    """The n-th occurrence of `name` as a WHOLE identifier, in LSP
    coordinates plus the byte index it starts at."""
    pat = re.compile(f"(?<![{IDENT_CHARS}])" + re.escape(name) + f"(?![{IDENT_CHARS}])")
    ms = list(pat.finditer(src))
    if len(ms) < n:
        raise LookupError(f"identifier {name!r} has {len(ms)} occurrence(s), "
                          f"fewer than {n}")
    idx = ms[n - 1].start()
    ln, text, col = line_of(src, idx)
    start = u16(text[:col])
    return {"line": ln, "start": start, "end": start + u16(name), "byte": idx}

def ident_count(src, name):
    pat = re.compile(f"(?<![{IDENT_CHARS}])" + re.escape(name) + f"(?![{IDENT_CHARS}])")
    return len(pat.findall(src))

def idents(src, name, n):
    return [ident_at(src, name, k) for k in range(1, n + 1)]

def pair_text(src, byte):
    """The `(name value)` pair a `let` binder at `byte` sits in: back to
    its `(`, forward to the matching `)`."""
    o = src.rfind("(", 0, byte)
    depth, i = 0, o
    while i < len(src):
        if src[i] == "(":
            depth += 1
        elif src[i] == ")":
            depth -= 1
            if depth == 0:
                return src[o:i + 1]
        i += 1
    return ""

# The corpus, counted: each name must occur exactly as often as the
# assertions below assume, or a position lands on the wrong occurrence
# and the check passes or fails for the wrong reason.
NAV_COUNTS = {"ph": 4, "pw": 2, "area": 3, "acc": 4, "lx": 2, "rad": 3,
              "twice": 1, "Circle": 3, "count": 3, "surface": 0, "total": 0,
              "Shape": 4, "Blob": 0}
for _n, _c in NAV_COUNTS.items():
    if ident_count(NAV_MAIN, _n) != _c:
        sys.exit(f"FAIL: NavMain.ax spells `{_n}` {ident_count(NAV_MAIN, _n)} "
                 f"time(s) as an identifier, this file assumes {_c}")
for _n, _c in (("area", 1), ("Circle", 1), ("useArea", 2), ("surface", 0)):
    if ident_count(NAV_USER, _n) != _c:
        sys.exit(f"FAIL: NavUser.ax spells `{_n}` {ident_count(NAV_USER, _n)} "
                 f"time(s), this file assumes {_c}")
if ident_count(REF_HELPER, "twice") != 2:
    sys.exit("FAIL: RefHelper.ax must spell `twice` exactly twice")
if not (NAV_MAIN.isascii() and NAV_USER.isascii()):
    sys.exit("FAIL: the rename is applied below with UTF-16 units read as "
             "characters, which is only true of ASCII documents")

PH = idents(NAV_MAIN, "ph", 4)            # header, let binder, let value, body
PW = idents(NAV_MAIN, "pw", 2)            # header, `(twice pw)`
AREA_A = idents(NAV_MAIN, "area", 3)      # signature, fn, the call in radius
AREA_B = idents(NAV_USER, "area", 1)
ACC = idents(NAV_MAIN, "acc", 4)          # `(mut acc 0)`, the set target, two reads
LX = idents(NAV_MAIN, "lx", 2)            # lambda parameter, its read
RAD = idents(NAV_MAIN, "rad", 3)          # pattern binder, two reads
TWICE_A = idents(NAV_MAIN, "twice", 1)
TWICE_D = idents(REF_HELPER, "twice", 2)  # signature, fn
CIRCLE_A = idents(NAV_MAIN, "Circle", 3)  # constructor, pattern head, expression
CIRCLE_B = idents(NAV_USER, "Circle", 1)
# The type: its declaration, then three TYPE POSITIONS - a struct
# field, the alias's target, the signature of `radius` - none of which
# is a node with a span, so each is a place the walk has to read out
# of the bytes. The `Int` beside it in that signature is a builtin
# type position: an occurrence, never renamable.
SHAPE_A = idents(NAV_MAIN, "Shape", 4)
_radius_sig = NAV_MAIN.index("(pub :: radius")
INT_IN_SIG = next(p for p in idents(NAV_MAIN, "Int", ident_count(NAV_MAIN, "Int"))
                  if p["byte"] > _radius_sig)
if not (SHAPE_A[0]["byte"] < NAV_MAIN.index("(pub struct Box") < SHAPE_A[1]["byte"]
        < NAV_MAIN.index("(pub type Shapes") < SHAPE_A[2]["byte"] < _radius_sig < SHAPE_A[3]["byte"]
        < INT_IN_SIG["byte"] < NAV_MAIN.index("\n", _radius_sig)):
    sys.exit("FAIL: NavMain.ax no longer spells `Shape` in the four positions - data, "
             "struct field, alias, signature - the type-position checks are written for")
# THE CONSTRUCTOR CHECKS' OWN FLOOR. `Shape` and `Circle` are declared
# on ONE line, and every constructor assertion below rests on that: a
# server that answered the `data`'s name span instead of the
# constructor's would land on the same line, one column range away, and
# an equality against a whole-identifier position is the only thing
# that can tell the two apart. If the corpus ever splits them, that
# ablation stops being reachable and these checks weaken without
# failing - which is the shape this gate refuses everywhere else.
if SHAPE_A[0]["line"] != CIRCLE_A[0]["line"]:
    sys.exit("FAIL: NavMain.ax no longer declares `Shape` and its constructors on "
             "one line - a wrong answer of the `data`'s span would then differ in "
             "LINE from the right one, and the constructor checks below could not "
             "tell an off-by-a-declaration answer from a correct one")
if not (SHAPE_A[0]["byte"] < CIRCLE_A[0]["byte"]
        < NAV_MAIN.index("\n", SHAPE_A[0]["byte"])):
    sys.exit("FAIL: NavMain.ax's first `Circle` is not the one inside "
             "`(pub data Shape ...)` - every constructor position below is written "
             "for that occurrence being the declaration")
# The form a constructor hover must quote: the WHOLE `data`, because
# that is where a reader finds the constructor's siblings and its field
# types. Cut from the document, like every other hover text here.
SHAPE_DATA_TEXT = between(NAV_MAIN, "(pub data Shape", "\n\n; A struct")
SHAPE_DOC = "A shape with two constructors, one of them carrying a field."
if "(Circle Int)" not in SHAPE_DATA_TEXT or SHAPE_DOC not in NAV_MAIN:
    sys.exit(f"FAIL: the derived `data Shape` form {SHAPE_DATA_TEXT!r} or its "
             f"paragraph is not in NavMain.ax - the constructor hovers rest on both")
KW_MATCH = ident_at(NAV_MAIN, "match", 1)
KW_LET = ident_at(NAV_MAIN, "let", 1)
LITERAL = locate(NAV_MAIN, "((Dot) 0)", 1)
LITERAL = {"line": LITERAL["line"], "start": LITERAL["end"] - 2}  # the `0`
# The type hover must show for `pw`: parameter 0 of `area`'s own
# signature, read out of its text.
AREA_SIG = between(NAV_MAIN, "(pub :: area", "\n\n(pub fn (area")
_arrow = re.search(r"\(->\s+(.+)\)\)$", AREA_SIG)
PARAM_TYPE = _arrow.group(1).split()[0] if _arrow else ""
# The binding pair hover must quote for the let-bound `ph`.
LET_TEXT = pair_text(NAV_MAIN, PH[1]["byte"])
for what, text in (("area signature", AREA_SIG), ("parameter type", PARAM_TYPE),
                   ("let pair", LET_TEXT)):
    if not text.strip() or (what != "parameter type" and text not in NAV_MAIN):
        sys.exit(f"FAIL: the derived {what} is empty or not in NavMain.ax "
                 f"({text!r}) - the hover assertions below rest on it")
if "ph" not in LET_TEXT or LET_TEXT.count("(") < 2:
    sys.exit(f"FAIL: the derived let pair {LET_TEXT!r} is not a `(name value)` pair")

def nav_req(rid, method, uri, at, extra=None):
    p = {"textDocument": {"uri": uri},
         "position": {"line": at["line"], "character": at["start"]}}
    if extra:
        p.update(extra)
    return {"jsonrpc": "2.0", "id": rid, "method": method, "params": p}

def nav_open(uri, text):
    return {"jsonrpc": "2.0", "method": "textDocument/didOpen",
            "params": {"textDocument": {"uri": uri, "languageId": "axiom",
                                        "version": 1, "text": text}}}

def refs(rid, uri, at, incl):
    return nav_req(rid, "textDocument/references", uri, at,
                   {"context": {"includeDeclaration": incl}})

def hilite(rid, uri, at):
    return nav_req(rid, "textDocument/documentHighlight", uri, at)

def prep(rid, uri, at):
    return nav_req(rid, "textDocument/prepareRename", uri, at)

def ren(rid, uri, at, new):
    return nav_req(rid, "textDocument/rename", uri, at, {"newName": new})

nav_session2 = b"".join(frame(m) for m in [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
    nav_open(A_URI, NAV_MAIN), nav_open(B_URI, NAV_USER),
    nav_open(C_URI, NAV_BROKEN), nav_open(D_URI, REF_HELPER),
    # references
    refs(2, A_URI, PH[0], True), refs(3, A_URI, PH[0], False),
    refs(4, A_URI, PH[1], True), refs(5, A_URI, PH[3], False),
    refs(6, A_URI, AREA_A[1], True), refs(7, A_URI, AREA_A[1], False),
    refs(8, A_URI, TWICE_A[0], True), refs(9, A_URI, CIRCLE_A[0], True),
    refs(10, A_URI, KW_MATCH, True), refs(11, C_URI, PH[0], True),
    # highlights
    hilite(12, A_URI, ACC[2]), hilite(13, A_URI, LX[1]), hilite(14, A_URI, RAD[0]),
    hilite(15, A_URI, LITERAL), hilite(16, C_URI, ACC[2]),
    # rename
    prep(17, A_URI, PW[1]), prep(18, A_URI, TWICE_A[0]), prep(19, A_URI, KW_LET),
    prep(20, C_URI, PW[1]),
    ren(21, A_URI, AREA_A[1], "surface"), ren(22, A_URI, PW[1], "1abc"),
    ren(23, A_URI, PW[1], "ph"), ren(24, A_URI, AREA_A[1], "count"),
    ren(25, A_URI, AREA_A[1], "useArea"), ren(26, C_URI, PW[1], "zz"),
    ren(27, A_URI, ACC[2], "total"),
    # the local half of definition and hover
    nav_req(28, "textDocument/definition", A_URI, PH[3]),
    nav_req(29, "textDocument/definition", A_URI, PH[2]),
    nav_req(30, "textDocument/hover", A_URI, PW[1]),
    nav_req(31, "textDocument/hover", A_URI, PH[3]),
    nav_req(32, "textDocument/hover", C_URI, PW[1]),
    nav_req(33, "textDocument/definition", C_URI, PH[3]),
    # type positions: from the signature, from the declaration
    refs(35, A_URI, SHAPE_A[3], True), hilite(36, A_URI, SHAPE_A[0]),
    prep(37, A_URI, INT_IN_SIG), ren(38, A_URI, SHAPE_A[1], "Blob"),
    ren(39, A_URI, SHAPE_A[0], "Int"),
    # constructors: definition, declaration, typeDefinition and hover,
    # in this document and across the import. 40-42, 46 and 48 are the
    # local half; 43-45 and 47 the imported one, so a build that
    # answered only for the open document fails on those alone.
    nav_req(40, "textDocument/definition", A_URI, CIRCLE_A[1]),
    nav_req(41, "textDocument/definition", A_URI, CIRCLE_A[2]),
    nav_req(42, "textDocument/declaration", A_URI, CIRCLE_A[1]),
    nav_req(43, "textDocument/definition", B_URI, CIRCLE_B[0]),
    nav_req(44, "textDocument/declaration", B_URI, CIRCLE_B[0]),
    nav_req(45, "textDocument/typeDefinition", B_URI, CIRCLE_B[0]),
    nav_req(46, "textDocument/hover", A_URI, CIRCLE_A[1]),
    nav_req(47, "textDocument/hover", B_URI, CIRCLE_B[0]),
    nav_req(48, "textDocument/definition", A_URI, CIRCLE_A[0]),
    nav_req(49, "textDocument/definition", C_URI, CIRCLE_A[1]),
    {"jsonrpc": "2.0", "id": 34, "method": "shutdown", "params": None},
    {"jsonrpc": "2.0", "method": "exit", "params": None},
])
rp = subprocess.run([stage1, "lsp"], input=nav_session2, capture_output=True,
                    cwd=NAVREF_DIR)
rmsgs, rtail = unframe(rp.stdout)
rresp = {m["id"]: m for m in rmsgs if "id" in m}
rcaps = (rresp.get(1, {}).get("result") or {}).get("capabilities") or {}
rpubs = {}
for m in rmsgs:
    if m.get("method") == "textDocument/publishDiagnostics":
        rpubs.setdefault(m["params"]["uri"], m["params"]["diagnostics"])

def loc(uri, at):
    return (uri, rng(at))

def got_locs(rid):
    r = rresp.get(rid, {}).get("result")
    if not isinstance(r, list):
        return r
    return [(x.get("uri"), x.get("range")) for x in r]

def want_locs(rid, want):
    """Reason request `rid` did not answer exactly `want`, or ""."""
    g = got_locs(rid)
    if g != want:
        return f"request {rid} answered {g!r}, want {want!r}"
    return ""

def want_null(rid, what):
    r = rresp.get(rid, {}).get("result", "unanswered")
    if r is not None:
        return f"{what} (request {rid}) answered {r!r:.160}, want null"
    return ""

def got_hilites(rid):
    r = rresp.get(rid, {}).get("result")
    if not isinstance(r, list):
        return r
    return [(x.get("range"), x.get("kind")) for x in r]

def want_hilites(rid, pairs):
    g = got_hilites(rid)
    want = [(rng(at), kind) for at, kind in pairs]
    if g != want:
        return f"request {rid} answered {g!r}, want {want!r}"
    return ""

def got_edits(rid):
    r = rresp.get(rid, {}).get("result")
    if not isinstance(r, dict) or not isinstance(r.get("changes"), dict):
        return r
    return {u: [(e.get("range"), e.get("newText")) for e in es]
            for u, es in r["changes"].items()}

def apply_edits(text, edits):
    """Apply TextEdits to an ASCII document, last first so earlier
    offsets stay valid; refuses overlapping edits."""
    starts, at = [], 0
    for line in text.split("\n"):
        starts.append(at)
        at += len(line) + 1
    spans = sorted(((starts[e["range"]["start"]["line"]] + e["range"]["start"]["character"],
                     starts[e["range"]["end"]["line"]] + e["range"]["end"]["character"],
                     e["newText"]) for e in edits), reverse=True)
    for (s1, _, _), (_, e2, _) in zip(spans, spans[1:]):
        if s1 < e2:
            return None
    for s, e, t in spans:
        text = text[:s] + t + text[e:]
    return text

def nav_hover(rid, wants, at):
    r = rresp.get(rid, {}).get("result")
    if r is None:
        return f"request {rid} answered null"
    value = (r.get("contents") or {}).get("value")
    if not isinstance(value, str) or "```axiom" not in value:
        return f"request {rid} answered contents {r.get('contents')!r}"
    for w in wants:
        if w not in value:
            return f"request {rid} did not carry {w!r}; it answered {value!r}"
    if r.get("range") != rng(at):
        return f"request {rid} covered {r.get('range')}, want the word at {rng(at)}"
    return ""

def nav_landed(rid, uri, at):
    r = rresp.get(rid, {}).get("result")
    if r is None:
        return f"request {rid} answered null"
    if r.get("uri") != uri or r.get("range") != rng(at):
        return f"request {rid} answered {r!r}, want {loc(uri, at)!r}"
    return ""

rename_caps = rcaps.get("renameProvider")
SURFACE_EDITS = {A_URI: [(rng(a), "surface") for a in AREA_A],
                 B_URI: [(rng(AREA_B[0]), "surface")]}
TOTAL_EDITS = {A_URI: [(rng(a), "total") for a in ACC]}
BLOB_EDITS = {A_URI: [(rng(s), "Blob") for s in SHAPE_A]}
nwhy = ""
if rp.returncode != 0:
    nwhy = f"the server exited {rp.returncode}: {rp.stderr[:200]!r}"
elif rp.stderr:
    nwhy = f"stderr not empty: {rp.stderr[:200]!r}"
elif rtail:
    nwhy = f"{len(rtail)} trailing bytes after the last frame"
elif 34 not in rresp:
    nwhy = "the session never answered shutdown - a request killed the server"
elif rcaps.get("referencesProvider") is not True:
    nwhy = f"referencesProvider is not advertised: capabilities were {sorted(rcaps)}"
elif rcaps.get("documentHighlightProvider") is not True:
    nwhy = f"documentHighlightProvider is not advertised: capabilities were {sorted(rcaps)}"
elif not isinstance(rename_caps, dict) or rename_caps.get("prepareProvider") is not True:
    nwhy = (f"renameProvider is {rename_caps!r}, want an object with "
            f"prepareProvider true so a client asks before opening a rename box")
# The corpus is a real program: three of the four documents check
# clean, and the broken one reports its parse error - so the rename's
# "still checks clean" proof below is not vacuous.
elif any(rpubs.get(u) for u in (A_URI, B_URI, D_URI)):
    nwhy = ("the navigation corpus does not check clean before any rename: "
            f"{[(os.path.basename(u), rpubs.get(u)) for u in (A_URI, B_URI, D_URI) if rpubs.get(u)]!r:.300}")
elif not rpubs.get(C_URI):
    nwhy = "NavBroken.ax published no diagnostic, so it is not the unparseable document it is meant to be"
# --- references -----------------------------------------------------
# (a) The shadowed parameter: the header and the let's VALUE, never the
# let's own binder or the body's read, which belong to the inner `ph`.
elif want_locs(2, [loc(A_URI, PH[0]), loc(A_URI, PH[2])]):
    nwhy = "param `ph` with declaration: " + want_locs(2, [loc(A_URI, PH[0]), loc(A_URI, PH[2])])
elif want_locs(3, [loc(A_URI, PH[2])]):
    nwhy = "param `ph` without declaration: " + want_locs(3, [loc(A_URI, PH[2])])
elif want_locs(4, [loc(A_URI, PH[1]), loc(A_URI, PH[3])]):
    nwhy = "let `ph` with declaration: " + want_locs(4, [loc(A_URI, PH[1]), loc(A_URI, PH[3])])
elif want_locs(5, [loc(A_URI, PH[3])]):
    nwhy = "let `ph` from its read, without declaration: " + want_locs(5, [loc(A_URI, PH[3])])
# (b) The top-level fn: its signature, its definition, its call, and the
# call in the OTHER open document, under that document's uri, last.
elif want_locs(6, [loc(A_URI, a) for a in AREA_A] + [loc(B_URI, AREA_B[0])]):
    nwhy = "`area` across two documents: " + want_locs(6, [loc(A_URI, a) for a in AREA_A] + [loc(B_URI, AREA_B[0])])
elif want_locs(7, [loc(A_URI, AREA_A[2]), loc(B_URI, AREA_B[0])]):
    nwhy = "`area` references only: " + want_locs(7, [loc(A_URI, AREA_A[2]), loc(B_URI, AREA_B[0])])
# The reverse: the cursor on an imported name whose module is open.
elif want_locs(8, [loc(A_URI, TWICE_A[0])] + [loc(D_URI, d) for d in TWICE_D]):
    nwhy = "imported `twice` with its open module: " + want_locs(8, [loc(A_URI, TWICE_A[0])] + [loc(D_URI, d) for d in TWICE_D])
elif want_locs(9, [loc(A_URI, c) for c in CIRCLE_A] + [loc(B_URI, CIRCLE_B[0])]):
    nwhy = "constructor `Circle` in a pattern, an expression and another document: " + want_locs(9, [loc(A_URI, c) for c in CIRCLE_A] + [loc(B_URI, CIRCLE_B[0])])
elif want_null(10, "references on the keyword `match`"):
    nwhy = want_null(10, "references on the keyword `match`")
elif want_null(11, "references on the document that does not parse"):
    nwhy = want_null(11, "references on the document that does not parse")
# --- document highlights --------------------------------------------
# (c) Write on the binder and the `set` target, Read on the reads.
elif want_hilites(12, [(ACC[0], 3), (ACC[1], 3), (ACC[2], 2), (ACC[3], 2)]):
    nwhy = "`acc` highlights: " + want_hilites(12, [(ACC[0], 3), (ACC[1], 3), (ACC[2], 2), (ACC[3], 2)])
elif want_hilites(13, [(LX[0], 3), (LX[1], 2)]):
    nwhy = "lambda parameter highlights (its span recovered from the bytes): " + want_hilites(13, [(LX[0], 3), (LX[1], 2)])
elif want_hilites(14, [(RAD[0], 3), (RAD[1], 2), (RAD[2], 2)]):
    nwhy = "pattern binder highlights: " + want_hilites(14, [(RAD[0], 3), (RAD[1], 2), (RAD[2], 2)])
elif want_null(15, "documentHighlight on a literal"):
    nwhy = want_null(15, "documentHighlight on a literal")
elif want_null(16, "documentHighlight on the document that does not parse"):
    nwhy = want_null(16, "documentHighlight on the document that does not parse")
# --- rename ---------------------------------------------------------
# (d) prepareRename: the word's range and its spelling for a local;
# null for an imported name, a keyword, and a broken document.
elif rresp.get(17, {}).get("result") != {"range": rng(PW[1]), "placeholder": "pw"}:
    nwhy = f"prepareRename on `pw` answered {rresp.get(17, {}).get('result')!r}, want its range and placeholder"
elif want_null(18, "prepareRename on the imported `twice`"):
    nwhy = want_null(18, "prepareRename on the imported `twice`")
elif want_null(19, "prepareRename on the keyword `let`"):
    nwhy = want_null(19, "prepareRename on the keyword `let`")
elif want_null(20, "prepareRename on the document that does not parse"):
    nwhy = want_null(20, "prepareRename on the document that does not parse")
# (e) The exact edit set for the fn, under both uris.
elif got_edits(21) != SURFACE_EDITS:
    nwhy = f"rename `area` -> `surface` answered {got_edits(21)!r}, want {SURFACE_EDITS!r}"
# (f) Refusals: not an identifier, a sibling parameter, a name this
# document declares, a name the importing document declares, a broken
# document.
elif want_null(22, "rename to `1abc`"):
    nwhy = want_null(22, "rename to `1abc`")
elif want_null(23, "rename `pw` to `ph`, its sibling parameter"):
    nwhy = want_null(23, "rename `pw` to `ph`, its sibling parameter")
elif want_null(24, "rename `area` to `count`, which this document declares"):
    nwhy = want_null(24, "rename `area` to `count`, which this document declares")
elif want_null(25, "rename `area` to `useArea`, which the importing document declares"):
    nwhy = want_null(25, "rename `area` to `useArea`, which the importing document declares")
elif want_null(26, "rename on the document that does not parse"):
    nwhy = want_null(26, "rename on the document that does not parse")
elif got_edits(27) != TOTAL_EDITS:
    nwhy = f"rename of the local `acc` answered {got_edits(27)!r}, want {TOTAL_EDITS!r}"
# --- definition and hover on locals ---------------------------------
# (g) A reference lands on ITS binder: the body's `ph` on the let, the
# let value's `ph` on the parameter.
elif nav_landed(28, A_URI, PH[1]):
    nwhy = "definition of the let-bound `ph`: " + nav_landed(28, A_URI, PH[1])
elif nav_landed(29, A_URI, PH[0]):
    nwhy = "definition of the parameter `ph` from the let's value: " + nav_landed(29, A_URI, PH[0])
# (h) Hover: the parameter with its type from the signature, the let
# with its binding pair cut from the document.
elif nav_hover(30, [f"pw : {PARAM_TYPE}", "parameter of `area`"], PW[1]):
    nwhy = "hover on a parameter: " + nav_hover(30, [f"pw : {PARAM_TYPE}", "parameter of `area`"], PW[1])
elif nav_hover(31, [LET_TEXT, "bound by `let` in `area`"], PH[3]):
    nwhy = "hover on a let binding: " + nav_hover(31, [LET_TEXT, "bound by `let` in `area`"], PH[3])
elif want_null(32, "hover on the document that does not parse"):
    nwhy = want_null(32, "hover on the document that does not parse")
elif want_null(33, "definition on the document that does not parse"):
    nwhy = want_null(33, "definition on the document that does not parse")
# --- type positions ---------------------------------------------------
# The cursor on `Shape` in a SIGNATURE finds the declaration and every
# other type position; the declaration's highlight is the one Write
# among Reads; a builtin in a type position is an occurrence but not
# a renamable one; the rename reaches all four; and a new name the
# type positions already spell is refused, since `(-> Int Int)` would
# then mean something else.
elif want_locs(35, [loc(A_URI, s) for s in SHAPE_A]):
    nwhy = "`Shape` from its signature position: " + want_locs(35, [loc(A_URI, s) for s in SHAPE_A])
elif want_hilites(36, [(SHAPE_A[0], 3)] + [(s, 2) for s in SHAPE_A[1:]]):
    nwhy = "`Shape` highlights over its type positions: " + want_hilites(36, [(SHAPE_A[0], 3)] + [(s, 2) for s in SHAPE_A[1:]])
elif want_null(37, "prepareRename on the builtin `Int` in a signature"):
    nwhy = want_null(37, "prepareRename on the builtin `Int` in a signature")
elif got_edits(38) != BLOB_EDITS:
    nwhy = f"rename `Shape` -> `Blob` from its struct field answered {got_edits(38)!r}, want {BLOB_EDITS!r}"
elif want_null(39, "rename `Shape` to `Int`, which its signatures already spell"):
    nwhy = want_null(39, "rename `Shape` to `Int`, which its signatures already spell")

# The renames, APPLIED - `area` -> `surface` under both uris and
# `Shape` -> `Blob` under the first, whose edits never overlap.
# NavMain.ax is rewritten on disk as well as reopened, because
# NavUser.ax's checker reads its import from disk; both must then
# check clean, and the old names must be gone.
renamed = {}
if not nwhy:
    for u, text in ((A_URI, NAV_MAIN), (B_URI, NAV_USER)):
        edits = list(rresp[21]["result"]["changes"][u])
        edits += rresp[38]["result"]["changes"].get(u, [])
        renamed[u] = apply_edits(text, edits)
        if renamed[u] is None:
            nwhy = f"the edits for {os.path.basename(u)} overlap"
            break
if not nwhy:
    open(os.path.join(NAVREF_DIR, "NavMain.ax"), "w", encoding="utf-8").write(renamed[A_URI])
    r2 = subprocess.run([stage1, "lsp"], input=b"".join(frame(m) for m in [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
        nav_open(A_URI, renamed[A_URI]), nav_open(B_URI, renamed[B_URI]),
        {"jsonrpc": "2.0", "id": 2, "method": "shutdown", "params": None},
        {"jsonrpc": "2.0", "method": "exit", "params": None},
    ]), capture_output=True, cwd=NAVREF_DIR)
    m2, t2 = unframe(r2.stdout)
    pubs2 = {m["params"]["uri"]: m["params"]["diagnostics"] for m in m2
             if m.get("method") == "textDocument/publishDiagnostics"}
    if r2.returncode != 0 or t2:
        nwhy = f"the session over the renamed documents exited {r2.returncode} with {len(t2)} trailing bytes"
    elif any(ident_count(renamed[u], "area") for u in renamed):
        nwhy = "the renamed documents still spell `area` as an identifier"
    elif ident_count(renamed[A_URI], "surface") != len(AREA_A) or ident_count(renamed[B_URI], "surface") != 1:
        nwhy = (f"the renamed documents spell `surface` {ident_count(renamed[A_URI], 'surface')} "
                f"and {ident_count(renamed[B_URI], 'surface')} times, want {len(AREA_A)} and 1")
    elif ident_count(renamed[A_URI], "Shape") or ident_count(renamed[A_URI], "Blob") != len(SHAPE_A):
        nwhy = (f"after renaming the type, NavMain.ax spells `Shape` "
                f"{ident_count(renamed[A_URI], 'Shape')} and `Blob` "
                f"{ident_count(renamed[A_URI], 'Blob')} times, want 0 and {len(SHAPE_A)} - "
                f"a type position the rename did not reach")
    elif A_URI not in pubs2 or B_URI not in pubs2:
        nwhy = "the session over the renamed documents published nothing for one of them"
    elif pubs2.get(A_URI) or pubs2.get(B_URI):
        nwhy = ("the renamed documents no longer check clean: "
                f"{[(os.path.basename(u), [(d['code'], first_line(d['message'])) for d in ds]) for u, ds in pubs2.items() if ds]!r:.400}")

if nwhy:
    print(f"FAIL nav-references: {nwhy}")
    failed += 1
else:
    print(f"ok   references (a shadowed parameter and the `let` that shadows it, "
          f"includeDeclaration both ways, `area` and `Circle` found in "
          f"{os.path.basename(B_URI)} under its own uri, imported `twice` found "
          f"in its open module, `Shape` in {len(SHAPE_A) - 1} type positions read from "
          f"the bytes; null on a keyword and on a document that does not parse)")
    print(f"ok   highlights (Write on a `mut` binder and its `set`, Read on its "
          f"reads; a lambda parameter and a pattern binder anchored from the "
          f"bytes; Read on a type's signature, field and alias positions; null on a "
          f"literal and on a broken document)")
    print(f"ok   rename     (prepareRename on a local, null on an import, a keyword, "
          f"a builtin type and a broken document; `area` -> `surface` as {len(AREA_A)} + 1 "
          f"edits under two uris and `Shape` -> `Blob` as {len(SHAPE_A)} edits through a "
          f"signature, a struct field and an alias, applied here and checked clean with "
          f"neither old name left; a local renamed in {len(ACC)} places; refused for "
          f"`1abc`, a sibling parameter, a name either document declares, and a type "
          f"name the signatures spell)")
    print(f"ok   local-nav  (definition from a read to ITS binder through a "
          f"shadowing `let`, hover `pw : {PARAM_TYPE}` from the signature and "
          f"{LET_TEXT!r} cut from the document; null on a broken document)")
    passed += 4
# ---------------------------------------------------------------------
# CONSTRUCTOR NAVIGATION, over the session above. Its own block, so a
# failure names the constructor rather than the whole of SECTION NAV.
#
# Every expected answer is a whole-identifier position in NavMain.ax:
# `definition` and `declaration` land on the constructor's own name
# inside the `data`, from a pattern head, from an expression, from the
# declaration itself, and from the OTHER document that imports it;
# `typeDefinition` lands on `Shape` instead, and is asked at the same
# character as `definition` so the two cannot be one answer wearing two
# names. `hover` quotes the whole `data` form cut from the document,
# carries the paragraph above it, says which constructor, and - across
# the import - names the module; its range is the WORD, in whichever
# document the cursor is in.
CIRCLE_DECL = loc(A_URI, CIRCLE_A[0])
cwhy = ""
if nwhy:
    cwhy = "the session above failed first"
elif rcaps.get("typeDefinitionProvider") is not True:
    cwhy = f"typeDefinitionProvider is not advertised: capabilities were {sorted(rcaps)}"
elif nav_landed(40, A_URI, CIRCLE_A[0]):
    cwhy = "definition on `Circle` as a pattern head: " + nav_landed(40, A_URI, CIRCLE_A[0])
elif nav_landed(41, A_URI, CIRCLE_A[0]):
    cwhy = "definition on `Circle` applied to an argument: " + nav_landed(41, A_URI, CIRCLE_A[0])
elif nav_landed(42, A_URI, CIRCLE_A[0]):
    cwhy = "declaration on `Circle`: " + nav_landed(42, A_URI, CIRCLE_A[0])
elif rresp.get(42, {}).get("result") != rresp.get(40, {}).get("result"):
    cwhy = ("declaration and definition disagree on `Circle`, which is written once: "
            f"{rresp.get(42, {}).get('result')!r} against {rresp.get(40, {}).get('result')!r}")
elif nav_landed(43, A_URI, CIRCLE_A[0]):
    cwhy = ("definition on the imported `Circle`, from NavUser.ax: "
            + nav_landed(43, A_URI, CIRCLE_A[0]))
elif nav_landed(44, A_URI, CIRCLE_A[0]):
    cwhy = ("declaration on the imported `Circle`, from NavUser.ax: "
            + nav_landed(44, A_URI, CIRCLE_A[0]))
elif nav_landed(45, A_URI, SHAPE_A[0]):
    cwhy = ("typeDefinition on the imported `Circle`, which is `Shape`: "
            + nav_landed(45, A_URI, SHAPE_A[0]))
elif rresp.get(45, {}).get("result") == rresp.get(43, {}).get("result"):
    cwhy = ("typeDefinition and definition answered the same range on the imported "
            f"`Circle` ({rresp.get(45, {}).get('result')!r}) - the definition is the "
            f"constructor and the type is the `data` that declares it, and they are "
            f"one line apart by construction here")
elif nav_hover(46, [SHAPE_DATA_TEXT, "constructor `Circle` of `Shape`", SHAPE_DOC],
               CIRCLE_A[1]):
    cwhy = ("hover on `Circle`: "
            + nav_hover(46, [SHAPE_DATA_TEXT, "constructor `Circle` of `Shape`",
                             SHAPE_DOC], CIRCLE_A[1]))
elif nav_hover(47, [SHAPE_DATA_TEXT, "constructor `Circle` of `Shape`",
                    "from `NavMain`", SHAPE_DOC], CIRCLE_B[0]):
    cwhy = ("hover on the imported `Circle`, from NavUser.ax: "
            + nav_hover(47, [SHAPE_DATA_TEXT, "constructor `Circle` of `Shape`",
                             "from `NavMain`", SHAPE_DOC], CIRCLE_B[0]))
elif nav_landed(48, A_URI, CIRCLE_A[0]):
    cwhy = ("definition on the constructor's own declaration: "
            + nav_landed(48, A_URI, CIRCLE_A[0]))
elif want_null(49, "definition on `Circle` in the document that does not parse"):
    cwhy = want_null(49, "definition on `Circle` in the document that does not parse")

if cwhy:
    print(f"FAIL nav-constructors: {cwhy}")
    failed += 1
else:
    print(f"ok   constructors (definition and declaration on `Circle` from a pattern "
          f"head, an application, its own declaration and the importing document, all "
          f"landing on the constructor's name inside `(pub data Shape ...)` and not on "
          f"`Shape`; typeDefinition at the same character landing on `Shape` instead; "
          f"hover quoting the {len(SHAPE_DATA_TEXT)}-byte form cut from NavMain.ax with "
          f"its paragraph, naming the constructor, and naming `NavMain` across the "
          f"import; null on a document that does not parse)")
    passed += 1
shutil.rmtree(NAVREF_DIR, ignore_errors=True)

# ---------------------------------------------------------------------
# textDocument/declaration, and the three call-hierarchy requests.
#
# Still SECTION NAV TESTS, because self_host/lsp.ax's SECTION NAV owns
# all four. Five documents written HERE, so no position below can drift
# away from the text it describes, and EVERY expected answer is
# computed from those documents' own bytes:
#
#   ChHelper.ax  two `fn`s, the second calling the first TWICE, so an
#                incoming list that reported a caller once per caller
#                rather than once per call site is visible.
#   ChMain.ax    imports ChHelper. Declares the shapes the design turns
#                on: a `fn` whose parameter is spelled like a top-level
#                `fn` (`apply`'s `k`), a `fn` that NAMES another
#                without applying it (`handoff`), a `let` for the local
#                half of `declaration`, and `caller`, which calls one
#                local `fn` twice and one imported `fn` once.
#   ChUser.ax    imports ChMain and calls `caller` twice, so incoming
#                calls have a second open document to find.
#   ChSig.ax     a `(:: pending ...)` with no `fn` under it - the one
#                case where `declaration` answers and `definition`
#                cannot.
#   ChBroken.ax  ChMain with an unclosed paren: every one of the four
#                must answer null without the session dying.
#
# WHAT MAKES THESE NON-VACUOUS, beyond deriving the positions:
#
#   * `declaration` and `definition` are asked at the SAME position and
#     must answer DIFFERENT ranges - the `::` and the `fn` - each equal
#     to a whole-identifier position computed here. A server that
#     aliased one to the other passes neither.
#   * `handoff` names `helper` and must NOT appear in `helper`'s
#     incoming list, while `axiom symbols --calls` does report that
#     edge (`#calls=helper`, measured 2026-08-31). The floor below
#     refuses to run if the document ever stops containing that shape.
#   * `apply`'s body head is its own parameter, so outgoing calls from
#     `apply` must be empty AND incoming calls to the top-level `k`
#     must be empty. A server that resolved heads by spelling reports
#     one edge in each direction.
# ---------------------------------------------------------------------
CH_DIR = tempfile.mkdtemp(prefix="axiom-lsp-callhier-")
CH_HELPER = """; Add one.
(pub :: bump (-> Int Int))

(pub fn (bump x) (+ x 1))

; Add one, then add one again: two call sites in one body.
(pub :: twice (-> Int Int))

(pub fn (twice x) (bump (bump x)))
"""
CH_MAIN = """(import ChHelper (bump twice))

(pub :: helper (-> Int Int))

(pub fn (helper n) (+ n n))

; A top-level one-letter function, shadowed below by a parameter
; spelled the same way.
(pub :: k (-> Int Int))

(pub fn (k n) (- n 1))

; The head of the body below is that PARAMETER, not the declaration
; above it.
(pub :: apply (-> (-> Int Int) Int Int))

(pub fn (apply k v) (k v))

; A local binding, for the local half of the declaration request.
(pub :: scaled (-> Int Int))

(pub fn (scaled n) (let ((factor 3)) (* n factor)))

(pub :: caller (-> Int Int))

(pub fn (caller n) (+ (helper n) (helper (bump n))))

; The body below NAMES a function and never applies it.
(pub :: handoff (-> Int (-> Int Int)))

(pub fn (handoff z) helper)

(:: main Int)

(fn (main) (caller (twice 2)))
"""
CH_USER = """(import ChMain (caller))

(pub :: run (-> Int Int))

(pub fn (run n) (+ (caller n) (caller 1)))
"""
CH_SIG = """; A signature whose definition has not been written yet, which is what
; an editor sees between two keystrokes.
(pub :: pending (-> Int Int))

(pub :: ready (-> Int Int))

(pub fn (ready x) (+ x 1))
"""
CH_BROKEN = CH_MAIN + "\n("
CH_DOCS = {"ChHelper.ax": CH_HELPER, "ChMain.ax": CH_MAIN, "ChUser.ax": CH_USER,
           "ChSig.ax": CH_SIG, "ChBroken.ax": CH_BROKEN}
for _n, _t in CH_DOCS.items():
    open(os.path.join(CH_DIR, _n), "w", encoding="utf-8").write(_t)


def ch_uri(name):
    return "file://" + os.path.join(CH_DIR, name)


H_URI, M_URI, U_URI, S_URI, BK_URI = (ch_uri(n) for n in
                                      ("ChHelper.ax", "ChMain.ax", "ChUser.ax",
                                       "ChSig.ax", "ChBroken.ax"))


def ch_form(src, at):
    """The whole top-level form holding the identifier at `at`: from the
    `(` in column 0 at or above its line to the matching `)`, as an LSP
    Range. A second implementation, in Python, of what `lspChItem`
    builds out of `lspFormStart` and `lspFormEnd`."""
    lines = src.split("\n")
    ln = at["line"]
    while ln >= 0 and not lines[ln].startswith("("):
        ln -= 1
    if ln < 0:
        raise LookupError("no column-zero form above line %d" % at["line"])
    start = sum(len(l) + 1 for l in lines[:ln])
    i, depth, instr, incom = start, 0, False, False
    while i < len(src):
        c = src[i]
        if incom:
            if c == "\n":
                incom = False
        elif instr:
            if c == "\\":
                i += 1
            elif c == '"':
                instr = False
        elif c == '"':
            instr = True
        elif c == ";":
            incom = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                i += 1
                break
        i += 1
    eln, etext, ecol = line_of(src, i)
    return {"start": {"line": ln, "character": 0},
            "end": {"line": eln, "character": u16(etext[:ecol])}}


def ch_item(src, uri, name, n=2):
    """The CallHierarchyItem the server must build for the `fn` named
    `name`: `selectionRange` its n-th whole-identifier occurrence - the
    2nd, because `(:: name ...)` spells it first - and `range` the form
    that holds it."""
    at = ident_at(src, name, n)
    return {"name": name, "kind": 12, "uri": uri,
            "range": ch_form(src, at), "selectionRange": rng(at)}


def ch_strip_comments(src):
    """`src` with every `;` comment cut off, strings respected."""
    out = []
    for line in src.split("\n"):
        instr, cut, i = False, len(line), 0
        while i < len(line):
            c = line[i]
            if instr:
                if c == "\\":
                    i += 1
                elif c == '"':
                    instr = False
            elif c == '"':
                instr = True
            elif c == ";":
                cut = i
                break
            i += 1
        out.append(line[:cut])
    return "\n".join(out)


# EVERY POSITION BELOW IS AN OCCURRENCE NUMBER, so a comment that
# happens to SPELL one of these names as a whole identifier silently
# shifts all of them and the checks go on passing against the wrong
# bytes. That is not hypothetical: the first draft of these documents
# wrote "; A top-level `k`, shadowed ..." above `(pub :: k ...)`, and
# every `k` position after it was off by one. So the names are listed
# and the documents are held to spelling them in CODE only.
CH_INDEXED = ["bump", "twice", "helper", "k", "apply", "handoff", "scaled",
              "caller", "main", "factor", "run", "pending", "ready",
              "n", "v", "x", "z"]
for _label, _text in (("ChHelper.ax", CH_HELPER), ("ChMain.ax", CH_MAIN),
                      ("ChUser.ax", CH_USER), ("ChSig.ax", CH_SIG)):
    _bare = ch_strip_comments(_text)
    for _nm in CH_INDEXED:
        if ident_count(_text, _nm) != ident_count(_bare, _nm):
            sys.exit(f"FAIL: a comment in {_label} spells `{_nm}` as a whole "
                     f"identifier, which shifts every occurrence number the "
                     f"declaration and call-hierarchy checks derive from it")

# The `fn` names ChMain declares, read out of the document rather than
# listed here, so a declaration added above is a declaration this block
# asks about.
CH_FNS = re.findall(r"^\(pub fn \(([^ )]+)", CH_MAIN, re.M) + \
         re.findall(r"^\(fn \(([^ )]+)", CH_MAIN, re.M)
# The two shapes the design turns on, asserted before any server runs.
if ident_count(CH_MAIN, "helper") < 5:
    sys.exit("FAIL: ChMain.ax spells `helper` %d times; the incoming-call check "
             "needs its signature, its definition, two calls and one bare "
             "mention" % ident_count(CH_MAIN, "helper"))
if "(handoff z) helper)" not in CH_MAIN:
    sys.exit("FAIL: ChMain.ax no longer NAMES `helper` without applying it, so "
             "nothing here separates a call hierarchy from `symbols --calls`")
if "(apply k v) (k v))" not in CH_MAIN or ident_count(CH_MAIN, "k") < 4:
    sys.exit("FAIL: ChMain.ax no longer shadows the top-level `k` with a "
             "parameter, so a server resolving heads by spelling would pass")
if len(CH_FNS) < 7:
    sys.exit("FAIL: derived only %d `fn` names from ChMain.ax; prepareCallHierarchy "
             "would be asked about too few" % len(CH_FNS))


def ch_req(rid, method, params):
    return {"jsonrpc": "2.0", "id": rid, "method": method, "params": params}


def ch_pos(uri, at):
    return {"textDocument": {"uri": uri}, "position": {"line": at["line"],
                                                       "character": at["start"]}}


# Positions, all whole-identifier, all derived.
CH_HELPER_SIG = ident_at(CH_MAIN, "helper", 1)      # in `(pub :: helper ...)`
CH_HELPER_FN = ident_at(CH_MAIN, "helper", 2)       # in `(pub fn (helper n) ...)`
CH_HELPER_CALLS = [ident_at(CH_MAIN, "helper", 3), ident_at(CH_MAIN, "helper", 4)]
CH_HELPER_NAMED = ident_at(CH_MAIN, "helper", 5)    # handoff's bare mention
CH_BUMP_CALL = ident_at(CH_MAIN, "bump", 2)         # the call inside `caller`; 1 is the import list
CH_BUMP_SIG = ident_at(CH_HELPER, "bump", 1)
CH_BUMP_FN = ident_at(CH_HELPER, "bump", 2)
CH_FACTOR_BIND = ident_at(CH_MAIN, "factor", 1)
CH_FACTOR_READ = ident_at(CH_MAIN, "factor", 2)
CH_APPLY_HEAD = ident_at(CH_MAIN, "k", 4)           # the `(k v)` head: a parameter
CH_CALLER_FN = ident_at(CH_MAIN, "caller", 2)
CH_CALLER_CALLS_M = [ident_at(CH_MAIN, "caller", 3)]
CH_CALLER_CALLS_U = [ident_at(CH_USER, "caller", 2), ident_at(CH_USER, "caller", 3)]
CH_PENDING = ident_at(CH_SIG, "pending", 1)
CH_TWICE_CALL = ident_at(CH_MAIN, "twice", 2)
CH_BUMP_IN_TWICE = [ident_at(CH_HELPER, "bump", 3), ident_at(CH_HELPER, "bump", 4)]

ch_msgs = [ch_req(1, "initialize", {})]
ch_msgs += [{"jsonrpc": "2.0", "method": "textDocument/didOpen",
             "params": {"textDocument": {"uri": ch_uri(n), "languageId": "axiom",
                                         "version": 1, "text": t}}}
            for n, t in CH_DOCS.items()]
# --- declaration ------------------------------------------------------
ch_msgs += [
    ch_req(2, "textDocument/declaration", ch_pos(M_URI, CH_HELPER_CALLS[0])),
    ch_req(3, "textDocument/definition", ch_pos(M_URI, CH_HELPER_CALLS[0])),
    ch_req(4, "textDocument/declaration", ch_pos(M_URI, CH_BUMP_CALL)),
    ch_req(5, "textDocument/definition", ch_pos(M_URI, CH_BUMP_CALL)),
    ch_req(6, "textDocument/declaration", ch_pos(M_URI, CH_FACTOR_READ)),
    ch_req(7, "textDocument/definition", ch_pos(M_URI, CH_FACTOR_READ)),
    ch_req(8, "textDocument/declaration", ch_pos(S_URI, CH_PENDING)),
    ch_req(9, "textDocument/definition", ch_pos(S_URI, CH_PENDING)),
    ch_req(10, "textDocument/declaration",
           {"textDocument": {"uri": M_URI}, "position": {"line": 0, "character": 1}}),
    ch_req(11, "textDocument/declaration", ch_pos(BK_URI, CH_HELPER_CALLS[0])),
]
# --- prepareCallHierarchy, once per `fn` ChMain declares --------------
CH_PREP = {}
_rid = 20
for _fn in CH_FNS:
    CH_PREP[_fn] = _rid
    ch_msgs.append(ch_req(_rid, "textDocument/prepareCallHierarchy",
                          ch_pos(M_URI, ident_at(CH_MAIN, _fn, 2))))
    _rid += 1
CH_PREP_NULL = {}
for _what, _uri, _at in (("an imported name", M_URI, CH_BUMP_CALL),
                         ("a parameter", M_URI, CH_APPLY_HEAD),
                         ("a `let` binder", M_URI, CH_FACTOR_BIND),
                         ("a signature with no fn", S_URI, CH_PENDING),
                         ("a broken document", BK_URI, CH_HELPER_FN)):
    CH_PREP_NULL[_what] = _rid
    ch_msgs.append(ch_req(_rid, "textDocument/prepareCallHierarchy", ch_pos(_uri, _at)))
    _rid += 1
ch_msgs.append(ch_req(_rid, "textDocument/prepareCallHierarchy",
                      {"textDocument": {"uri": M_URI},
                       "position": {"line": 0, "character": 1}}))
CH_PREP_NULL["a keyword"] = _rid
_rid += 1
ch_msgs.append(ch_req(90, "shutdown", None))
ch_msgs.append({"jsonrpc": "2.0", "method": "exit", "params": None})
chp = subprocess.run([stage1, "lsp"], input=b"".join(frame(m) for m in ch_msgs),
                     capture_output=True, cwd=CH_DIR)
chmsgs, chtail = unframe(chp.stdout)
chresp = {m["id"]: m for m in chmsgs if "id" in m}
chpubs = {}
for m in chmsgs:
    if m.get("method") == "textDocument/publishDiagnostics":
        chpubs.setdefault(m["params"]["uri"], m["params"]["diagnostics"])
chcaps = (chresp.get(1, {}).get("result") or {}).get("capabilities") or {}


def chres(rid):
    return chresp.get(rid, {}).get("result")


def ch_landed(rid, uri, at, what):
    r = chres(rid)
    if r is None:
        return f"{what} (request {rid}) answered null"
    if not isinstance(r, dict):
        return f"{what} (request {rid}) answered {r!r:.160}, want one Location"
    if (r.get("uri"), r.get("range")) != (uri, rng(at)):
        return (f"{what} (request {rid}) answered {(r.get('uri'), r.get('range'))!r:.200}, "
                f"want {(uri, rng(at))!r:.200}")
    return ""


def ch_null(rid, what):
    r = chresp.get(rid, {}).get("result", "unanswered")
    if r is not None:
        return f"{what} (request {rid}) answered {r!r:.160}, want null"
    return ""


chwhy = ""
if chp.returncode != 0:
    chwhy = f"the server exited {chp.returncode}: {chp.stderr[:200]!r}"
elif chtail:
    chwhy = f"{len(chtail)} trailing bytes after the last frame"
elif 90 not in chresp:
    chwhy = "the session never answered shutdown - a request killed the server"
elif chcaps.get("declarationProvider") is not True:
    chwhy = (f"the server answers textDocument/declaration and does not advertise "
             f"declarationProvider: capabilities were {sorted(chcaps)}")
elif chcaps.get("callHierarchyProvider") is not True:
    chwhy = (f"the server answers the callHierarchy requests and does not advertise "
             f"callHierarchyProvider: capabilities were {sorted(chcaps)}")
# The corpus is a real program, so nothing below is vacuous: three
# documents check clean, ChSig reports its orphan signature and only
# that, and ChBroken reports its parse error.
elif any(chpubs.get(u) for u in (H_URI, M_URI, U_URI)):
    chwhy = ("the call-hierarchy corpus does not check clean: " +
             repr([(os.path.basename(u), chpubs.get(u)) for u in (H_URI, M_URI, U_URI)
                   if chpubs.get(u)])[:300])
elif [d.get("code") for d in chpubs.get(S_URI) or []] != ["AX3015"]:
    chwhy = (f"ChSig.ax published {[d.get('code') for d in chpubs.get(S_URI) or []]}, "
             f"want exactly ['AX3015'] - the signature with no definition is the "
             f"whole point of that document")
elif not chpubs.get(BK_URI):
    chwhy = "ChBroken.ax published no diagnostic, so it is not the unparseable document it is meant to be"
# --- declaration is not definition ------------------------------------
elif ch_landed(2, M_URI, CH_HELPER_SIG, "declaration on a local `fn`"):
    chwhy = ch_landed(2, M_URI, CH_HELPER_SIG, "declaration on a local `fn`")
elif ch_landed(3, M_URI, CH_HELPER_FN, "definition on the same position"):
    chwhy = ch_landed(3, M_URI, CH_HELPER_FN, "definition on the same position")
elif chres(2) == chres(3):
    chwhy = (f"declaration and definition answered the SAME range {chres(2)!r:.200} "
             f"for `helper`; the `(:: helper ...)` is {CH_HELPER_SIG['line'] and ''}"
             f"line {CH_HELPER_SIG['line']} and the `(pub fn (helper ...)` is line "
             f"{CH_HELPER_FN['line']}, and separating them is what this request is for")
elif ch_landed(4, H_URI, CH_BUMP_SIG, "declaration on an imported name"):
    chwhy = ch_landed(4, H_URI, CH_BUMP_SIG, "declaration on an imported name")
elif ch_landed(5, H_URI, CH_BUMP_FN, "definition on an imported name"):
    chwhy = ch_landed(5, H_URI, CH_BUMP_FN, "definition on an imported name")
elif chres(4) == chres(5):
    chwhy = f"declaration and definition answered the same range for the imported `bump`"
elif ch_landed(6, M_URI, CH_FACTOR_BIND, "declaration on a `let` read"):
    chwhy = ch_landed(6, M_URI, CH_FACTOR_BIND, "declaration on a `let` read")
elif chres(6) != chres(7):
    chwhy = (f"declaration answered {chres(6)!r:.150} and definition {chres(7)!r:.150} "
             f"for the local `factor`; a local is declared by being bound, so the "
             f"two must agree")
elif ch_landed(8, S_URI, CH_PENDING, "declaration on a signature with no definition"):
    chwhy = ch_landed(8, S_URI, CH_PENDING, "declaration on a signature with no definition")
elif ch_null(9, "definition on a signature with no definition"):
    chwhy = ch_null(9, "definition on a signature with no definition")
elif ch_null(10, "declaration on a keyword"):
    chwhy = ch_null(10, "declaration on a keyword")
elif ch_null(11, "declaration on a document that does not parse"):
    chwhy = ch_null(11, "declaration on a document that does not parse")
# --- prepareCallHierarchy ---------------------------------------------
if not chwhy:
    for _fn in CH_FNS:
        want = [ch_item(CH_MAIN, M_URI, _fn)]
        got = chres(CH_PREP[_fn])
        if got != want:
            chwhy = (f"prepareCallHierarchy on `{_fn}` answered {got!r:.300}, "
                     f"want {want!r:.300}")
            break
        sel = want[0]["selectionRange"]
        rge = want[0]["range"]
        if not (rge["start"]["line"] <= sel["start"]["line"] and
                rge["end"]["line"] >= sel["end"]["line"]):
            chwhy = f"the item for `{_fn}` has a selectionRange outside its range"
            break
if not chwhy:
    for _what, _rid in CH_PREP_NULL.items():
        chwhy = ch_null(_rid, f"prepareCallHierarchy on {_what}")
        if chwhy:
            break

# --- incomingCalls and outgoingCalls ---------------------------------
# A second session, whose items are the ones DERIVED above rather than
# the ones the first session answered: what a client sends back is a
# CallHierarchyItem and nothing else, so the server must work from the
# item's uri and name alone, and an item this gate built by hand is the
# only way to prove that.
IT_HELPER = ch_item(CH_MAIN, M_URI, "helper")
IT_CALLER = ch_item(CH_MAIN, M_URI, "caller")
IT_APPLY = ch_item(CH_MAIN, M_URI, "apply")
IT_K = ch_item(CH_MAIN, M_URI, "k")
IT_HANDOFF = ch_item(CH_MAIN, M_URI, "handoff")
IT_MAIN = ch_item(CH_MAIN, M_URI, "main")
IT_BUMP = ch_item(CH_HELPER, H_URI, "bump")
IT_TWICE = ch_item(CH_HELPER, H_URI, "twice")
IT_RUN = ch_item(CH_USER, U_URI, "run")
IT_GHOST = dict(IT_HELPER, name="nosuchfn")
IT_CLOSED = dict(IT_HELPER, uri=ch_uri("ChClosed.ax"))
IT_BROKEN = dict(IT_HELPER, uri=BK_URI)

ch2 = [ch_req(1, "initialize", {})]
ch2 += [{"jsonrpc": "2.0", "method": "textDocument/didOpen",
         "params": {"textDocument": {"uri": ch_uri(n), "languageId": "axiom",
                                     "version": 1, "text": t}}}
        for n, t in CH_DOCS.items()]
CH_IN, CH_OUT = {}, {}
_rid = 100
for _label, _item in (("helper", IT_HELPER), ("caller", IT_CALLER), ("apply", IT_APPLY),
                      ("k", IT_K), ("handoff", IT_HANDOFF), ("main", IT_MAIN),
                      ("bump", IT_BUMP)):
    CH_IN[_label] = _rid
    ch2.append(ch_req(_rid, "callHierarchy/incomingCalls", {"item": _item}))
    _rid += 1
    CH_OUT[_label] = _rid
    ch2.append(ch_req(_rid, "callHierarchy/outgoingCalls", {"item": _item}))
    _rid += 1
CH_HIER_NULL = {}
for _what, _item in (("an item nothing declares", IT_GHOST),
                     ("an item in a document the server has not opened", IT_CLOSED),
                     ("an item in a document that does not parse", IT_BROKEN)):
    CH_HIER_NULL[_what + " (incoming)"] = _rid
    ch2.append(ch_req(_rid, "callHierarchy/incomingCalls", {"item": _item}))
    _rid += 1
    CH_HIER_NULL[_what + " (outgoing)"] = _rid
    ch2.append(ch_req(_rid, "callHierarchy/outgoingCalls", {"item": _item}))
    _rid += 1
ch2.append(ch_req(90, "shutdown", None))
ch2.append({"jsonrpc": "2.0", "method": "exit", "params": None})
chp2 = subprocess.run([stage1, "lsp"], input=b"".join(frame(m) for m in ch2),
                      capture_output=True, cwd=CH_DIR)
chmsgs2, chtail2 = unframe(chp2.stdout)
chresp2 = {m["id"]: m for m in chmsgs2 if "id" in m}


def ch2res(rid):
    return chresp2.get(rid, {}).get("result")


def ch_edges(item, ats):
    """One entry of an incoming or outgoing list, with its ranges in the
    order the document spells them."""
    return {"item": item, "fromRanges": [rng(a) for a in ats]}


def ch_brief(entries):
    """(name, file, call-site positions) per entry - what a reader needs
    to see which edge is wrong. The comparison below is against the
    WHOLE structure; this is only how the difference is reported,
    because two full CallHierarchyItems side by side are 500 characters
    of agreement around the one field that differs."""
    out = []
    for e in entries:
        it = e.get("item") or {}
        out.append((it.get("name"), os.path.basename(it.get("uri") or ""),
                    [(r["start"]["line"], r["start"]["character"])
                     for r in e.get("fromRanges") or []]))
    return out


def ch_calls(rid, key, want, what):
    """Reason request `rid` did not answer exactly `want` - a list of
    (item, ranges) pairs under `key` ("from" or "to") - or ""."""
    got = ch2res(rid)
    if not isinstance(got, list):
        return f"{what} (request {rid}) answered {got!r:.200}, want a list"
    flat = [{"item": e.get(key), "fromRanges": e.get("fromRanges")} for e in got]
    if flat == want:
        return ""
    gb, wb = ch_brief(flat), ch_brief(want)
    if gb != wb:
        return (f"{what} (request {rid}) answered {gb!r}, want {wb!r} "
                f"- each entry is (function, file, the position of every call site)")
    for i, (g, w) in enumerate(zip(flat, want)):
        if g != w:
            return (f"{what} (request {rid}) entry {i} names the right function at "
                    f"the right positions and differs in the item: {g['item']!r:.250} "
                    f"vs {w['item']!r:.250}")
    return f"{what} (request {rid}) answered {len(flat)} entries, want {len(want)}"


if not chwhy:
    if chp2.returncode != 0:
        chwhy = f"the hierarchy session exited {chp2.returncode}: {chp2.stderr[:200]!r}"
    elif chtail2:
        chwhy = f"{len(chtail2)} trailing bytes after the last frame of the hierarchy session"
    elif 90 not in chresp2:
        chwhy = "the hierarchy session never answered shutdown - a request killed the server"
if not chwhy:
    for _what, _rid, _key, _want in (
        # `helper` is called twice by `caller` and NAMED once by
        # `handoff`; only the calls are edges, and the two of them are
        # one entry with two ranges rather than two entries.
        ("incoming calls to `helper`", CH_IN["helper"], "from",
         [ch_edges(IT_CALLER, CH_HELPER_CALLS)]),
        ("outgoing calls from `caller`", CH_OUT["caller"], "to",
         [ch_edges(IT_HELPER, CH_HELPER_CALLS), ch_edges(IT_BUMP, [CH_BUMP_CALL])]),
        # Across two files, in both directions.
        ("incoming calls to `caller`", CH_IN["caller"], "from",
         [ch_edges(IT_MAIN, CH_CALLER_CALLS_M), ch_edges(IT_RUN, CH_CALLER_CALLS_U)]),
        ("incoming calls to the imported `bump`", CH_IN["bump"], "from",
         [ch_edges(IT_TWICE, CH_BUMP_IN_TWICE), ch_edges(IT_CALLER, [CH_BUMP_CALL])]),
        ("outgoing calls from `main`", CH_OUT["main"], "to",
         [ch_edges(IT_CALLER, CH_CALLER_CALLS_M), ch_edges(IT_TWICE, [CH_TWICE_CALL])]),
        # The head of `(k v)` is `apply`'s own parameter, so there is no
        # edge in either direction between `apply` and the top-level `k`.
        ("outgoing calls from `apply`, whose body's head is its parameter",
         CH_OUT["apply"], "to", []),
        ("incoming calls to the top-level `k`, shadowed at the only site that spells it",
         CH_IN["k"], "from", []),
        # `handoff` NAMES `helper`. `axiom symbols --calls` reports that
        # edge; a call hierarchy must not.
        ("outgoing calls from `handoff`, which names `helper` without applying it",
         CH_OUT["handoff"], "to", []),
        ("incoming calls to `main`", CH_IN["main"], "from", []),
        ("outgoing calls from `helper`, whose only head is a builtin operator",
         CH_OUT["helper"], "to", []),
    ):
        chwhy = ch_calls(_rid, _key, _want, _what)
        if chwhy:
            break
if not chwhy:
    for _what, _rid in CH_HIER_NULL.items():
        got = chresp2.get(_rid, {}).get("result", "unanswered")
        if got is not None:
            chwhy = (f"{_what} answered {got!r:.160}, want null - `[]` would claim "
                     f"the function has no callers, which a server that cannot read "
                     f"the file has not earned")
            break

if chwhy:
    print(f"FAIL nav-declaration-callhierarchy: {chwhy}")
    failed += 1
else:
    print(f"ok   declaration (the `(:: helper ...)` on line {CH_HELPER_SIG['line']} where "
          f"`definition` answers the `fn` on line {CH_HELPER_FN['line']}, the same split "
          f"across a file boundary for the imported `bump`, a `let` binder where the two "
          f"agree, and a signature with no `fn` where only this one answers; null on a "
          f"keyword and on a document that does not parse)")
    print(f"ok   call-hierarchy (prepare over all {len(CH_FNS)} `fn`s of ChMain.ax, each "
          f"item's range the form and its selectionRange the name; `helper` called twice "
          f"from one caller as one entry with two ranges and NOT from the `handoff` that "
          f"names it; `caller` reached from `main` here and from `run` in ChUser.ax; "
          f"`bump` reached from its own module and across the import; nothing either way "
          f"for the parameter-shadowed `k`; null for an item nothing declares, one in a "
          f"document the server has not opened, and one that does not parse)")
    passed += 2
shutil.rmtree(CH_DIR, ignore_errors=True)

# =====================================================================
# END SECTION NAV TESTS
# =====================================================================

# =====================================================================
# SECTION VIEW TESTS: signature help, inlay hints, folding ranges,
# selection ranges, document links, workspace symbols.
# =====================================================================
# The six VIEW requests - signature help, inlay hints, folding ranges,
# selection ranges, document links, workspace symbols - over a document
# and two helper modules written HERE. Every expected position, label,
# type text, paragraph and URI is DERIVED from the three documents'
# bytes, so no re-bless of any golden can satisfy it: the hint list the
# server must answer is built from the header and call anchors, the
# fold and selection ranges from a second bracket matcher written
# below, the signature label's type from the `::` line it is cut from.
#
# Each feature has a POSITIVE check and a BOUNDARY: null or [] where it
# does not apply - a keyword head, a document that does not parse, a
# query nothing matches, a document with nothing to fold. Folding's
# boundary runs the other way as well: a document that does NOT parse
# still answers the ranges of its balanced forms, which is the point of
# folding from bytes rather than from a tree.
VIEWDIR = tempfile.mkdtemp(prefix="axiom-view-")
VIEWHELPER = """; Double a number.
(pub :: twice (-> Int Int))

(pub fn (twice n) (* n 2))
"""
VIEWOTHER = """(pub :: seven Int)

(pub fn (seven) 7)
"""
open(os.path.join(VIEWDIR, "ViewHelper.ax"), "w", encoding="utf-8").write(VIEWHELPER)
open(os.path.join(VIEWDIR, "ViewOther.ax"), "w", encoding="utf-8").write(VIEWOTHER)
# A dotted module path, so the link's range has a `.` to extend over -
# the parser's span names the first segment alone.
VIEWDEEP = """(pub :: deep Int)

(pub fn (deep) 9)
"""
os.mkdir(os.path.join(VIEWDIR, "Nested"))
open(os.path.join(VIEWDIR, "Nested", "Deep.ax"), "w", encoding="utf-8").write(VIEWDEEP)

# Three imports in a row, one dotted, a three-line comment block, a two-parameter
# `fn` with a signature, a call with literal arguments, a call whose
# first argument is a variable spelled like the parameter, a
# constructor call, a multi-line `let`, and a call into the imported
# module.
VIEW = """(import ViewHelper)
(import ViewOther)
(import Nested.Deep)

; A block of three comment lines,
; which a folding client collapses
; as one region.
(:: add (-> Int Int Int))
(fn (add x y) (+ x y))

(data Shape (Circle Int) (Square Int Int))

(:: sumUp (-> Int Int))
(fn (sumUp x)
  (let ((total (add 1 2))
        (same (add x 3)))
    (+ total same)))

(:: shape Shape)
(fn (shape) (Circle 7))

(:: viaLocal Int)
(fn (viaLocal) (let ((add (lambda (p q) (+ p q)))) (add 8 9)))

(:: main Int)
(fn (main) (twice (add 4 5)))
"""
view_uri = "file://" + os.path.join(VIEWDIR, "view-generated.ax")
vhelper_uri = "file://" + os.path.join(VIEWDIR, "ViewHelper.ax")
vother_uri = "file://" + os.path.join(VIEWDIR, "ViewOther.ax")
vdeep_uri = "file://" + os.path.join(VIEWDIR, "Nested", "Deep.ax")
# A document mid-form, and one with nothing to fold or hint.
VIEW_BROKEN = VIEW + "\n("
VIEW_FLAT = "(:: one Int)\n(fn (one) 1)\n"


def vat(src, anchor, occurrence=1, sub=""):
    """The LSP position `sub` characters into the N-th `anchor`. The
    anchor sits on one line, so the column is its UTF-16 start plus the
    UTF-16 length of the prefix - the same rule `locate` uses."""
    p = locate(src, anchor, occurrence)
    return {"line": p["line"], "character": p["start"] + u16(sub)}


def vform(src, opener, occurrence=1):
    """(start, one past end) character indices of the form whose `(`
    begins the N-th `opener`, by counting brackets and stepping over
    `;` comments - a second implementation of the server's scan, over
    documents that keep their brackets out of strings."""
    idx = -1
    for _ in range(occurrence):
        idx = src.index(opener, idx + 1)
    depth, i = 0, idx
    while i < len(src):
        c = src[i]
        if c == ";":
            nl = src.find("\n", i)
            i = len(src) if nl < 0 else nl
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return idx, i + 1
        i += 1
    raise LookupError(f"the form at {opener!r} never closes")


def vrange(src, i, j):
    """An LSP range from two character indices into `src`."""
    def at(k):
        ln, text, col = line_of(src, k)
        return {"line": ln, "character": u16(text[:col])}
    return {"start": at(i), "end": at(j)}


def vlines(src, span):
    """(startLine, endLine) of a form: the lines of its `(` and `)`."""
    return line_of(src, span[0])[0], line_of(src, span[1] - 1)[0]


def vparams(src, header):
    """The parameter names a `fn` header declares, read out of the
    document: `(fn (add x y)` -> ["x", "y"]."""
    rest = src[src.index(header) + len(header):]
    return rest[:rest.index(")")].split()


def arrow_parts(ty):
    """`(-> Int Int Bool)` -> ["Int", "Int", "Bool"]: the parameter
    types in order and, last, the result."""
    if not (ty.startswith("(-> ") and ty.endswith(")")):
        sys.exit(f"FAIL: {ty!r} is not an arrow type, and the hint labels "
                 f"below are derived from one")
    return ty[len("(-> "):-1].split()


# The signature texts, cut from the `::` lines that carry them, and the
# type alone: everything after the name up to the closing paren.
def sig_type(sig_text, name):
    return sig_text[sig_text.index(name) + len(name):].strip()[:-1].strip()

ADD_SIG_TEXT = between(VIEW, "(:: add", "\n(fn (add")
ADD_TYPE = sig_type(ADD_SIG_TEXT, "add")
SUMUP_SIG_TEXT = between(VIEW, "(:: sumUp", "\n(fn (sumUp")
SUMUP_TYPE = sig_type(SUMUP_SIG_TEXT, "sumUp")
TWICE_SIG_TEXT = between(VIEWHELPER, "(pub :: twice", "\n\n(pub fn")
TWICE_TYPE = sig_type(TWICE_SIG_TEXT, "twice")
TWICE_DOC = prose(VIEWHELPER, "(pub :: twice")
ADD_DOC = prose(VIEW, "(:: add")
ADD_PARAMS = vparams(VIEW, "(fn (add")
SUMUP_PARAMS = vparams(VIEW, "(fn (sumUp")
TWICE_PARAMS = vparams(VIEWHELPER, "(pub fn (twice")
ADD_TYS = arrow_parts(ADD_TYPE)
SUMUP_TYS = arrow_parts(SUMUP_TYPE)
# The constructor's field types, cut from the `data` line.
CIRCLE_FIELDS = between(VIEW, "(Circle", ")")[len("(Circle"):].split()

for what, text, doc in (("add type", ADD_TYPE, VIEW), ("sumUp type", SUMUP_TYPE, VIEW),
                        ("twice type", TWICE_TYPE, VIEWHELPER),
                        ("twice doc", TWICE_DOC, None), ("add doc", ADD_DOC, None)):
    if not text.strip() or (doc is not None and text not in doc):
        sys.exit(f"FAIL: the derived {what} text is empty or is not in the "
                 f"document it was cut from ({text!r}) - every signature and "
                 f"hint assertion below rests on it")
if len(ADD_PARAMS) != 2 or len(ADD_TYS) != 3 or len(TWICE_PARAMS) != 1 or not CIRCLE_FIELDS:
    sys.exit(f"FAIL: the VIEW document no longer declares the shapes the "
             f"checks below are written for: add{ADD_PARAMS} : {ADD_TYS}, "
             f"twice{TWICE_PARAMS}, Circle{CIRCLE_FIELDS}")
if len(ADD_DOC.split("\n")) < 3:
    sys.exit("FAIL: the comment block above `add` is under three lines, so "
             "the folding check for a comment run would not need a run")

# --- inlay hints: the whole list, derived -----------------------------
# One tuple per hint: (line, UTF-16 character, label, kind). Kind 1 is
# a type hint, kind 2 a parameter name; both come from the protocol.
HDR_ADD, HDR_SUM = "(fn (add x y)", "(fn (sumUp x)"
CALL_LIT, CALL_SAME, CALL_IMP = "(add 1 2)", "(add x 3)", "(twice (add 4 5))"


def vhint(anchor, sub, label, kind):
    p = vat(VIEW, anchor, 1, sub)
    return (p["line"], p["character"], label, kind)

HINTS_WANT = sorted([
    # (b) the parameter types after each header name, (c) the result
    # after the header's `)`.
    vhint(HDR_ADD, "(fn (add x", ": " + ADD_TYS[0], 1),
    vhint(HDR_ADD, "(fn (add x y", ": " + ADD_TYS[1], 1),
    vhint(HDR_ADD, "(fn (add x y)", " -> " + ADD_TYS[2], 1),
    vhint(HDR_SUM, "(fn (sumUp x", ": " + SUMUP_TYS[0], 1),
    vhint(HDR_SUM, "(fn (sumUp x)", " -> " + SUMUP_TYS[1], 1),
    # (a) parameter names before literal arguments ...
    vhint(CALL_LIT, "(add ", ADD_PARAMS[0] + ":", 2),
    vhint(CALL_LIT, "(add 1 ", ADD_PARAMS[1] + ":", 2),
    # ... before the `3` but NOT before the `x` spelled like the parameter,
    vhint(CALL_SAME, "(add x ", ADD_PARAMS[1] + ":", 2),
    # ... and for an imported callee, with the nested call's own hints.
    vhint(CALL_IMP, "(twice ", TWICE_PARAMS[0] + ":", 2),
    vhint(CALL_IMP, "(twice (add ", ADD_PARAMS[0] + ":", 2),
    vhint(CALL_IMP, "(twice (add 4 ", ADD_PARAMS[1] + ":", 2),
])
FORBIDDEN_HINT = vhint(CALL_SAME, "(add ", ADD_PARAMS[0] + ":", 2)
HDR_ADD_LINE = locate(VIEW, HDR_ADD, 1)["line"]
HINTS_ONE_LINE = sorted(h for h in HINTS_WANT if h[0] == HDR_ADD_LINE)
# The call whose head is the `let`-bound `add`, spelled like the
# top-level `fn`: a LOCAL, so it is not a call to `add` and gets no
# parameter hints and no signature - the language's scoping rule, and
# the one thing a lookup by bare name cannot know.
CALL_LOCAL = "(add 8 9)"
LOCAL_CALL_LINE = locate(VIEW, CALL_LOCAL, 1)["line"]
if "(let ((add " not in VIEW or VIEW.count(CALL_LOCAL) != 1 \
        or LOCAL_CALL_LINE != locate(VIEW, "(let ((add ", 1)["line"]:
    sys.exit("FAIL: the VIEW document no longer binds a local `add` and calls it once on "
             "the binding's own line")
if len(HINTS_WANT) < 10 or len(HINTS_ONE_LINE) < 3 or FORBIDDEN_HINT in HINTS_WANT \
        or [h for h in HINTS_WANT if h[0] == LOCAL_CALL_LINE]:
    sys.exit(f"FAIL: derived {len(HINTS_WANT)} hints ({len(HINTS_ONE_LINE)} on "
             f"the `add` header line) - an equality against a list this short "
             f"asserts nothing")

# --- folding, selection, links, symbols: derived ---------------------
FOLD_FN = vform(VIEW, "(fn (sumUp")
FOLD_LET = vform(VIEW, "(let ((total")
FOLD_PLUS = vform(VIEW, "(+ total same)")
FOLD_FN_L, FOLD_LET_L = vlines(VIEW, FOLD_FN), vlines(VIEW, FOLD_LET)
COMMENT_L = (locate(VIEW, "; A block", 1)["line"], locate(VIEW, "; as one region.", 1)["line"])
IMPORTS_L = (locate(VIEW, "(import ViewHelper)", 1)["line"], locate(VIEW, "(import Nested.Deep)", 1)["line"])
DATA_LINE = locate(VIEW, "(data Shape", 1)["line"]
if FOLD_FN_L[0] == FOLD_FN_L[1] or COMMENT_L[1] - COMMENT_L[0] != 2 or IMPORTS_L[1] - IMPORTS_L[0] != 2:
    sys.exit(f"FAIL: the VIEW document's fn ({FOLD_FN_L}), comment block "
             f"({COMMENT_L}) or import run ({IMPORTS_L}) no longer spans the "
             f"lines the folding checks need")

# Two characters into the second `total` - the reference in `(+ total
# same)`, not the binder - and the chain a selection expands through.
TOTAL_IDX = VIEW.index("total", VIEW.index("total") + 1)
SEL_POS = vat(VIEW, "total", 2, "to")
CHAIN_WANT = [vrange(VIEW, TOTAL_IDX, TOTAL_IDX + len("total")),
              vrange(VIEW, *FOLD_PLUS), vrange(VIEW, *FOLD_LET),
              vrange(VIEW, *FOLD_FN), vrange(VIEW, 0, len(VIEW))]
# The empty last line: nothing encloses it, so the chain is the document.
EOF_POS = {"line": VIEW.count("\n"), "character": 0}
DOC_RANGE = vrange(VIEW, 0, len(VIEW))

LINKS_WANT = [(rng(locate(VIEW, "ViewHelper", 1)), vhelper_uri),
              (rng(locate(VIEW, "ViewOther", 1)), vother_uri),
              (rng(locate(VIEW, "Nested.Deep", 1)), vdeep_uri)]

TWICE_DECL = locate(VIEWHELPER, "twice", 2)   # the `fn`'s name; 1 is the `::`
SEVEN_DECL = locate(VIEWOTHER, "seven", 2)
DEEP_DECL = locate(VIEWDEEP, "deep", 2)
ADD_DECL = locate(VIEW, "add", 2)             # `(fn (add`; 1 is `(:: add`
SHAPE_DECL = locate(VIEW, "Shape", 1)
CIRCLE_DECL = locate(VIEW, "Circle", 1)
# Mixed case on purpose: the match is a case-folded substring.
TWICE_QUERY = "tWi"
if TWICE_QUERY.lower() not in "twice" or TWICE_QUERY in VIEWHELPER:
    sys.exit("FAIL: the workspace query must be a case-folded substring of "
             "`twice` that the helper does not spell literally")


def vreq(rid, method, extra):
    p = {"textDocument": {"uri": view_uri}}
    p.update(extra)
    return {"jsonrpc": "2.0", "id": rid, "method": method, "params": p}


def vsig(rid, anchor, sub):
    return vreq(rid, "textDocument/signatureHelp", {"position": vat(VIEW, anchor, 1, sub)})


def vhints(rid, start_line, end_line):
    return vreq(rid, "textDocument/inlayHint",
                {"range": {"start": {"line": start_line, "character": 0},
                           "end": {"line": end_line, "character": 0}}})


def vws(rid, query):
    return {"jsonrpc": "2.0", "id": rid, "method": "workspace/symbol",
            "params": {"query": query}}


def vchange(text, version):
    return {"jsonrpc": "2.0", "method": "textDocument/didChange",
            "params": {"textDocument": {"uri": view_uri, "version": version},
                       "contentChanges": [{"text": text}]}}

VIEW_LINES = VIEW.count("\n") + 1
view_session = b"".join(frame(m) for m in [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
    {"jsonrpc": "2.0", "method": "textDocument/didOpen",
     "params": {"textDocument": {"uri": view_uri, "languageId": "axiom",
                                 "version": 1, "text": VIEW}}},
    vsig(40, CALL_LIT, "(add 1 "),        # on the `2`: the second argument
    vsig(41, "(let ((total", "(let "),    # a keyword head
    vsig(42, "(Circle 7)", "(Circle "),   # a constructor
    vsig(43, CALL_IMP, "(twice"),         # touching an imported head
    vhints(44, 0, VIEW_LINES),
    vhints(45, HDR_ADD_LINE, HDR_ADD_LINE + 1),
    vreq(46, "textDocument/foldingRange", {}),
    vreq(47, "textDocument/selectionRange", {"positions": [SEL_POS, EOF_POS]}),
    vreq(48, "textDocument/documentLink", {}),
    vws(49, TWICE_QUERY),
    vws(50, "zzqx"),
    vws(51, ""),
    vsig(58, CALL_LOCAL, "(add 8 "),       # a head that is a local
    vsig(59, HDR_ADD, "(fn (add x "),      # inside the fn's own header
    vchange(VIEW_BROKEN, 2),
    vsig(52, CALL_LIT, "(add 1 "),
    vhints(53, 0, VIEW_LINES + 2),
    vreq(54, "textDocument/foldingRange", {}),
    vreq(55, "textDocument/documentLink", {}),
    vchange(VIEW_FLAT, 3),
    vreq(56, "textDocument/foldingRange", {}),
    vhints(57, 0, 3),
    {"jsonrpc": "2.0", "id": 9, "method": "shutdown", "params": None},
    {"jsonrpc": "2.0", "method": "exit", "params": None},
])

vp = subprocess.run([stage1, "lsp"], input=view_session, capture_output=True,
                    cwd=fixdir)
vmsgs, vtail = unframe(vp.stdout)
vresp = {m["id"]: m for m in vmsgs if "id" in m}
vcaps = (vresp.get(1, {}).get("result") or {}).get("capabilities") or {}


def vres(rid):
    return vresp.get(rid, {}).get("result")


def sig_says(rid, label_parts, active, param_names, doc=None):
    """One signature whose label carries every part, whose parameters'
    [start, end) offsets SLICE the label to the names given, with the
    active parameter given - and the paragraph, when one is expected."""
    r = vres(rid)
    if r is None:
        return f"request {rid} answered null"
    sigs = r.get("signatures") or []
    if len(sigs) != 1:
        return f"request {rid} answered {len(sigs)} signature(s), want 1"
    s = sigs[0]
    label = s.get("label", "")
    for w in label_parts:
        if w not in label:
            return f"request {rid} label {label!r} does not carry {w!r}"
    if r.get("activeSignature") != 0:
        return f"request {rid} activeSignature {r.get('activeSignature')!r}, want 0"
    if r.get("activeParameter") != active:
        return f"request {rid} activeParameter {r.get('activeParameter')!r}, want {active}"
    got = []
    for p in s.get("parameters") or []:
        lb = p.get("label")
        if not (isinstance(lb, list) and len(lb) == 2):
            return f"request {rid} parameter label {lb!r} is not an offset pair"
        got.append(slice_u16(label, lb[0], lb[1]))
    if got != param_names:
        return f"request {rid} parameters slice the label to {got}, want {param_names}"
    if doc is not None and doc not in ((s.get("documentation") or {}).get("value") or ""):
        return f"request {rid} documentation {s.get('documentation')!r} does not carry {doc!r}"
    return ""


def hints_of(rid):
    r = vres(rid)
    if not isinstance(r, list):
        return None
    return sorted((h["position"]["line"], h["position"]["character"],
                   h["label"], h["kind"]) for h in r)


def hints_padded(rid):
    """Every parameter-name hint carries paddingRight and no type hint
    does; answers the first offender or ''."""
    for h in vres(rid) or []:
        if (h["kind"] == 2) != (h.get("paddingRight") is True):
            return f"hint {h!r} has the wrong paddingRight for its kind"
    return ""


def folds_of(rid):
    r = vres(rid)
    if not isinstance(r, list):
        return None
    return sorted((f["startLine"], f["endLine"], f.get("kind")) for f in r)


def chain_of(node):
    out = []
    while node is not None:
        out.append(node.get("range"))
        node = node.get("parent")
    return out


def links_of(rid):
    r = vres(rid)
    if not isinstance(r, list):
        return None
    return [(l.get("range"), l.get("target")) for l in
            sorted(r, key=lambda l: (l["range"]["start"]["line"], l["range"]["start"]["character"]))]


def vsym_named(rid, name):
    return [s for s in (vres(rid) or []) if s.get("name") == name]


def sym_is(rid, name, kind, uri, at, container=None):
    """Exactly one symbol `name`, with the kind, the Location and the
    containerName it must have; the reason it is not, or ''."""
    ss = vsym_named(rid, name)
    if len(ss) != 1:
        return f"request {rid} listed {name!r} {len(ss)} time(s), want once"
    s = ss[0]
    if s.get("kind") != kind:
        return f"request {rid} listed {name!r} as kind {s.get('kind')}, want {kind}"
    loc = s.get("location") or {}
    if loc.get("uri") != uri:
        return f"request {rid} placed {name!r} in {loc.get('uri')}, want {uri}"
    if loc.get("range") != rng(at):
        return f"request {rid} placed {name!r} at {loc.get('range')}, want {rng(at)}"
    if s.get("containerName") != container:
        return (f"request {rid} gave {name!r} containerName "
                f"{s.get('containerName')!r}, want {container!r}")
    return ""

sig_caps = vcaps.get("signatureHelpProvider")
link_caps = vcaps.get("documentLinkProvider")
folds46, folds54, folds56 = folds_of(46), folds_of(54), folds_of(56)
sel47 = vres(47)
vwhy = ""
if vp.returncode != 0:
    vwhy = f"the server exited {vp.returncode}"
elif vp.stderr:
    vwhy = f"stderr not empty: {vp.stderr[:200]!r}"
elif vtail:
    vwhy = f"{len(vtail)} trailing bytes after the last frame"
# --- capabilities: a promise the client reads ------------------------
elif not isinstance(sig_caps, dict) or sig_caps.get("triggerCharacters") != ["(", " "] \
        or sig_caps.get("retriggerCharacters") != [" "]:
    vwhy = (f"signatureHelpProvider is {sig_caps!r}, want triggerCharacters "
            f"['(', ' '] and retriggerCharacters [' ']")
elif vcaps.get("inlayHintProvider") is not True:
    vwhy = f"inlayHintProvider not advertised: capabilities were {sorted(vcaps)}"
elif vcaps.get("foldingRangeProvider") is not True:
    vwhy = f"foldingRangeProvider not advertised: capabilities were {sorted(vcaps)}"
elif vcaps.get("selectionRangeProvider") is not True:
    vwhy = f"selectionRangeProvider not advertised: capabilities were {sorted(vcaps)}"
elif not isinstance(link_caps, dict) or link_caps.get("resolveProvider") is not False:
    vwhy = (f"documentLinkProvider is {link_caps!r}, want resolveProvider false - "
            f"there is no documentLink/resolve")
elif vcaps.get("workspaceSymbolProvider") is not True:
    vwhy = f"workspaceSymbolProvider not advertised: capabilities were {sorted(vcaps)}"
# --- signature help --------------------------------------------------
elif sig_says(40, ["(add " + " ".join(ADD_PARAMS) + ")", ADD_TYPE], 1, ADD_PARAMS, ADD_DOC):
    vwhy = "signature help on the second argument: " + \
        sig_says(40, ["(add " + " ".join(ADD_PARAMS) + ")", ADD_TYPE], 1, ADD_PARAMS, ADD_DOC)
elif vres(41) is not None:
    vwhy = f"signature help on a `let` head answered {vres(41)!r}, want null"
elif sig_says(42, ["(Circle " + " ".join(CIRCLE_FIELDS) + ")"], 0, CIRCLE_FIELDS):
    vwhy = "signature help on a constructor: " + \
        sig_says(42, ["(Circle " + " ".join(CIRCLE_FIELDS) + ")"], 0, CIRCLE_FIELDS)
elif sig_says(43, ["(twice " + " ".join(TWICE_PARAMS) + ")", TWICE_TYPE, "ViewHelper"], 0, TWICE_PARAMS, TWICE_DOC):
    vwhy = "signature help on an imported fn: " + \
        sig_says(43, ["(twice " + " ".join(TWICE_PARAMS) + ")", TWICE_TYPE, "ViewHelper"], 0, TWICE_PARAMS, TWICE_DOC)
elif vres(52) is not None:
    vwhy = f"signature help on a document that does not parse answered {vres(52)!r}, want null"
elif vres(58) is not None:
    vwhy = (f"signature help on `{CALL_LOCAL}`, whose head is the `let`-bound `add`, "
            f"answered {vres(58)!r:.160}, want null - a local is not the fn it is spelled like")
elif vres(59) is not None:
    vwhy = (f"signature help inside the header `{HDR_ADD}` answered {vres(59)!r:.160}, "
            f"want null - a header declares a fn, it does not call one")
# --- inlay hints -----------------------------------------------------
elif [h for h in hints_of(44) or [] if h[0] == LOCAL_CALL_LINE]:
    vwhy = (f"inlay hints labelled the arguments of `{CALL_LOCAL}` on line {LOCAL_CALL_LINE}, "
            f"whose head is a local: {[h for h in hints_of(44) if h[0] == LOCAL_CALL_LINE]}")
elif hints_of(44) != HINTS_WANT:
    vwhy = (f"inlay hints over the whole document are not the derived list;\n"
            f"          server:  {hints_of(44)}\n          derived: {HINTS_WANT}")
elif hints_padded(44):
    vwhy = "inlay hints: " + hints_padded(44)
elif hints_of(45) != HINTS_ONE_LINE:
    vwhy = (f"inlay hints over line {HDR_ADD_LINE} alone answered {hints_of(45)}, "
            f"want only that line's {HINTS_ONE_LINE}")
elif vres(53) != []:
    vwhy = f"inlay hints on a document that does not parse answered {vres(53)!r}, want []"
elif vres(57) != []:
    vwhy = f"inlay hints on a signature with no arrow answered {vres(57)!r}, want []"
# --- folding ---------------------------------------------------------
elif folds46 is None:
    vwhy = f"foldingRange answered {vres(46)!r}, want an array"
elif (FOLD_FN_L[0], FOLD_FN_L[1], None) not in folds46:
    vwhy = f"folding did not offer the fn form {FOLD_FN_L}; it offered {folds46}"
elif (FOLD_LET_L[0], FOLD_LET_L[1], None) not in folds46:
    vwhy = f"folding did not offer the let form {FOLD_LET_L}; it offered {folds46}"
elif (COMMENT_L[0], COMMENT_L[1], "comment") not in folds46:
    vwhy = f"folding did not offer the comment block {COMMENT_L} as kind comment; it offered {folds46}"
elif (IMPORTS_L[0], IMPORTS_L[1], "imports") not in folds46:
    vwhy = f"folding did not offer the import run {IMPORTS_L} as kind imports; it offered {folds46}"
elif [f for f in folds46 if f[0] == DATA_LINE]:
    vwhy = f"folding offered a range starting on the one-line `data` at line {DATA_LINE}"
elif [f for f in folds46 if f[0] >= f[1]]:
    vwhy = f"folding offered a range that does not span two lines: {[f for f in folds46 if f[0] >= f[1]]}"
elif folds54 != folds46:
    vwhy = (f"a document that does not parse folded {folds54}, want the same "
            f"balanced forms as before the edit: {folds46}")
elif folds56 != []:
    vwhy = f"a document of one-line forms folded {folds56}, want []"
# --- selection ranges ------------------------------------------------
elif not isinstance(sel47, list) or len(sel47) != 2:
    vwhy = f"selectionRange for two positions answered {sel47!r}"
elif chain_of(sel47[0]) != CHAIN_WANT:
    vwhy = (f"selection chain at `total` is not the derived one;\n"
            f"          server:  {chain_of(sel47[0])}\n          derived: {CHAIN_WANT}")
elif chain_of(sel47[1]) != [DOC_RANGE]:
    vwhy = f"selection chain on the empty last line is {chain_of(sel47[1])}, want the document alone"
# --- document links --------------------------------------------------
elif links_of(48) != LINKS_WANT:
    vwhy = (f"document links are not the derived ones;\n"
            f"          server:  {links_of(48)}\n          derived: {LINKS_WANT}")
elif vres(55) != []:
    vwhy = f"document links on a document that does not parse answered {vres(55)!r}, want []"
# --- workspace symbols -----------------------------------------------
elif len(vres(49) or []) != 1 or sym_is(49, "twice", 12, vhelper_uri, TWICE_DECL, "ViewHelper"):
    vwhy = (f"workspace/symbol {TWICE_QUERY!r}: " +
            (sym_is(49, "twice", 12, vhelper_uri, TWICE_DECL, "ViewHelper")
             or f"answered {len(vres(49) or [])} symbol(s), want the one `twice`"))
elif vres(50) != []:
    vwhy = f"workspace/symbol on a query nothing matches answered {vres(50)!r}, want []"
elif sym_is(51, "add", 12, view_uri, ADD_DECL):
    vwhy = "workspace/symbol '': " + sym_is(51, "add", 12, view_uri, ADD_DECL)
elif sym_is(51, "Shape", 10, view_uri, SHAPE_DECL):
    vwhy = "workspace/symbol '': " + sym_is(51, "Shape", 10, view_uri, SHAPE_DECL)
elif sym_is(51, "Circle", 22, view_uri, CIRCLE_DECL):
    vwhy = "workspace/symbol '': " + sym_is(51, "Circle", 22, view_uri, CIRCLE_DECL)
elif sym_is(51, "seven", 12, vother_uri, SEVEN_DECL, "ViewOther"):
    vwhy = "workspace/symbol '': " + sym_is(51, "seven", 12, vother_uri, SEVEN_DECL, "ViewOther")
elif sym_is(51, "twice", 12, vhelper_uri, TWICE_DECL, "ViewHelper"):
    vwhy = "workspace/symbol '': " + sym_is(51, "twice", 12, vhelper_uri, TWICE_DECL, "ViewHelper")
elif sym_is(51, "deep", 12, vdeep_uri, DEEP_DECL, "Nested.Deep"):
    vwhy = "workspace/symbol '': " + sym_is(51, "deep", 12, vdeep_uri, DEEP_DECL, "Nested.Deep")
elif len(vres(51)) > 200:
    vwhy = f"workspace/symbol '' answered {len(vres(51))} symbols, over the 200 cap"

if vwhy:
    print(f"FAIL view: {vwhy}")
    failed += 1
else:
    print(f"ok   signature-help (activeParameter 1 on `{CALL_LIT}`, labels "
          f"slicing to {ADD_PARAMS} with {ADD_TYPE!r} cut from the document, a "
          f"constructor, `twice` from ViewHelper with its paragraph; null on a "
          f"keyword head, on a head that is a local, inside a fn header, and on a "
          f"document that does not parse)")
    print(f"ok   inlay-hints (exactly the {len(HINTS_WANT)} derived hints: types "
          f"after header parameters, the result after the header, names before "
          f"literal and nested arguments, none before the var spelled like its "
          f"parameter, none on a call whose head is a local; {len(HINTS_ONE_LINE)} "
          f"for one line; [] on a document that does not parse)")
    print(f"ok   folding    (the fn {FOLD_FN_L}, the let {FOLD_LET_L}, a comment "
          f"run {COMMENT_L}, an import run {IMPORTS_L}; the same forms on a "
          f"document that does not parse; [] with nothing to fold)")
    print(f"ok   selection  (word -> form -> let -> fn -> document, {len(CHAIN_WANT)} "
          f"derived ranges; the document alone on the empty last line)")
    print(f"ok   links      ({len(LINKS_WANT)} module names, one dotted, to their files' URIs; "
          f"[] on a document that does not parse)")
    print(f"ok   workspace  (`twice` found by {TWICE_QUERY!r} in ViewHelper.ax with "
          f"its container, 6 declarations of 3 kinds in 4 files placed by an "
          f"empty query, [] for a query nothing matches)")
    passed += 6
shutil.rmtree(VIEWDIR, ignore_errors=True)

# =====================================================================
# END SECTION VIEW TESTS
# =====================================================================

# =====================================================================
# SECTION FIX TESTS: formatting, code actions, macro expansion, code
# lenses, type definition, diagnostics for imported modules.
# =====================================================================
#
# The requests that CHANGE or RUN code, over one document written HERE,
# with every expected answer DERIVED from its bytes or from the
# compiler's own commands run on a copy of it:
#
#   * `formatting` must answer ONE edit over the whole document whose
#     text equals, byte for byte, what `axiom fmt` writes to a copy of
#     the same file - the command is the reference - and whose range is
#     derived from the document's line count; the formatted text,
#     opened as a document, must answer an empty list;
#   * the two quickfixes must land where the document says: AX3012's on
#     the BINDER `x` of `(let ((x 1)) ...)` - not the `set` the
#     diagnostic anchors on - with the text `mut x`, and AX3001's on
#     the misspelt call with the name of the declaration it meant;
#   * the "Add type signature" assist must insert, at column 0 of the
#     unsigned fn's line, a `::` whose type is what `axiom symbols`
#     prints for that fn - rewritten from the checker's `(A -> B)` into
#     the parser's `(-> A B)`, since only the latter parses. Then every
#     quickfix and the assist are APPLIED here, the result is opened as
#     a fresh document and must publish NO diagnostics, and `symbols` on
#     it must print the same type for the fn - the check that the
#     inserted line means what the assist claimed;
#   * `typeDefinition` on a fn returning a local `data`, on a parameter
#     of that type inside a fn header, and on one of its constructors
#     must land on the data's NAME; on a fn returning `Int`, null;
#   * the `Run` lens must sit over `main` with the document's path as
#     its one argument, and the `Expand macro` lens over the macro's
#     name with the URI and that name's position;
#   * `expandMacro` on the invocation `(deriveTag Shape)` must name the
#     macro and answer text that, opened as a fresh document, parses
#     clean and has an outline of exactly the generated name - `tag` +
#     the invocation's argument, derived here - and carries the
#     template's literal; the same on the declaration's name; null on
#     `main`;
#   * every request on a document that does not parse answers null or
#     an empty list, and every capability is advertised.
#
# TWO SESSIONS, not one, and the reason is in the assertions: the fixed
# document and the expansion text are the FIRST session's answers, and
# a pipe fed in one write cannot send back what it has not yet read.
# The second session opens both and reads what the server publishes.
FIXDIR = tempfile.mkdtemp(prefix="axiom-fix-")
FIX = """; A shape, for typeDefinition to land on.
(data Shape (Circle Int) (Square Int))

; A macro that derives a tag function.
(pub macro deriveTag
  ((deriveTag T)
   (pub :: (syntax/join tag T) Int)
   (pub fn ((syntax/join tag T)) 7)))

(deriveTag Shape)

; A capability record, its instance for the field type, and a macro
; that derives a free equality function for a whole `data` - a FN
; product, named by `syntax/join` the same way `deriveTag` names its
; own, with hygiene-renamed binders from `syntax/binders`.
(struct EqOf (a) (eq : (-> a a Bool)))

(:: eqOfInt (EqOf Int))
(fn (eqOfInt) (EqOf (lambda (x y) (== x y))))

(macro deriveEq ((deriveEq T)
   (:: (syntax/join eq T) (-> T T Bool))
   (fn ((syntax/join eq T) a b)
     (match a
       (syntax/for (C (syntax/constructors T))
         ((C (syntax/binders C x))
          (match b
            ((C (syntax/binders C y))
             (syntax/fold && true
                          ((xi (syntax/binders C x))
                           (yi (syntax/binders C y)))
               (== xi yi)))
            (_ false))))))))

(deriveEq Shape)

(:: helper (-> Int Int))
(fn (helper n) (+ n 1))

(:: mk (-> Int Shape))
(fn (mk n) (Circle n))

(:: area (-> Shape Int))
(fn (area s) (match s ((Circle r) r) ((Square w) w)))

(:: call Int)
(fn (call) (helpr 1))

(:: bump Int)
(fn (bump) (let ((x 1)) { (set x 2) x }))

(fn (twice x)   (+ x
  x))

(fn (adder n) (lambda (y) y))

(:: main Int)
(fn (main) (+ (+ (tagShape) (area (mk 2))) (+ call (+ bump (+ (twice 3) (adder 10 5))))))
"""
fix_path = os.path.join(FIXDIR, "fix-generated.ax")
open(fix_path, "w", encoding="utf-8").write(FIX)
fix_uri = "file://" + fix_path
fmt_uri = "file://" + os.path.join(FIXDIR, "fix-formatted.ax")
fixed_uri = "file://" + os.path.join(FIXDIR, "fix-fixed.ax")
exp_uri = "file://" + os.path.join(FIXDIR, "fix-expansion.ax")
exp2_uri = "file://" + os.path.join(FIXDIR, "fix-expansion-impl.ax")


def locate_in(src, context, name):
    """`name` at its first occurrence INSIDE the first occurrence of
    `context` - for a one-letter name the document holds in many
    places, such as the binder `x` of `(let ((x 1)) ...)`."""
    i = src.index(context)
    k = src.index(name, i, i + len(context))
    ln, text, col = line_of(src, k)
    start = u16(text[:col])
    return {"line": ln, "start": start, "end": start + u16(name)}


def cut(src, before, after):
    """The one TOKEN written between `before` and `after` - a name read
    out of the document rather than written down beside it. A token,
    not a slice from the first `before` to the next `after`: the first
    `(fn (` in the document is not the fn the caller means."""
    m = re.search(re.escape(before) + r"([^\s()]+)" + re.escape(after), src)
    if not m:
        sys.exit(f"FAIL: nothing in the FIX document sits between {before!r} "
                 f"and {after!r} - an anchor has drifted from the text")
    return m.group(1)


# --- what the document says --------------------------------------------
BINDER = locate_in(FIX, "(let ((x 1))", "x")       # AX3012's fix goes HERE
SET_X = locate_in(FIX, "(set x 2)", "x")           # ...not where it anchors
HELPR = locate(FIX, "helpr", 1)                    # AX3001's misspelt call
HELPER_NAME = cut(FIX, "(fn (", " n) (+ n 1))")    # ...and the name it meant
TWICE_NAME = cut(FIX, "(fn (", " x)   (+ x")       # the unsigned fn
TWICE_LINE = locate(FIX, "(fn (" + TWICE_NAME, 1)["line"]
ADDER_NAME = cut(FIX, "(fn (", " n) (lambda (y) y))")  # unsigned, with a type the checker cannot resolve
ADDER_LINE = locate(FIX, "(fn (" + ADDER_NAME, 1)["line"]
# The eq-deriving macro: its name, the capability record's own name,
# the invocation's argument, the name `syntax/join` makes for the
# generated fn, and the binder prefix `syntax/binders` spells.
EQ_MACRO = cut(FIX, "(macro ", " ((")
EQ_CAP = cut(FIX, "(struct ", " (a)")
EQ_ARG = cut(FIX, "(" + EQ_MACRO + " ", ")\n\n(:: helper")
EQ_USE = locate(FIX, "(" + EQ_MACRO + " " + EQ_ARG + ")", 1)
EQ_USE = {"line": EQ_USE["line"], "start": EQ_USE["start"] + 1}
EQ_JOIN = cut(FIX, "(:: (syntax/join ", " T) (-> T T Bool))")
EQ_GEN_NAME = EQ_JOIN + EQ_ARG                      # what the join makes
BINDER_PREFIX = cut(FIX, "(syntax/binders C ", "))\n")
MAIN_DECL = locate(FIX, "main", 2)                 # `(fn (main) ...)`; 1 is the `::`
SHAPE_DECL = locate(FIX, "Shape", 1)               # `(data Shape ...)`
MK_USE = locate_in(FIX, "(mk 2)", "mk")            # returns Shape
HELPER_USE = locate_in(FIX, "(:: helper", "helper")  # returns Int
PARAM_S = locate_in(FIX, "(area s)", "s")          # a parameter typed Shape
CIRCLE_USE = locate_in(FIX, "(Circle n)", "Circle")  # a constructor of Shape
DERIVE_DECL = locate(FIX, "deriveTag", 1)          # the macro's own name
DERIVE_USE = locate(FIX, "deriveTag", 3)           # the invocation (2 is the rule head)
MACRO_NAME = cut(FIX, "(pub macro ", "\n")
INV_ARG = cut(FIX, "(" + MACRO_NAME + " ", ")\n\n; A capability")
GEN_NAME = cut(FIX, "(syntax/join ", " T)") + INV_ARG   # what the join makes
TPL_LIT = cut(FIX, "(pub fn ((syntax/join tag T)) ", ")))")
BROKEN_FIX = FIX + "\n("
FIX_LINES = FIX.split("\n")
WHOLE = {"start": {"line": 0, "character": 0},
         "end": {"line": len(FIX_LINES) - 1, "character": u16(FIX_LINES[-1])}}

# --- what the compiler's own commands say --------------------------------
fmt_copy = os.path.join(FIXDIR, "fmt-copy.ax")
open(fmt_copy, "w", encoding="utf-8").write(FIX)
subprocess.run([stage1, "fmt", fmt_copy], capture_output=True, cwd=FIXDIR)
FMT = open(fmt_copy, encoding="utf-8").read()


def axsym_type(path, name):
    """The quoted type `axiom symbols` prints for `name`, or "". The
    command exits 1 on a file with errors and prints its table anyway,
    so stdout is read whatever the status."""
    p = subprocess.run([stage1, "--diagnostic-format=ai", "symbols", path],
                       capture_output=True, cwd=FIXDIR)
    for line in p.stdout.decode("utf-8", "replace").split("\n"):
        m = re.match(r'F ' + re.escape(name) + r' \S+ "([^"]*)"', line)
        if m:
            return m.group(1)
    return ""


def to_source_type(s):
    """The checker's notation, which `symbols` prints, rewritten into
    the parser's: `(Int -> (Int -> Bool))` is `(-> Int Int Bool)`,
    `Maybe Int` is `(Maybe Int)`, `[Int]`, `()` and `(A, B)` keep their
    shapes, `*T` is `(* T)`. A second implementation of the server's
    own type writer, from the grammar in parser.ax's parseTypeParens."""
    toks = re.findall(r"->|\(|\)|\[|\]|,|\*mut|\*|[A-Za-z_][A-Za-z0-9_']*", s)
    i = 0

    def atom():
        nonlocal i
        t = toks[i]
        i += 1
        if t == "(":
            groups, cur, arrow = [], [], False
            while toks[i] != ")":
                if toks[i] == "->":
                    arrow, i = True, i + 1
                    groups.append(cur)
                    cur = []
                elif toks[i] == ",":
                    i += 1
                    groups.append(cur)
                    cur = []
                else:
                    cur.append(atom())
            i += 1
            groups.append(cur)
            if arrow:
                return ("arrow", [seq(g) for g in groups])
            if groups == [[]]:
                return ("unit",)
            if len(groups) == 1:
                return seq(groups[0])
            return ("tuple", [seq(g) for g in groups])
        if t == "[":
            items = []
            while toks[i] != "]":
                items.append(atom())
            i += 1
            return ("list", seq(items))
        if t in ("*", "*mut"):
            return ("ptr", atom())
        return ("name", t)

    def seq(items):
        return items[0] if len(items) == 1 else ("app", items)

    def render(n):
        if n[0] == "name":
            return n[1]
        if n[0] == "app":
            return "(" + " ".join(render(x) for x in n[1]) + ")"
        if n[0] == "arrow":
            parts = list(n[1])
            while parts[-1][0] == "arrow":       # right-nested arrows flatten
                parts = parts[:-1] + list(parts[-1][1])
            return "(-> " + " ".join(render(x) for x in parts) + ")"
        if n[0] == "tuple":
            return "(" + " ".join(render(x) for x in n[1]) + ")"
        if n[0] == "unit":
            return "()"
        if n[0] == "list":
            return "[" + render(n[1]) + "]"
        return "(* " + render(n[1]) + ")"

    items = []
    while i < len(toks):
        items.append(atom())
    return render(seq(items))


def letterize(s):
    """The checker's unresolved type variables - `_tN`, which no
    signature may spell (the parser reads a type variable as a name
    starting with a lowercase letter) - each replaced by the first
    letter the type does not already use, in order of appearance: a
    second implementation of the server's `lspFreshRenames`."""
    used = {t for t in re.findall(r"[A-Za-z_][A-Za-z0-9_']*", s)
            if t[0].islower() and not re.fullmatch(r"_t\d+", t)}
    ren = {}
    for v in re.findall(r"_t\d+", s):
        if v not in ren:
            ren[v] = next(c for c in "abcdefghijklmnopqrstuvwxyz" if c not in used)
            used.add(ren[v])
    return re.sub(r"_t\d+", lambda m: ren[m.group(0)], s)


sym_copy = os.path.join(FIXDIR, "sym-copy.ax")
open(sym_copy, "w", encoding="utf-8").write(FIX)
AXSYM_TWICE = axsym_type(sym_copy, TWICE_NAME)
SRC_TYPE = to_source_type(AXSYM_TWICE) if AXSYM_TWICE else ""
ASSIST_TEXT = "(:: " + TWICE_NAME + " " + SRC_TYPE + ")\n"
ASSIST_AT = {"line": TWICE_LINE, "character": 0}
AXSYM_ADDER = axsym_type(sym_copy, ADDER_NAME)
ADDER_LETTERED = letterize(AXSYM_ADDER)
ADDER_SRC_TYPE = to_source_type(ADDER_LETTERED) if ADDER_LETTERED else ""
ADDER_ASSIST_TEXT = "(:: " + ADDER_NAME + " " + ADDER_SRC_TYPE + ")\n"
ADDER_AT = {"line": ADDER_LINE, "character": 0}

# Every derived string has to be non-empty and mean what it is used
# for, or the assertions below compare "" against "".
for what, text in (("formatted text", FMT), ("helper name", HELPER_NAME),
                   ("unsigned fn name", TWICE_NAME), ("symbols type", AXSYM_TWICE),
                   ("source type", SRC_TYPE), ("macro name", MACRO_NAME),
                   ("generated name", GEN_NAME), ("template literal", TPL_LIT),
                   ("adder symbols type", AXSYM_ADDER), ("adder source type", ADDER_SRC_TYPE),
                   ("eq macro", EQ_MACRO), ("eq capability", EQ_CAP), ("eq argument", EQ_ARG),
                   ("eq generated name", EQ_GEN_NAME), ("binder prefix", BINDER_PREFIX)):
    if not text.strip():
        sys.exit(f"FAIL: the derived {what} is empty - every FIX assertion "
                 f"resting on it would compare nothing against nothing")
if FMT == FIX:
    sys.exit("FAIL: `fmt` left the FIX document unchanged, so a formatting "
             "edit cannot be observed on it - restore the misformatted fn")
if "->" not in AXSYM_TWICE:
    sys.exit(f"FAIL: symbols printed {AXSYM_TWICE!r} for {TWICE_NAME}, not an "
             f"arrow - the rewrite into the parser's spelling would be a no-op")
# The fresh-variable rule can only be observed on a type that has one.
if not re.search(r"_t\d+", AXSYM_ADDER) or ADDER_LETTERED == AXSYM_ADDER:
    sys.exit(f"FAIL: symbols printed {AXSYM_ADDER!r} for {ADDER_NAME}, which carries "
             f"no unresolved `_tN` variable - the assist's renaming of one would go untested")
if GEN_NAME in FIX.split("(fn (main)")[0]:
    sys.exit(f"FAIL: {GEN_NAME!r} is written in the document above `main`, so "
             f"the expansion check could not tell generated from written")


def to_index(src, pos):
    """A string index for an LSP position: the line's start plus as many
    characters as it takes to reach `character` UTF-16 units."""
    lines = src.split("\n")
    base = sum(len(l) + 1 for l in lines[:pos["line"]])
    line, units, k = lines[pos["line"]], 0, 0
    while units < pos["character"]:
        units += u16(line[k])
        k += 1
    return base + k


def apply_edits(src, edits):
    """Every (range, newText) applied to `src`, last first so the
    earlier indices stay valid; the edits never overlap."""
    spans = sorted(((to_index(src, e["range"]["start"]),
                     to_index(src, e["range"]["end"]), e["newText"]) for e in edits),
                   reverse=True)
    for s, e, text in spans:
        src = src[:s] + text + src[e:]
    return src


def fixreq(rid, method, params):
    return {"jsonrpc": "2.0", "id": rid, "method": method, "params": params}


def fixdoc(uri, extra=None):
    p = {"textDocument": {"uri": uri}}
    p.update(extra or {})
    return p


def at(p):
    return {"line": p["line"], "character": p["start"]}


def action_req(rid, rng):
    return fixreq(rid, "textDocument/codeAction",
                  fixdoc(fix_uri, {"range": rng, "context": {"diagnostics": []}}))


def point(p):
    return {"start": at(p), "end": at(p)}


def line_range(ln):
    return {"start": {"line": ln, "character": 0}, "end": {"line": ln, "character": 0}}


HELPER_SIG_LINE = locate(FIX, "(:: helper", 1)["line"]
fix_session = b"".join(frame(m) for m in [
    fixreq(1, "initialize", {}),
    {"jsonrpc": "2.0", "method": "textDocument/didOpen",
     "params": {"textDocument": {"uri": fix_uri, "languageId": "axiom",
                                 "version": 1, "text": FIX}}},
    fixreq(2, "textDocument/formatting",
           fixdoc(fix_uri, {"options": {"tabSize": 2, "insertSpaces": True}})),
    action_req(3, WHOLE),
    action_req(4, line_range(HELPER_SIG_LINE)),
    action_req(5, line_range(TWICE_LINE)),
    fixreq(6, "textDocument/typeDefinition", fixdoc(fix_uri, {"position": at(MK_USE)})),
    fixreq(7, "textDocument/typeDefinition", fixdoc(fix_uri, {"position": at(HELPER_USE)})),
    fixreq(8, "textDocument/typeDefinition", fixdoc(fix_uri, {"position": at(PARAM_S)})),
    fixreq(9, "textDocument/typeDefinition", fixdoc(fix_uri, {"position": at(CIRCLE_USE)})),
    fixreq(10, "textDocument/codeLens", fixdoc(fix_uri)),
    fixreq(11, "axiom/expandMacro", fixdoc(fix_uri, {"position": at(DERIVE_USE)})),
    fixreq(12, "axiom/expandMacro", fixdoc(fix_uri, {"position": at(DERIVE_DECL)})),
    fixreq(13, "axiom/expandMacro", fixdoc(fix_uri, {"position": at(MAIN_DECL)})),
    fixreq(25, "axiom/expandMacro", fixdoc(fix_uri, {"position": at(EQ_USE)})),
    {"jsonrpc": "2.0", "method": "textDocument/didOpen",
     "params": {"textDocument": {"uri": fmt_uri, "languageId": "axiom",
                                 "version": 1, "text": FMT}}},
    fixreq(14, "textDocument/formatting", fixdoc(fmt_uri, {"options": {}})),
    {"jsonrpc": "2.0", "method": "textDocument/didChange",
     "params": {"textDocument": {"uri": fix_uri, "version": 2},
                "contentChanges": [{"text": BROKEN_FIX}]}},
    fixreq(20, "textDocument/formatting", fixdoc(fix_uri, {"options": {}})),
    action_req(21, WHOLE),
    fixreq(22, "textDocument/typeDefinition", fixdoc(fix_uri, {"position": at(MK_USE)})),
    fixreq(23, "textDocument/codeLens", fixdoc(fix_uri)),
    fixreq(24, "axiom/expandMacro", fixdoc(fix_uri, {"position": at(DERIVE_USE)})),
    fixreq(30, "shutdown", None),
    {"jsonrpc": "2.0", "method": "exit", "params": None},
])
fp = subprocess.run([stage1, "lsp"], input=fix_session, capture_output=True, cwd=FIXDIR)
fmsgs, ftail = unframe(fp.stdout)
fresp = {m["id"]: m for m in fmsgs if "id" in m}
fcaps = (fresp.get(1, {}).get("result") or {}).get("capabilities") or {}


def fres(rid):
    return fresp.get(rid, {}).get("result")


def action_of(rid, kind, code=None, title=None):
    """The one action of `kind` (and, for a quickfix, of diagnostic
    `code`; for an assist, of `title`) request `rid` answered, or None."""
    for a in fres(rid) or []:
        if a.get("kind") != kind:
            continue
        if title is not None and a.get("title") != title:
            continue
        if code is None or [d.get("code") for d in a.get("diagnostics") or []] == [code]:
            return a
    return None


def one_edit(action):
    """The single TextEdit an action's WorkspaceEdit makes in fix_uri."""
    changes = ((action or {}).get("edit") or {}).get("changes") or {}
    edits = changes.get(fix_uri) or []
    return edits[0] if len(edits) == 1 and len(changes) == 1 else None


def edit_is(action, rng, text):
    e = one_edit(action)
    if e is None:
        return f"has no single edit in the document ({action!r:.200})"
    if e.get("range") != rng:
        return f"edits {e.get('range')}, want {rng}"
    if e.get("newText") != text:
        return f"writes {e.get('newText')!r}, want {text!r}"
    return ""


def landed_in(rid, uri, at_, resp):
    """`landed`, over THIS session's responses: did request `rid`
    answer a Location at `at_` in `uri`? The reason it did not, or ""."""
    r = resp.get(rid, {}).get("result")
    if r is None:
        return f"request {rid} answered null"
    if r.get("uri") != uri:
        return f"request {rid} answered {r.get('uri')}, want {uri}"
    if r.get("range") != rng(at_):
        return f"request {rid} answered range {r.get('range')}, want {rng(at_)}"
    return ""


def lens_named(rid, command):
    for l in fres(rid) or []:
        if (l.get("command") or {}).get("command") == command:
            return l
    return None


ax3012 = action_of(3, "quickfix", "AX3012")
ax3001 = action_of(3, "quickfix", "AX3001")
assist = action_of(3, "refactor.rewrite", title="Add type signature for `" + TWICE_NAME + "`")
assist_adder = action_of(3, "refactor.rewrite", title="Add type signature for `" + ADDER_NAME + "`")
run_lens = lens_named(10, "axiom.run")
exp_lens = lens_named(10, "axiom.expandMacro")
r11 = fres(11) or {}
r25 = fres(25) or {}
fwhy = ""
if fp.returncode != 0:
    fwhy = f"the server exited {fp.returncode}: {fp.stderr[:200]!r}"
elif ftail:
    fwhy = f"{len(ftail)} trailing bytes after the last frame"
elif fcaps.get("documentFormattingProvider") is not True:
    fwhy = f"documentFormattingProvider is not advertised: {sorted(fcaps)}"
elif (fcaps.get("codeActionProvider") or {}).get("codeActionKinds") != ["quickfix", "refactor.rewrite", "refactor.extract"]:
    fwhy = f"codeActionProvider is {fcaps.get('codeActionProvider')!r}, want the three kinds"
elif fcaps.get("typeDefinitionProvider") is not True:
    fwhy = f"typeDefinitionProvider is not advertised: {sorted(fcaps)}"
elif fcaps.get("codeLensProvider") != {"resolveProvider": False}:
    fwhy = f"codeLensProvider is {fcaps.get('codeLensProvider')!r}"
elif (fcaps.get("experimental") or {}).get("expandMacro") is not True:
    fwhy = f"experimental.expandMacro is not advertised: {fcaps.get('experimental')!r}"
# --- formatting ---------------------------------------------------------
elif fres(2) != [{"range": WHOLE, "newText": FMT}]:
    fwhy = (f"formatting answered {json.dumps(fres(2))[:300]}, want one edit over "
            f"{WHOLE} whose text is what `fmt` wrote ({len(FMT)} bytes)")
elif fres(14) != []:
    fwhy = f"formatting an already-formatted document answered {fres(14)!r:.200}, want []"
# --- code actions --------------------------------------------------------
elif len(fres(3) or []) != 4:
    fwhy = (f"the whole-document code action request answered {len(fres(3) or [])} "
            f"action(s), want 2 quickfixes and 2 assists: {json.dumps(fres(3))[:400]}")
elif ax3012 is None:
    fwhy = f"no quickfix carrying the AX3012 diagnostic: {json.dumps(fres(3))[:400]}"
elif edit_is(ax3012, rng(BINDER), "mut " + cut(FIX, "(let ((", " 1))")):
    fwhy = ("the AX3012 quickfix " + edit_is(ax3012, rng(BINDER), "mut x")
            + f" - the fix goes on the BINDER at {rng(BINDER)}, not the `set` at {rng(SET_X)}")
elif ax3012.get("isPreferred") is not True:
    fwhy = "the AX3012 quickfix is not isPreferred; a compiler-written fix is THE fix"
elif ax3001 is None:
    fwhy = f"no quickfix carrying the AX3001 diagnostic: {json.dumps(fres(3))[:400]}"
elif edit_is(ax3001, rng(HELPR), HELPER_NAME):
    fwhy = "the AX3001 quickfix " + edit_is(ax3001, rng(HELPR), HELPER_NAME)
elif (ax3001["diagnostics"][0].get("range") != rng(HELPR)
      or ax3001["diagnostics"][0].get("severity") != 1):
    fwhy = f"the AX3001 quickfix carries diagnostic {ax3001['diagnostics'][0]!r:.200}"
elif assist is None:
    fwhy = f"no refactor.rewrite assist offered: {json.dumps(fres(3))[:400]}"
elif assist.get("title") != "Add type signature for `" + TWICE_NAME + "`":
    fwhy = f"the assist is titled {assist.get('title')!r}"
elif edit_is(assist, {"start": ASSIST_AT, "end": ASSIST_AT}, ASSIST_TEXT):
    fwhy = ("the assist " + edit_is(assist, {"start": ASSIST_AT, "end": ASSIST_AT}, ASSIST_TEXT)
            + f" - symbols printed {AXSYM_TWICE!r}, which is {SRC_TYPE!r} in the parser's spelling")
# The type the checker could not resolve: `symbols` prints `_tN`, which
# no signature may spell, so the assist writes it as a type variable
# the parser reads - and the checker then accepts (the second session
# below holds the applied document clean).
elif assist_adder is None:
    fwhy = f"no assist offered for `{ADDER_NAME}`, whose inferred type carries an unresolved variable: {json.dumps(fres(3))[:400]}"
elif edit_is(assist_adder, {"start": ADDER_AT, "end": ADDER_AT}, ADDER_ASSIST_TEXT):
    fwhy = ("the assist for `" + ADDER_NAME + "` " + edit_is(assist_adder, {"start": ADDER_AT, "end": ADDER_AT}, ADDER_ASSIST_TEXT)
            + f" - symbols printed {AXSYM_ADDER!r}, whose `_tN` must be written as a lowercase variable: {ADDER_SRC_TYPE!r}")
elif fres(4) != []:
    fwhy = f"a range on a line with nothing to fix answered {fres(4)!r:.200}, want []"
elif [a.get("kind") for a in fres(5) or []] != ["refactor.rewrite"]:
    fwhy = f"a range on the unsigned fn's line answered {fres(5)!r:.300}, want the assist alone"
# --- type definition -----------------------------------------------------
elif landed_in(6, fix_uri, SHAPE_DECL, fresp):
    fwhy = "typeDefinition on a fn returning `Shape`: " + landed_in(6, fix_uri, SHAPE_DECL, fresp)
elif fres(7) is not None:
    fwhy = f"typeDefinition on a fn returning Int answered {fres(7)!r}, want null"
elif landed_in(8, fix_uri, SHAPE_DECL, fresp):
    fwhy = "typeDefinition on a parameter typed `Shape`: " + landed_in(8, fix_uri, SHAPE_DECL, fresp)
elif landed_in(9, fix_uri, SHAPE_DECL, fresp):
    fwhy = "typeDefinition on a constructor of `Shape`: " + landed_in(9, fix_uri, SHAPE_DECL, fresp)
# --- code lenses ---------------------------------------------------------
elif len(fres(10) or []) != 2:
    fwhy = f"codeLens answered {fres(10)!r:.300}, want a Run lens and an Expand lens"
elif run_lens is None or run_lens.get("range") != rng(MAIN_DECL):
    fwhy = f"the Run lens is {run_lens!r:.200}, want it over `main` at {rng(MAIN_DECL)}"
elif run_lens["command"].get("arguments") != [fix_path]:
    fwhy = f"the Run lens runs {run_lens['command'].get('arguments')!r}, want [{fix_path!r}]"
elif not run_lens["command"].get("title"):
    fwhy = "the Run lens has no title"
elif exp_lens is None or exp_lens.get("range") != rng(DERIVE_DECL):
    fwhy = f"the Expand lens is {exp_lens!r:.200}, want it over the macro's name at {rng(DERIVE_DECL)}"
elif exp_lens["command"].get("arguments") != [fix_uri, at(DERIVE_DECL)]:
    fwhy = f"the Expand lens carries {exp_lens['command'].get('arguments')!r}"
# --- expand macro --------------------------------------------------------
elif r11.get("name") != MACRO_NAME:
    fwhy = f"expandMacro on the invocation answered {fres(11)!r:.300}, want name {MACRO_NAME!r}"
elif GEN_NAME not in r11.get("expansion", ""):
    fwhy = f"the expansion does not carry the generated name {GEN_NAME!r}: {r11.get('expansion')!r}"
elif not re.search(r"\b" + re.escape(TPL_LIT) + r"\b", r11.get("expansion", "")):
    fwhy = f"the expansion does not carry the template's literal {TPL_LIT!r}: {r11.get('expansion')!r}"
elif fres(12) != r11:
    fwhy = f"expandMacro on the declaration answered {fres(12)!r:.300}, want the invocation's products"
elif fres(13) is not None:
    fwhy = f"expandMacro on `main` answered {fres(13)!r:.200}, want null"
# The fn product: named by `syntax/join`, not by the capability record
# (a free function has no dictionary to dispatch through), so a
# product known by name alone is invisible; the head is the template's
# with the argument substituted, and the binders `syntax/binders`
# spells `x#i` and hygiene renames `.k` come out as identifiers.
elif r25.get("name") != EQ_MACRO:
    fwhy = f"expandMacro on `({EQ_MACRO} {EQ_ARG})` answered {fres(25)!r:.300}, want name {EQ_MACRO!r}"
# `pub` or not: phase D stamps every product exported (expCopyDeclInto
# writes word 5), and the printer writes the tree it is given.
elif not re.search(r"\((?:pub )?fn \(" + re.escape(EQ_GEN_NAME) + r" a b\)", r25.get("expansion", "")):
    fwhy = (f"the eq expansion does not carry `(fn ({EQ_GEN_NAME} a b)`: "
            f"{r25.get('expansion')!r:.300}")
elif not re.search(r"(?<![A-Za-z0-9_'])" + re.escape(BINDER_PREFIX) + r"_\d+_\d+(?![A-Za-z0-9_'])", r25.get("expansion", "")) \
        or re.search(r"[A-Za-z0-9_'][#.][0-9]", r25.get("expansion", "")):
    fwhy = (f"the eq expansion's `syntax/binders` variables are not written as "
            f"identifiers `{BINDER_PREFIX}_<i>_<k>`: {r25.get('expansion')!r:.400}")
# --- a document that does not parse ---------------------------------------
elif fres(20) is not None:
    fwhy = f"formatting an unparseable document answered {fres(20)!r:.200}, want null"
elif fres(21) != []:
    fwhy = f"codeAction on an unparseable document answered {fres(21)!r:.200}, want []"
elif fres(22) is not None:
    fwhy = f"typeDefinition on an unparseable document answered {fres(22)!r:.200}, want null"
elif fres(23) != []:
    fwhy = f"codeLens on an unparseable document answered {fres(23)!r:.200}, want []"
elif fres(24) is not None:
    fwhy = f"expandMacro on an unparseable document answered {fres(24)!r:.200}, want null"

# The second session: the first one's answers, applied and opened.
EXPANSION = r11.get("expansion", "") if not fwhy else ""
EXPANSION2 = r25.get("expansion", "") if not fwhy else ""
FIXED = apply_edits(FIX, [one_edit(ax3012), one_edit(ax3001), one_edit(assist), one_edit(assist_adder)]) if not fwhy else FIX
fixed_diags = exp_diags = exp2_diags = None
gen_outline = []
sym_after = sym_after_adder = ""
if not fwhy:
    if FIXED == FIX:
        fwhy = "applying the four edits changed nothing"
    else:
        fixed_copy = os.path.join(FIXDIR, "fixed-copy.ax")
        open(fixed_copy, "w", encoding="utf-8").write(FIXED)
        sym_after = axsym_type(fixed_copy, TWICE_NAME)
        sym_after_adder = axsym_type(fixed_copy, ADDER_NAME)
        second = b"".join(frame(m) for m in [
            fixreq(1, "initialize", {}),
            {"jsonrpc": "2.0", "method": "textDocument/didOpen",
             "params": {"textDocument": {"uri": fixed_uri, "languageId": "axiom",
                                         "version": 1, "text": FIXED}}},
            {"jsonrpc": "2.0", "method": "textDocument/didOpen",
             "params": {"textDocument": {"uri": exp_uri, "languageId": "axiom",
                                         "version": 1, "text": EXPANSION}}},
            {"jsonrpc": "2.0", "method": "textDocument/didOpen",
             "params": {"textDocument": {"uri": exp2_uri, "languageId": "axiom",
                                         "version": 1, "text": EXPANSION2}}},
            fixreq(2, "textDocument/documentSymbol", fixdoc(exp_uri)),
            fixreq(3, "shutdown", None),
            {"jsonrpc": "2.0", "method": "exit", "params": None},
        ])
        sp = subprocess.run([stage1, "lsp"], input=second, capture_output=True, cwd=FIXDIR)
        smsgs, stail = unframe(sp.stdout)
        pubs = {m["params"]["uri"]: m["params"]["diagnostics"] for m in smsgs
                if m.get("method") == "textDocument/publishDiagnostics"}
        sresp = {m["id"]: m for m in smsgs if "id" in m}
        fixed_diags = pubs.get(fixed_uri)
        exp_diags = pubs.get(exp_uri)
        exp2_diags = pubs.get(exp2_uri)
        gen_outline = sresp.get(2, {}).get("result")
        parse_codes = [d.get("code") for d in exp_diags or []
                       if str(d.get("code", "")).startswith(("AX1", "AX2"))]
        parse_codes2 = [d.get("code") for d in exp2_diags or []
                        if str(d.get("code", "")).startswith(("AX1", "AX2"))]
        if sp.returncode != 0 or stail:
            fwhy = f"the second session exited {sp.returncode} with {len(stail)} trailing bytes"
        elif fixed_diags != []:
            fwhy = (f"the document with every quickfix and both assists applied still "
                    f"publishes {[(d.get('code'), d['range']['start']) for d in fixed_diags or []]}"
                    f"; the fixed text was:\n{FIXED}")
        elif sym_after != AXSYM_TWICE:
            fwhy = (f"after inserting {ASSIST_TEXT.strip()!r}, symbols prints "
                    f"{sym_after!r} for {TWICE_NAME}, where it printed {AXSYM_TWICE!r} "
                    f"before - the signature does not mean what the assist claimed")
        elif sym_after_adder != ADDER_LETTERED:
            fwhy = (f"after inserting {ADDER_ASSIST_TEXT.strip()!r}, symbols prints "
                    f"{sym_after_adder!r} for {ADDER_NAME}, want {ADDER_LETTERED!r} - the "
                    f"unresolved variable written as a type variable, and nothing else changed")
        # A publish that never arrived would make the parse checks
        # below vacuous: an absent list has no parse codes in it.
        elif exp_diags is None or exp2_diags is None:
            fwhy = "the server published no diagnostics for an expansion document"
        elif parse_codes:
            fwhy = f"the expansion text does not parse ({parse_codes}):\n{EXPANSION}"
        elif parse_codes2:
            fwhy = f"the impl expansion text does not parse ({parse_codes2}):\n{EXPANSION2}"
        elif not isinstance(gen_outline, list) or [s.get("name") for s in gen_outline] != [GEN_NAME]:
            fwhy = (f"the expansion's outline is {gen_outline!r:.300}, want exactly "
                    f"[{GEN_NAME!r}] - the one declaration the macro generated")
        elif {s.get("kind") for s in gen_outline} != {12}:
            fwhy = f"the generated declaration is not a Function in the outline: {gen_outline!r:.200}"

if fwhy:
    print(f"FAIL fix: {fwhy}")
    failed += 1
else:
    print(f"ok   formatting (one edit over {len(FIX_LINES)} lines whose text is the "
          f"{len(FMT)} bytes `fmt` wrote to a copy; [] on the formatted text; null "
          f"when the document does not parse)")
    print(f"ok   code-actions (AX3012 fixed at the BINDER {rng(BINDER)['start']} not the "
          f"`set` at {rng(SET_X)['start']}, AX3001 fixed to {HELPER_NAME!r}, the assist "
          f"inserting {ASSIST_TEXT.strip()!r} from symbols' {AXSYM_TWICE!r} and "
          f"{ADDER_ASSIST_TEXT.strip()!r} from {AXSYM_ADDER!r}; all four applied check "
          f"clean and symbols agrees; [] off the fixes and when the document does not "
          f"parse)")
    print(f"ok   type-definition (a fn's result, a header parameter and a constructor "
          f"all landing on `{cut(FIX, '(data ', ' ')}`; null for Int and for a document "
          f"that does not parse)")
    print(f"ok   code-lens (Run over `main` with {os.path.basename(fix_path)!r}, Expand "
          f"over `{MACRO_NAME}`; [] when the document does not parse)")
    print(f"ok   expand-macro (`{MACRO_NAME}` at its invocation and at its declaration "
          f"rendering {GEN_NAME!r} with literal {TPL_LIT}; the text re-parses with an "
          f"outline of exactly that name; `{EQ_MACRO}` rendering `(fn ({EQ_GEN_NAME} "
          f"a b)` with its binders as identifiers, re-parsing clean; null on `main` "
          f"and when the document does not parse)")
    passed += 5
shutil.rmtree(FIXDIR, ignore_errors=True)

# ---------------------------------------------------------------------
# CODE ACTIONS, THE THREE ASSISTS THE COMPILER DOES NOT WRITE: an
# import for a name another module declares (on AX3001), `pub` for a
# name a module keeps private (on AX3023), and an extraction to a
# `let` (on a range, with no diagnostic). A helper module and five
# documents written HERE, into a temp directory the server resolves
# imports from, with every expected edit DERIVED from their bytes and
# every applied result handed back to the compiler's own commands:
#
#   * on `(shout 1)` in a document with no import at all, the import
#     quickfix must insert `(import CaHelper (shout))` as the FIRST
#     line, and on `(strLen "ab")` in the same document `(import Str
#     (strLen))` - the sibling-directory leg and the `AXIOM_STDLIB` leg
#     of the resolver's own search; the request over `shout` must not
#     carry `strLen`'s action; with both applied, `check` must answer
#     OK;
#   * on `(whisper 2)` beside `(import CaHelper (shout))`, the name IS
#     public and the list lacks it - AX3023, measured - so the edit
#     adds ` whisper` just inside the list's closing paren;
#   * on `(shout 1)` beneath `(import IO)`, the new import goes on its
#     own line after the last import, not at the top;
#   * on `(quiet 1)`, imported by name from a module that declares it
#     without `pub`, ONE action whether asked at the call or at the
#     import's own diagnostic, whose edit is keyed by the HELPER's URI
#     and inserts `pub ` after the opening paren of BOTH the `fn` and
#     its `::` - `check` refuses either alone, measured - and a
#     whole-document range, which meets both diagnostics, still answers
#     it once; applied to copies of both files, `check` must answer OK;
#   * on `(tick 3)`, a call whose side effect the program performs
#     exactly once, the extraction must replace the STATEMENT holding
#     it - the block child, not the fn body - by a `let` naming the call
#     `extracted2`, because the document already binds `extracted`; the
#     result, run with `axiom run`, must print the same bytes and exit
#     with the same status as the original, which prints `tick` once
#     and exits 3 = (3+1) + (4+5) - 10, so a duplicated call is a
#     second `tick` line; on `(> n 0)`, the test of an `if`, the whole
#     `if` is the statement. On `tick 3` (two items), `(tick n)` (a
#     branch of an `if`), `(+ y 2)` (its `y` bound inside the
#     statement), the `+` head, an empty range and an unparseable
#     document: no extraction.
# ---------------------------------------------------------------------
CADIR = tempfile.mkdtemp(prefix="axiom-ca-")
CA_HELPER = """; The module the assists reach into.
(pub :: shout (-> Int Int))
(pub fn (shout x) (+ x 1))

(pub :: whisper (-> Int Int))
(pub fn (whisper x) (- x 1))

(:: quiet (-> Int Int))
(fn (quiet x) (* x 2))
"""
CA_IMPORT = """(:: main Int)
(fn (main) (+ (shout 1) (strLen "ab")))
"""
CA_LISTED = """(import CaHelper (shout))

(:: main Int)
(fn (main) (+ (shout 1) (whisper 2)))
"""
CA_AFTER = """(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main) {
  (println "x")
  (shout 1)
})
"""
CA_PUBLIC = """(import CaHelper (quiet))

(:: main Int)
(fn (main) (quiet 1))
"""
CA_EXTRACT = """(import IO)

(:: tick (-> Int Int))
;@axiom:effect(io)
(fn (tick n) {
  (println "tick")
  (+ n 1)
})

(:: keep (-> Int Int))
(fn (keep n) (let ((extracted 5)) (+ n extracted)))

(:: pick (-> Int Int))
;@axiom:effect(io)
(fn (pick n) (if (> n 0) (tick n) 0))

(:: main Int)
;@axiom:effect(io)
(fn (main) {
  (println "start")
  (let ((y 1)) (+ y 2))
  (- (+ (tick 3) (keep 4)) 10)
})
"""
CA_DOCS = {"ca-import.ax": CA_IMPORT, "ca-listed.ax": CA_LISTED, "ca-after.ax": CA_AFTER,
           "ca-public.ax": CA_PUBLIC, "ca-extract.ax": CA_EXTRACT}
HELPER_FILE = "CaHelper.ax"
open(os.path.join(CADIR, HELPER_FILE), "w", encoding="utf-8").write(CA_HELPER)
for ca_name, ca_text in CA_DOCS.items():
    open(os.path.join(CADIR, ca_name), "w", encoding="utf-8").write(ca_text)


def ca_uri(name):
    return "file://" + os.path.join(CADIR, name)


HELPER_URI = ca_uri(HELPER_FILE)
HELPER_MOD = HELPER_FILE[:-3]                       # the name the resolver gives the file
SHOUT = cut(CA_HELPER, "(pub fn (", " x) (+ x 1))")
WHISPER = cut(CA_HELPER, "(pub fn (", " x) (- x 1))")
QUIET = cut(CA_HELPER, "(fn (", " x) (* x 2))")     # the private one
STRLEN = cut(CA_IMPORT, "(", " \"ab\")")
IMP_SHOUT = locate(CA_IMPORT, SHOUT, 1)
IMP_STRLEN = locate(CA_IMPORT, STRLEN, 1)
LISTED_WHISPER = locate(CA_LISTED, WHISPER, 1)
LIST_FORM = locate(CA_LISTED, "(" + SHOUT + ")", 1)   # the import's name list
LIST_INSERT = {"line": LIST_FORM["line"], "character": LIST_FORM["end"] - 1}
AFTER_SHOUT = locate(CA_AFTER, SHOUT, 1)
AFTER_IMPORT = locate(CA_AFTER, "(import IO)", 1)
AFTER_INSERT = {"line": AFTER_IMPORT["line"], "character": AFTER_IMPORT["end"]}
# The import-list diagnostic anchors on the import's MODULE token
# (measured: `m.ax:1:9-17` for `(import CaHelper (quiet))`), not on
# the listed name, so that is where "the import's own diagnostic" is.
PUB_LISTED = locate(CA_PUBLIC, HELPER_MOD, 1)
PUB_CALL = locate(CA_PUBLIC, QUIET, 2)              # the call; 1 is in the list
H_SIG = locate(CA_HELPER, "(:: " + QUIET, 1)
H_FN = locate(CA_HELPER, "(fn (" + QUIET, 1)
PUB_INSERTS = sorted([(H_SIG["line"], 1, "pub "), (H_FN["line"], 1, "pub ")])
EX_CALL = locate(CA_EXTRACT, "(tick 3)", 1)
EX_STMT = CA_EXTRACT.split("\n")[EX_CALL["line"]].strip()   # the block child holding it
EX_STMT_AT = locate(CA_EXTRACT, EX_STMT, 1)
PICK = cut(CA_EXTRACT, "(fn (", " n) (if")
IF_TEST = locate(CA_EXTRACT, "(> n 0)", 1)
IF_LINE = CA_EXTRACT.split("\n")[IF_TEST["line"]]
IF_STMT = IF_LINE[len("(fn (" + PICK + " n) "):-1]           # the fn's body, an `if`
IF_STMT_AT = locate(CA_EXTRACT, IF_STMT, 1)
EX_TWO = locate(CA_EXTRACT, "tick 3", 1)
EX_BRANCH = locate(CA_EXTRACT, "(tick n)", 1)
EX_BOUND = locate(CA_EXTRACT, "(+ y 2)", 1)
EX_HEAD = locate_in(CA_EXTRACT, "(+ (tick 3)", "+")


def ca_fresh(src):
    """The binder the extraction must choose: `extracted`, or the first
    `extractedN` the document does not spell - a second implementation
    of the server's rule."""
    name, k = "extracted", 2
    while re.search(r"(?<![\w'-])" + re.escape(name) + r"(?![\w'-])", src):
        name = "extracted%d" % k
        k += 1
    return name


EX_NAME = ca_fresh(CA_EXTRACT)
EX_NEW = "(let ((" + EX_NAME + " (tick 3))) " + EX_STMT.replace("(tick 3)", EX_NAME) + ")"
IF_NEW = "(let ((" + EX_NAME + " (> n 0))) " + IF_STMT.replace("(> n 0)", EX_NAME) + ")"
EX_LINES = CA_EXTRACT.split("\n")
PUB_LINES = CA_PUBLIC.split("\n")
PUB_WHOLE = {"start": {"line": 0, "character": 0},
             "end": {"line": len(PUB_LINES) - 1, "character": u16(PUB_LINES[-1])}}
for what, text in (("public fn name", SHOUT), ("second public fn name", WHISPER),
                   ("private fn name", QUIET), ("stdlib name", STRLEN),
                   ("statement", EX_STMT), ("if statement", IF_STMT),
                   ("fresh binder", EX_NAME)):
    if not text.strip():
        sys.exit(f"FAIL: the derived {what} is empty - every assist assertion "
                 f"resting on it would compare nothing against nothing")
if EX_NAME == "extracted":
    sys.exit("FAIL: the extract document no longer binds `extracted`, so the "
             "fresh-name rule would go untested")
if not IF_STMT.startswith("(if ") or "(tick 3)" not in EX_STMT:
    sys.exit(f"FAIL: the derived statements {IF_STMT!r} / {EX_STMT!r} are not "
             f"the forms the extract checks describe")


def ca_req(rid, name, rng_):
    return fixreq(rid, "textDocument/codeAction",
                  fixdoc(ca_uri(name), {"range": rng_, "context": {"diagnostics": []}}))


def zero_at(pos):
    return {"start": pos, "end": pos}


ca_session = b"".join(frame(m) for m in [
    fixreq(1, "initialize", {}),
] + [
    {"jsonrpc": "2.0", "method": "textDocument/didOpen",
     "params": {"textDocument": {"uri": ca_uri(n), "languageId": "axiom",
                                 "version": 1, "text": t}}}
    for n, t in CA_DOCS.items()
] + [
    ca_req(2, "ca-import.ax", rng(IMP_SHOUT)),
    ca_req(3, "ca-import.ax", rng(IMP_STRLEN)),
    ca_req(4, "ca-listed.ax", rng(LISTED_WHISPER)),
    ca_req(5, "ca-after.ax", rng(AFTER_SHOUT)),
    ca_req(6, "ca-public.ax", rng(PUB_CALL)),
    ca_req(7, "ca-public.ax", rng(PUB_LISTED)),
    ca_req(8, "ca-public.ax", PUB_WHOLE),
    ca_req(9, "ca-extract.ax", rng(EX_CALL)),
    ca_req(10, "ca-extract.ax", rng(IF_TEST)),
    ca_req(11, "ca-extract.ax", rng(EX_TWO)),
    ca_req(12, "ca-extract.ax", rng(EX_BRANCH)),
    ca_req(13, "ca-extract.ax", rng(EX_BOUND)),
    ca_req(14, "ca-extract.ax", rng(EX_HEAD)),
    ca_req(15, "ca-extract.ax", point(EX_CALL)),
    {"jsonrpc": "2.0", "method": "textDocument/didChange",
     "params": {"textDocument": {"uri": ca_uri("ca-extract.ax"), "version": 2},
                "contentChanges": [{"text": CA_EXTRACT + "\n("}]}},
    ca_req(16, "ca-extract.ax", rng(EX_CALL)),
    fixreq(17, "shutdown", None),
    {"jsonrpc": "2.0", "method": "exit", "params": None},
])
cp = subprocess.run([stage1, "lsp"], input=ca_session, capture_output=True, cwd=CADIR)
cmsgs, ctail = unframe(cp.stdout)
cresp = {m["id"]: m for m in cmsgs if "id" in m}
ccaps = (cresp.get(1, {}).get("result") or {}).get("capabilities") or {}


def cres(rid):
    return cresp.get(rid, {}).get("result")


def ca_actions(rid, kind, title=None):
    return [a for a in cres(rid) or [] if a.get("kind") == kind
            and (title is None or a.get("title") == title)]


def ca_edits(action, uri):
    """Every TextEdit an action makes in `uri`, as (line, character,
    newText) triples of zero-width inserts - or the reason it is not
    a single-document WorkspaceEdit of inserts."""
    changes = ((action or {}).get("edit") or {}).get("changes") or {}
    if list(changes) != [uri]:
        return f"edits {sorted(changes)}, want exactly [{uri}]"
    out = []
    for e in changes[uri]:
        r = e.get("range") or {}
        if r.get("start") != r.get("end"):
            return f"has a non-insert edit {e!r:.200}"
        out.append((r["start"]["line"], r["start"]["character"], e.get("newText")))
    return sorted(out)


def ca_import_is(rid, name, mod, code, at, text):
    """Request `rid` must answer exactly one import action for `name`
    from `mod`, on a diagnostic of `code`, inserting `text` at `at` in
    the request's own document."""
    title = f"Import `{name}` from `{mod}`"
    acts = ca_actions(rid, "quickfix", title)
    if len(acts) != 1:
        return f"request {rid} answered {len(acts)} action(s) titled {title!r}: {json.dumps(cres(rid))[:300]}"
    a = acts[0]
    if [d.get("code") for d in a.get("diagnostics") or []] != [code]:
        return f"{title!r} carries diagnostics {a.get('diagnostics')!r:.200}, want one {code}"
    uri = ca_uri({2: "ca-import.ax", 3: "ca-import.ax", 4: "ca-listed.ax", 5: "ca-after.ax"}[rid])
    got = ca_edits(a, uri)
    if got != [(at["line"], at["character"], text)]:
        return f"{title!r} edits {got!r}, want one insert of {text!r} at {at}"
    return ""


def ca_check(path):
    """`check`'s verdict on `path`: "" for OK, else what it printed."""
    p = subprocess.run([stage1, "--diagnostic-format=ai", "check", path],
                       capture_output=True, cwd=os.path.dirname(path))
    if p.returncode == 0 and not p.stderr:
        return ""
    return f"exit {p.returncode}: {p.stderr.decode('utf-8', 'replace')[:300]}"


def ca_run(path):
    p = subprocess.run([stage1, "run", path], capture_output=True, cwd=os.path.dirname(path))
    return p.stdout, p.returncode


def ca_import_edits(rid, name, imported, mod):
    """The TextEdits the import action for `imported` from `mod` makes
    in document `name` - selected by TITLE, because the compiler's own
    typo quickfix sits beside it when a similar name is in scope
    (measured: `shout` beneath `(import IO)` also offers `stdout`)."""
    acts = ca_actions(rid, "quickfix", f"Import `{imported}` from `{mod}`")
    changes = ((acts[0] if acts else {}).get("edit") or {}).get("changes") or {}
    return changes.get(ca_uri(name)) or []


def ca_apply(rid, name, imported, mod):
    return apply_edits(CA_DOCS[name], ca_import_edits(rid, name, imported, mod))


pub_title = f"Make `{QUIET}` public in `{HELPER_MOD}`"
pub6 = ca_actions(6, "quickfix", pub_title)
pub7 = ca_actions(7, "quickfix", pub_title)
ex9 = ca_actions(9, "refactor.extract")
ex10 = ca_actions(10, "refactor.extract")
cawhy = ""
if cp.returncode != 0:
    cawhy = f"the server exited {cp.returncode}: {cp.stderr[:200]!r}"
elif ctail:
    cawhy = f"{len(ctail)} trailing bytes after the last frame"
elif (ccaps.get("codeActionProvider") or {}).get("codeActionKinds") != ["quickfix", "refactor.rewrite", "refactor.extract"]:
    cawhy = f"codeActionProvider is {ccaps.get('codeActionProvider')!r}, want quickfix, refactor.rewrite and refactor.extract"
# --- import ----------------------------------------------------------------
elif ca_import_is(2, SHOUT, HELPER_MOD, "AX3001", {"line": 0, "character": 0}, f"(import {HELPER_MOD} ({SHOUT}))\n"):
    cawhy = "import, no import present: " + ca_import_is(2, SHOUT, HELPER_MOD, "AX3001", {"line": 0, "character": 0}, f"(import {HELPER_MOD} ({SHOUT}))\n")
elif len(cres(2) or []) != 1:
    cawhy = f"the request over `{SHOUT}` answered {len(cres(2))} actions, want its import alone: {json.dumps(cres(2))[:300]}"
elif ca_import_is(3, STRLEN, "Str", "AX3001", {"line": 0, "character": 0}, f"(import Str ({STRLEN}))\n"):
    cawhy = "import from the stdlib: " + ca_import_is(3, STRLEN, "Str", "AX3001", {"line": 0, "character": 0}, f"(import Str ({STRLEN}))\n")
elif ca_import_is(4, WHISPER, HELPER_MOD, "AX3023", LIST_INSERT, " " + WHISPER):
    cawhy = "import, a public name the list lacks: " + ca_import_is(4, WHISPER, HELPER_MOD, "AX3023", LIST_INSERT, " " + WHISPER)
elif ca_import_is(5, SHOUT, HELPER_MOD, "AX3001", AFTER_INSERT, f"\n(import {HELPER_MOD} ({SHOUT}))"):
    cawhy = "import after the last import: " + ca_import_is(5, SHOUT, HELPER_MOD, "AX3001", AFTER_INSERT, f"\n(import {HELPER_MOD} ({SHOUT}))")
# --- make public -----------------------------------------------------------
elif len(pub6) != 1:
    cawhy = f"the request at the private call answered {len(pub6)} action(s) titled {pub_title!r}: {json.dumps(cres(6))[:300]}"
elif [d.get("code") for d in pub6[0].get("diagnostics") or []] != ["AX3023"]:
    cawhy = f"{pub_title!r} carries diagnostics {pub6[0].get('diagnostics')!r:.200}, want one AX3023"
elif ca_edits(pub6[0], HELPER_URI) != PUB_INSERTS:
    cawhy = (f"{pub_title!r} edits {ca_edits(pub6[0], HELPER_URI)!r}, want `pub ` inserted at "
             f"{PUB_INSERTS} of the helper - both the `::` and the `fn`, in the helper's own file")
elif len(pub7) != 1 or pub7[0].get("edit") != pub6[0].get("edit"):
    cawhy = f"the request at the import's own diagnostic answered {json.dumps(cres(7))[:300]}, want the same action"
elif [a.get("title") for a in cres(8) or []] != [pub_title]:
    cawhy = f"a whole-document range answered {[a.get('title') for a in cres(8) or []]}, want the one action once"
# --- extract ---------------------------------------------------------------
elif [a.get("kind") for a in cres(9) or []] != ["refactor.extract"]:
    cawhy = f"the range over `(tick 3)` answered {json.dumps(cres(9))[:300]}, want one refactor.extract"
elif ex9[0].get("title") != "Extract to `let`":
    cawhy = f"the extraction is titled {ex9[0].get('title')!r}"
elif ((ex9[0].get("edit") or {}).get("changes") or {}).get(ca_uri("ca-extract.ax")) != [{"range": rng(EX_STMT_AT), "newText": EX_NEW}]:
    cawhy = (f"the extraction edits {json.dumps((ex9[0].get('edit') or {}).get('changes'))[:400]}, want the "
             f"statement at {rng(EX_STMT_AT)} replaced by {EX_NEW!r}")
elif len(ex10) != 1 or ((ex10[0].get("edit") or {}).get("changes") or {}).get(ca_uri("ca-extract.ax")) != [{"range": rng(IF_STMT_AT), "newText": IF_NEW}]:
    cawhy = (f"the range over an `if`'s test answered {json.dumps(cres(10))[:400]}, want the whole "
             f"`if` at {rng(IF_STMT_AT)} replaced by {IF_NEW!r}")
elif any(ca_actions(rid, "refactor.extract") for rid in (11, 12, 13, 14, 15)):
    cawhy = ("an extraction was offered where none applies: " +
             str({rid: cres(rid) for rid in (11, 12, 13, 14, 15) if ca_actions(rid, "refactor.extract")})[:400])
elif cres(16) != []:
    cawhy = f"codeAction on the unparseable extract document answered {cres(16)!r:.200}, want []"

# The applied results, handed to the compiler.
CADIR2 = tempfile.mkdtemp(prefix="axiom-ca2-")
run0 = run1 = (b"", -1)
if not cawhy:
    fixed_import = apply_edits(CA_IMPORT, ca_import_edits(2, "ca-import.ax", SHOUT, HELPER_MOD)
                               + ca_import_edits(3, "ca-import.ax", STRLEN, "Str"))
    applied = {"ca-import-fixed.ax": fixed_import,
               "ca-listed-fixed.ax": ca_apply(4, "ca-listed.ax", WHISPER, HELPER_MOD),
               "ca-after-fixed.ax": ca_apply(5, "ca-after.ax", SHOUT, HELPER_MOD)}
    for ca_name, ca_text in applied.items():
        if ca_text == CA_DOCS[ca_name.replace("-fixed", "")]:
            cawhy = f"applying the import edit to {ca_name} changed nothing"
            break
        open(os.path.join(CADIR, ca_name), "w", encoding="utf-8").write(ca_text)
        verdict = ca_check(os.path.join(CADIR, ca_name))
        if verdict:
            cawhy = f"{ca_name}, the import applied, does not check clean ({verdict}); the text was:\n{ca_text}"
            break
if not cawhy:
    helper_changes = ((pub6[0].get("edit") or {}).get("changes") or {})
    fixed_helper = apply_edits(CA_HELPER, helper_changes.get(HELPER_URI) or [])
    open(os.path.join(CADIR2, HELPER_FILE), "w", encoding="utf-8").write(fixed_helper)
    open(os.path.join(CADIR2, "ca-public.ax"), "w", encoding="utf-8").write(CA_PUBLIC)
    verdict = ca_check(os.path.join(CADIR2, "ca-public.ax"))
    if fixed_helper == CA_HELPER:
        cawhy = "applying the make-public edit to the helper changed nothing"
    elif verdict:
        cawhy = f"with `pub ` applied, the importing document does not check clean ({verdict}); the helper was:\n{fixed_helper}"
if not cawhy:
    extracted = apply_edits(CA_EXTRACT, [{"range": rng(EX_STMT_AT), "newText": EX_NEW}])
    open(os.path.join(CADIR, "ca-extract-fixed.ax"), "w", encoding="utf-8").write(extracted)
    v0 = ca_check(os.path.join(CADIR, "ca-extract.ax"))
    v1 = ca_check(os.path.join(CADIR, "ca-extract-fixed.ax"))
    run0 = ca_run(os.path.join(CADIR, "ca-extract.ax"))
    run1 = ca_run(os.path.join(CADIR, "ca-extract-fixed.ax"))
    if v0 != v1:
        cawhy = f"`check` says {v1!r} of the extracted document and {v0!r} of the original"
    elif run0[1] != 3:
        cawhy = f"the original extract document exits {run0[1]}, want 3 - the run that the extraction is compared against is not the one the document describes"
    elif run0[0].count(b"tick") != 1:
        cawhy = f"the original prints `tick` {run0[0].count(b'tick')} time(s), want exactly once so a duplicated call would show: {run0[0]!r:.200}"
    elif run1 != run0:
        cawhy = (f"the extracted program printed {run1[0]!r:.200} and exited {run1[1]}, where the original "
                 f"printed {run0[0]!r:.200} and exited {run0[1]}; the extracted text was:\n{extracted}")

if cawhy:
    print(f"FAIL code-action-assists: {cawhy}")
    failed += 1
else:
    print(f"ok   import-assist (`{SHOUT}` from `{HELPER_MOD}` as the first line, `{STRLEN}` from "
          f"`Str` beside it, `{WHISPER}` added to an existing list, `{SHOUT}` on its own line "
          f"after `(import IO)`; each applied checks OK; the request over one name carries "
          f"only that name's action)")
    print(f"ok   make-public-assist (`{QUIET}` in `{HELPER_MOD}`: `pub ` inserted at lines "
          f"{PUB_INSERTS[0][0]} and {PUB_INSERTS[1][0]} of the helper's own file, the same "
          f"action from the call and from the import's diagnostic, once over the whole "
          f"document; applied, the importer checks OK)")
    print(f"ok   extract-assist (`(tick 3)` to `{EX_NAME}` over its statement, an `if`'s test "
          f"over the whole `if`; the extracted program prints the same {len(run0[0])} bytes "
          f"and exits {run0[1]}; nothing for two items, a branch, a captured binder, a head, "
          f"an empty range or an unparseable document)")
    passed += 3
shutil.rmtree(CADIR, ignore_errors=True)
shutil.rmtree(CADIR2, ignore_errors=True)
# =====================================================================
# END SECTION FIX TESTS
# =====================================================================


# ---------------------------------------------------------------------
# An editing session does not grow.
#
# This is the roadmap's §1 dependency edge measured on the thing that
# depends on it. The server reuses the compiler's frontend, so every
# edit re-parses and re-checks - and on a bump allocator that never
# frees, every one of those was retained for the life of the process:
# 8.3 MB after one `didChange` of a 16 KB file, 693.7 MB after two
# hundred. Flat now, because the loop reclaims to a mark after each
# message and carries the store and the reader's unconsumed bytes
# across the reclaim in one block.
#
# What makes this gate non-vacuous is the pair of checks together. RSS
# alone cannot tell reclamation from a server that died on message
# three: BOTH sessions must publish diagnostics for every edit and
# answer the shutdown, and only then does the memory comparison mean
# anything.


def run_measured(argv, payload, cwd):
    """Run a child on `payload` and answer (stdout, exit status, peak
    RSS in KiB). `os.wait4` gives the rusage of THIS child, which
    `RUSAGE_CHILDREN` does not - it reports a maximum over every child
    so far, so a smaller second run would read as the larger first."""
    rfd, wfd = os.pipe()
    orfd, owfd = os.pipe()
    pid = os.fork()
    if pid == 0:                                    # child
        os.dup2(rfd, 0)
        os.dup2(owfd, 1)
        for fd in (rfd, wfd, orfd, owfd):
            os.close(fd)
        os.chdir(cwd)
        os.execv(argv[0], argv)
        os._exit(127)
    os.close(rfd)
    os.close(owfd)
    # Feed and drain concurrently: the payload is larger than a pipe
    # buffer and the server answers as it reads, so writing it all
    # before reading deadlocks both ends.
    import threading
    chunks = []

    def drain():
        while True:
            b = os.read(orfd, 65536)
            if not b:
                return
            chunks.append(b)

    t = threading.Thread(target=drain)
    t.start()
    try:
        os.write(wfd, payload)
    except BrokenPipeError:
        pass
    os.close(wfd)
    t.join()
    os.close(orfd)
    _, status, ru = os.wait4(pid, 0)
    # Darwin reports bytes, Linux kilobytes.
    kib = ru.ru_maxrss // 1024 if sys.platform == "darwin" else ru.ru_maxrss
    return b"".join(chunks), status, kib


MEM_SRC = open(os.path.join(fixdir, "060-outline.ax"), encoding="utf-8").read()
mem_uri = "file://" + os.path.join(os.path.abspath(fixdir), "060-outline.ax")


def edit_session(n):
    ms = [{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
          {"jsonrpc": "2.0", "method": "textDocument/didOpen",
           "params": {"textDocument": {"uri": mem_uri, "languageId": "axiom",
                                       "version": 1, "text": MEM_SRC}}}]
    for i in range(n):
        ms.append({"jsonrpc": "2.0", "method": "textDocument/didChange",
                   "params": {"textDocument": {"uri": mem_uri, "version": i + 2},
                              "contentChanges": [{"text": MEM_SRC + "\n; %d\n" % i}]}})
    ms += [{"jsonrpc": "2.0", "id": 2, "method": "shutdown", "params": None},
           {"jsonrpc": "2.0", "method": "exit", "params": None}]
    return b"".join(frame(m) for m in ms)


SMALL, BIG_N = 5, 200
SLOPE_CEILING_KIB = 2048     # over 195 further edits

# THE ABSOLUTE CEILING IS PER-PLATFORM, and it has to be, because the
# same flat session measures 13x apart on the two. Measured 2026-08-31
# on the same tree:
#
#   darwin-aarch64   2,336 KiB at 5 edits, 2,512 KiB at 200
#   linux-aarch64   33,464 KiB at 200        (reproduced under podman)
#   linux-x86_64    33,544 KiB at 200        (CI, run 33424865965)
#
# One ceiling of 32,768 covered both until 0.6.1 crossed it on the two
# Linux legs. It was derived on Darwin, where it sits 13x above the
# measurement and therefore asserts NOTHING - a ceiling nothing can
# reach is the same defect as a check that cannot fail, and it hid the
# fact that the Linux number had never been bounded at all.
#
# THE SLOPE ARM IS THE LEAK CHECK AND IT PASSES ON BOTH. That is what
# says the difference is a working set and not a growth: 176 KiB over
# 195 edits on Darwin, and under the 2,048 KiB ceiling on Linux, where
# the absolute arm is what went red. The gap is the runtime's chunk
# behaviour under glibc against Darwin's, not the server keeping
# anything per edit.
#
# Each is derived from its own platform's measurement with the margin
# stated, rather than rounded up until it passed: Darwin 12,288 is 4.9x
# its 2,512, and Linux 40,960 is 1.22x its 33,544. The Darwin number is
# TIGHTENED here - 2.7x lower than the 32,768 it replaces - because a
# ceiling that only one platform can reach is only half a check.
ABSOLUTE_CEILING_KIB = 12288 if sys.platform == "darwin" else 40960

why = None
rss = {}
for n in (SMALL, BIG_N):
    out, st, kib = run_measured([stage1, "lsp"], edit_session(n), fixdir)
    rss[n] = kib
    msgs, tail = unframe(out)
    pubs = [m for m in msgs if m.get("method") == "textDocument/publishDiagnostics"]
    answered = {m["id"] for m in msgs if "id" in m}
    if st != 0:
        why = f"{n}-edit session exited {st}"
    elif tail:
        why = f"{n}-edit session left {len(tail)} unframed trailing bytes"
    elif len(pubs) != n + 1:
        why = (f"{n}-edit session published {len(pubs)} diagnostics, want {n + 1}"
               " - it did not process every edit, so its memory means nothing")
    elif 2 not in answered:
        why = f"{n}-edit session never answered shutdown"
    if why:
        break

if not why:
    slope = rss[BIG_N] - rss[SMALL]
    if slope > SLOPE_CEILING_KIB:
        why = (f"{rss[SMALL]} KiB at {SMALL} edits, {rss[BIG_N]} KiB at {BIG_N}"
               f" - grew {slope} KiB over {BIG_N - SMALL} edits"
               f" ({slope * 1024 // (BIG_N - SMALL)} bytes per edit),"
               f" ceiling {SLOPE_CEILING_KIB} KiB")
    elif rss[BIG_N] > ABSOLUTE_CEILING_KIB:
        # The slope is in this message even though it PASSED, because
        # without it a reader cannot tell a leak from a working set and
        # has to re-run the gate to find out which one went wrong.
        why = (f"{rss[BIG_N]} KiB at {BIG_N} edits exceeds"
               f" {ABSOLUTE_CEILING_KIB} KiB on {sys.platform}"
               f" (the session is FLAT - {rss[SMALL]} KiB at {SMALL},"
               f" grew {slope} KiB over {BIG_N - SMALL} edits, under the"
               f" {SLOPE_CEILING_KIB} KiB slope ceiling - so this is a"
               f" working set, not a leak)")

if why:
    print(f"FAIL editing-session-is-flat: {why}")
    failed += 1
else:
    print(f"ok   editing-session-is-flat ({rss[SMALL]} KiB at {SMALL} edits, "
          f"{rss[BIG_N]} KiB at {BIG_N}, grew {rss[BIG_N] - rss[SMALL]} KiB, "
          f"under {SLOPE_CEILING_KIB} slope and {ABSOLUTE_CEILING_KIB} absolute "
          f"on {sys.platform}, every edit checked)")
    passed += 1

# =====================================================================
# DIAGNOSTIC FIDELITY: the editor must not be shown less than the
# terminal.
#
# `axiom check --diagnostic-format json` and the language server are two
# renderings of ONE diagnostic. Until 2026-09-03 they disagreed about
# two of its fields. Over the 422 diagnostics in tests/diagnostics/*.json,
# 215 carry a `label` - what the terminal prints at the caret - and 32
# carry `related`, a second span with its own message; `lspDiagJson`
# published neither. `axiom check` on a duplicate `main` points at the
# first definition and names it; VS Code said "duplicate definition
# `main`" and pointed at nothing.
#
# So this block is a DIFFERENTIAL, and the reason it is a legitimate one
# where the deleted stage0 comparison was not: the two sides are
# different code (render.ax's JSON writer against lsp.ax's publisher),
# and the assertion is not "they are equal" but "the editor's side
# contains the terminal's" - a strictly weaker side cannot satisfy it by
# agreeing to say nothing.
#
# It can still be made vacuous from BELOW - if the checker stopped
# producing labels and secondaries, both surfaces would fall silent
# together and every comparison would be two empty lists. That is what
# the two floors are for. They are computed over the WHOLE corpus, not
# over the selection, so `drive.py DIR 010` cannot switch them off, and
# they exit rather than count a failure: a corpus that cannot exercise
# this comparison is not a run whose verdict means anything. Unlike the
# manifest floors they are measured here rather than before the first
# server starts, because they need the checker's own answer for each
# fixture - the whole point is that nothing writes those down.
#
# WHAT IS COMPARED, per fixture:
#   * the same diagnostics in the same order, by code. A server that
#     drops one, or reorders them, fails here as well as against the
#     manifest - and this one notices a drop even for a fixture whose
#     manifest row count happened to match.
#   * every non-empty `label` appears in the published message. The
#     manifest pins the message's FIRST line; the label sits below it,
#     where no row can see it.
#   * `relatedInformation` equals the terminal's `related`, position by
#     position: the uri is the fixture's own, the range is the
#     terminal's CHARACTER offsets converted here to UTF-16 code units
#     (the same `u16` conversion the anchors use, applied to a number
#     the server never sees), and the message is the secondary's own
#     label. "It published something" cannot pass for "it published the
#     right place".
# =====================================================================
def term_diags(path):
    """What `axiom check --diagnostic-format json` says about `path`.
    One JSON object per line, on stderr - the driver writes diagnostics
    there and keeps stdout for output."""
    r = subprocess.run([stage1, "check", "--diagnostic-format", "json", path],
                       capture_output=True, cwd=fixdir)
    out = []
    for line in (r.stdout + r.stderr).decode("utf-8", "replace").splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                out.append(json.loads(line))
            except ValueError:
                pass
    return out


def char_pos(src_text, k):
    """A 0-based CHARACTER offset, as the position LSP asks for. The
    terminal's `char_start`/`char_end` are character offsets; every
    column the server publishes is a UTF-16 code-unit count."""
    ln, text, col = line_of(src_text, k)
    return {"line": ln, "character": u16(text[:col])}


# The floors, over the WHOLE corpus, before any server starts.
corpus_labels, corpus_related = 0, 0
for fx in all_fixtures:
    for d in term_diags(os.path.join(fixdir, fx)):
        if d.get("label"):
            corpus_labels += 1
        corpus_related += len(d.get("related") or [])
if corpus_labels < 5:
    sys.exit(f"FAIL: only {corpus_labels} diagnostic(s) in the whole tests/lsp "
             f"corpus carry a `label`, under a floor of 5 - a comparison over "
             f"that few asserts nearly nothing, and one over none would be two "
             f"empty strings agreeing")
if corpus_related < 1:
    sys.exit("FAIL: no fixture in tests/lsp produces a diagnostic with a "
             "secondary span, so the relatedInformation comparison below "
             "would be two empty lists on every fixture. "
             "090-related-spans.ax exists to be that fixture: restore it, or "
             "add another whose checker output carries `related`.")

dwhy = ""
dlabels = drelated = 0
for fx in fixtures:
    path = os.path.join(fixdir, fx)
    text = open(path, encoding="utf-8").read()
    uri = "file://" + os.path.abspath(path)
    term = term_diags(path)
    msgs, tail = unframe(subprocess.run(
        [stage1, "lsp"], cwd=fixdir, capture_output=True,
        input=b"".join(frame(m) for m in [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
            {"jsonrpc": "2.0", "method": "textDocument/didOpen",
             "params": {"textDocument": {"uri": uri, "languageId": "axiom",
                                         "version": 1, "text": text}}},
            {"jsonrpc": "2.0", "id": 2, "method": "shutdown", "params": None},
            {"jsonrpc": "2.0", "method": "exit", "params": None},
        ])).stdout)
    pub = None
    for m in msgs:
        if m.get("method") == "textDocument/publishDiagnostics":
            pub = m["params"]["diagnostics"]
    if pub is None:
        dwhy = f"{fx}: the server published no diagnostics array at all"
        break
    if [d.get("code") for d in term] != [d.get("code") for d in pub]:
        dwhy = (f"{fx}: the terminal reports {[d.get('code') for d in term]} and "
                f"the editor is published {[d.get('code') for d in pub]}")
        break
    for t, e in zip(term, pub):
        label = t.get("label") or ""
        if label:
            dlabels += 1
            if label not in (e.get("message") or ""):
                dwhy = (f"{fx}: {t.get('code')} - the terminal prints the label "
                        f"{label!r} at the caret and the editor's message does "
                        f"not carry it: {e.get('message')!r}")
                break
        want = [{"location": {"uri": uri,
                              "range": {"start": char_pos(text, r["span"]["char_start"]),
                                        "end": char_pos(text, r["span"]["char_end"])}},
                 "message": r.get("label") or ""}
                for r in (t.get("related") or [])]
        drelated += len(want)
        got = e.get("relatedInformation") or []
        if got != want:
            dwhy = (f"{fx}: {t.get('code')} published {len(got)} related "
                    f"location(s) and the terminal derives {len(want)}: "
                    f"{got!r:.300} against {want!r:.300}")
            break
    if dwhy:
        break

if dwhy:
    print(f"FAIL diagnostic-fidelity: {dwhy}")
    failed += 1
elif dlabels < 1 or drelated < 1:
    # A filtered run may legitimately select a fixture with neither; say
    # so rather than reporting a comparison that did not happen.
    print(f"ok   fidelity   ({len(fixtures)} fixture(s) compared against "
          f"`axiom check --diagnostic-format json`: {dlabels} label(s) and "
          f"{drelated} related location(s) in this selection; the corpus "
          f"carries {corpus_labels} and {corpus_related})")
    passed += 1
else:
    print(f"ok   fidelity   (every diagnostic of every fixture published in the "
          f"terminal's own order, {dlabels} caret label(s) carried into the "
          f"editor's message and {drelated} secondary span(s) published as "
          f"relatedInformation at UTF-16 positions converted here from the "
          f"terminal's character offsets)")
    passed += 1

# ---------------------------------------------------------------------
# Did the derived half actually run? Every check above is skipped by a
# `continue`, and a sweep that skips everything prints nothing but
# "0 failed". These counts are the difference between "no fixture
# disagreed" and "the fixtures were read", and they are EQUALITIES
# against numbers computed from the manifests and the fixture bytes
# before the first server started - too few means a check was skipped,
# too many means one ran twice.
#
# They are reported only when nothing else failed, because a fixture
# that bails takes its assertions with it and a count mismatch is then
# an echo of a failure already printed, not news.
# ---------------------------------------------------------------------
if failed == 0:
    for what, seen, expect in (("position(s) derived from source and asserted",
                                anchored, expect_anchored),
                               ("range(s) checked to spell the name their "
                                "message quotes", named, expect_named),
                               ("symbol name(s) read back out of the source",
                                sym_named, expect_symbols),
                               ("anchor(s) discriminating UTF-16 from bytes "
                                "and characters", len(discriminating),
                                expect_discriminating)):
        if seen != expect:
            print(f"FAIL: {seen} {what}; this run was supposed to make "
                  f"exactly {expect}")
            failed += 1
    if failed == 0:
        print(f"ok   {anchored} derived position(s), {named} name-at-range "
              f"check(s), {sym_named} symbol name(s), discriminating on "
              f"{', '.join(discriminating) or '(nothing in this selection)'}")

print(f"\nlsp: {passed} passed, {failed} failed, "
      f"{len(fixtures)} fixtures + 2 generated")

# A filtered run asserted part of the corpus. Its floors scaled with the
# selection rather than switching off - `drive.py DIR 010` used to skip
# all three - but a partial run must not be able to report success at
# all: the shell forwards `$1` unconditionally, so `check-lsp-selfhost.sh
# anything` would otherwise be a one-fixture sweep that exits 0.
if filt:
    print(f"PARTIAL: filtered to {len(fixtures)} of {len(all_fixtures)} "
          f"fixtures on {filt!r}; exit status is 1 by construction, whatever "
          f"the checks above said. Re-run without a filter for a verdict.")
    sys.exit(1)
sys.exit(1 if failed else 0)
