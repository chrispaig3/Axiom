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
import subprocess
import sys

stage1, fixdir = sys.argv[1], sys.argv[2]
rest = sys.argv[3:]
bless = "--bless" in rest
filt = next((a for a in rest if not a.startswith("--")), "")

DOC_URI = "file:///DOC.ax"
MANIFEST = os.path.join(fixdir, "expected-diagnostics.txt")
OUTLINE = os.path.join(fixdir, "expected-outline.txt")

FIXTURE_FLOOR = 8
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
ABSOLUTE_CEILING_KIB = 32768

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
        why = f"{rss[BIG_N]} KiB at {BIG_N} edits exceeds {ABSOLUTE_CEILING_KIB} KiB"

if why:
    print(f"FAIL editing-session-is-flat: {why}")
    failed += 1
else:
    print(f"ok   editing-session-is-flat ({rss[SMALL]} KiB at {SMALL} edits, "
          f"{rss[BIG_N]} KiB at {BIG_N}, every edit checked)")
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
