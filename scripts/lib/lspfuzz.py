#!/usr/bin/env python3
"""Seeded fuzzing of the language server, `axiom lsp`, over JSON-RPC:
the LSP half of R-E1's fuzzing (`scripts/check-fuzz.sh` section 7).

WHAT A SESSION IS. One run of the server, fed a byte stream written up
front: `initialize`, a document opened from the tracked corpus (often
mutated with `fuzz.py`'s edits, deep nesting included, and sometimes
under a URI no editor sends), then up to 64 actions drawn with weights
- a request of every kind the server answers at a random position
(and at positions no editor sends: negative, huge, past the end, the
wrong type), a `didChange` carrying the document with another edit
applied, a second document opened or closed, a frame whose body is not
JSON, a message that is JSON but not JSON-RPC - and then `shutdown`
and `exit`. A tenth of the sessions break the framing itself partway
through, a tenth end without `exit` or without `shutdown`, and a
quarter write every non-ASCII character as a `\\u` escape.

THE ORACLES, held on every session (`judge`):

  signal   the server did not die by a signal;
  hang     it ended within the deadline;
  frame    everything it wrote is `Content-Length: N\\r\\n\\r\\n` and N
           bytes of UTF-8 JSON, back to back, with nothing left over;
  jsonrpc  every message is JSON-RPC 2.0: a response carries the id of
           a request it was sent and exactly one of `result` and
           `error`, an error has an integer `code` and a string
           `message`, a notification a string `method`, and every
           `line` and `character` in a position is a non-negative
           integer (the protocol's `uinteger`);
  answer   every well-formed request sent before any broken frame was
           answered exactly once - including those after a malformed
           message, so a server that stopped answering is caught;
  exit     it exited 0 after `shutdown` and `exit`, and 1 after an
           `exit` or an end of input with no `shutdown` first; after a
           broken frame, 0 or 1.

DETERMINISM, as in `fuzz.py`: splitmix64, mutant I from its own stream,
no set iterated, the corpus sorted by code point. A session names the
tree as `@ROOT@`, which `run` replaces with the repository root, so a
session file (and the digest `gen` prints) is the same on every host,
and a stored reproducer replays anywhere.

A SESSION FILE is JSON Lines, one chunk per line: `{"k": "frame", "t":
body text}` is sent framed, `{"k": "raw", ...}` verbatim, and `"b"`
replaces `"t"` with base64 where the bytes are not UTF-8. `"x"` says
what the oracle expects: `answer` (a request that must be answered),
`maybe` (may be answered: its id or its framing is malformed), `none`
(a notification) or `break` (a broken frame; everything after it is
`maybe`).

Subcommands:

  gen  --seed S --count N --corpus LIST --root ROOT --out DIR
       [--start I] [--max-doc BYTES]
       writes DIR/sNNNNN.lspfuzz and DIR/manifest.tsv, prints
       `digest <hex>`; LIST names corpus files relative to ROOT
  one  --seed S --index I --corpus LIST --root ROOT --out FILE
       session I alone, the reproduce path
  run  --server CMD --root ROOT [--deadline S] [--transcript] FILE...
       runs each session, prints one verdict line per file
  batch --server CMD --root ROOT --dir DIR [--deadline S] [--jobs J]
       runs every session in DIR's manifest; verdict lines, then
       `stats <json>` for the gate's floors
  caps --server CMD
       the capability keys `initialize` advertises that `CAP_METHODS`
       does not know, one per line (the gate fails on any)
  planted --real CMD --mode clean|crash|frame [--after K]
       a wrapper server for the controls: `crash` dies by SIGSEGV
       once it has passed K requests on; `frame` lengthens the
       Content-Length of the server's K-th frame by one
  selftest

LIMITS. The server sees documents from the corpus's neighbourhood and
requests at random positions: a crash that needs a construct no corpus
file comes near, or a position no draw lands on, is not found. The
oracles are protocol-shaped: an answer that is well-formed and wrong
(a definition in the wrong place) passes. Requests are written up
front, so nothing sent depends on what the server answered.
"""
import base64
import concurrent.futures
import hashlib
import json
import os
import re
import shlex
import signal
import subprocess
import sys
import tempfile
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# A server's answer may nest as deep as the document it describes (a
# selection range's parent chain, a folded outline), and `json` recurses
# once per level. Worker threads get a stack to match.
sys.setrecursionlimit(200000)
threading.stack_size(512 * 1024 * 1024)
from fuzz import Rng, mix, Corpus, OPS, read_corpus_list  # noqa: E402

ROOT_MARK = "@ROOT@"
# A session's documents come from corpus files at most this big: a
# `didOpen` checks the whole document and a request re-reads it, so a
# 500 KB compiler module turns a session into a benchmark.
MAX_DOC = 40000

# Every request the server answers, by the capability that advertises
# it. `caps` fails on an advertised key this table does not name, so a
# provider added to `self_host/lsp.ax` and not here is a red gate.
CAP_METHODS = {
    "definitionProvider": ["textDocument/definition"],
    "declarationProvider": ["textDocument/declaration"],
    "typeDefinitionProvider": ["textDocument/typeDefinition"],
    "hoverProvider": ["textDocument/hover"],
    "completionProvider": ["textDocument/completion"],
    "documentSymbolProvider": ["textDocument/documentSymbol"],
    "referencesProvider": ["textDocument/references"],
    "documentHighlightProvider": ["textDocument/documentHighlight"],
    "renameProvider": ["textDocument/prepareRename", "textDocument/rename"],
    "signatureHelpProvider": ["textDocument/signatureHelp"],
    "inlayHintProvider": ["textDocument/inlayHint"],
    "foldingRangeProvider": ["textDocument/foldingRange"],
    "selectionRangeProvider": ["textDocument/selectionRange"],
    "documentLinkProvider": ["textDocument/documentLink"],
    "workspaceSymbolProvider": ["workspace/symbol"],
    "documentFormattingProvider": ["textDocument/formatting"],
    "codeActionProvider": ["textDocument/codeAction"],
    "codeLensProvider": ["textDocument/codeLens"],
    "callHierarchyProvider": ["textDocument/prepareCallHierarchy",
                              "callHierarchy/incomingCalls",
                              "callHierarchy/outgoingCalls"],
    "typeHierarchyProvider": ["textDocument/prepareTypeHierarchy",
                              "typeHierarchy/supertypes",
                              "typeHierarchy/subtypes"],
    "experimental": ["axiom/expandMacro"],
    "textDocumentSync": [],
}
METHODS = [m for k in sorted(CAP_METHODS) for m in CAP_METHODS[k]]
# Methods no capability names: the server must answer each request
# with an error (a notification with nothing).
UNKNOWN = ["textDocument/semanticTokens/full", "workspace/executeCommand",
           "completionItem/resolve", "textDocument/rangeFormatting",
           "$/unknownRequest", "", "initialize/", "textdocument/hover"]
NOTIFICATIONS = ["$/cancelRequest", "$/setTrace", "workspace/didChangeConfiguration",
                 "workspace/didChangeWatchedFiles", "textDocument/didSave",
                 "textDocument/willSave", "window/workDoneProgress/cancel",
                 "$/unknownNotification"]


# ---------------------------------------------------------------------
# Positions: the protocol's line and UTF-16 character, from bytes.

def pos_of(text, off):
    off = max(0, min(off, len(text)))
    head = text[:off]
    line = head.count("\n")
    ls = head.rfind("\n") + 1
    return {"line": line, "character": len(text[ls:off].encode("utf-16-le", "surrogatepass")) // 2}


ODD_NUMBERS = [-1, -2147483648, 2147483647, 2147483648, 4294967295,
               9007199254740993, 9223372036854775807, -9223372036854775808,
               18446744073709551616, 10 ** 30]
ODD_VALUES = [None, True, "3", "", [], {}, 1.5, -0.5, 1e300, -1e-300]


def gen_pos(rng, text):
    """A position: mostly a real one, sometimes one no editor sends."""
    k = rng.below(20)
    if k < 13:
        return pos_of(text, rng.below(len(text) + 1))
    if k == 13:
        return pos_of(text, len(text))
    if k == 14:
        return {"line": text.count("\n") + 1 + rng.below(5), "character": rng.below(3)}
    if k == 15:
        p = pos_of(text, rng.below(len(text) + 1))
        p["character"] += 1 + rng.below(200)
        return p
    if k == 16:
        return {"line": rng.choice(ODD_NUMBERS), "character": rng.choice(ODD_NUMBERS)}
    if k == 17:
        p = pos_of(text, rng.below(len(text) + 1))
        p[rng.choice(["line", "character"])] = rng.choice(ODD_VALUES)
        return p
    if k == 18:
        return {"line": rng.below(text.count("\n") + 1)}
    return rng.choice([None, [], {}, "0:0", 0])


def gen_range(rng, text):
    a, b = gen_pos(rng, text), gen_pos(rng, text)
    if rng.below(8) == 0:
        return rng.choice([None, {}, {"start": a}, [a, b]])
    return {"start": a, "end": b}


def gen_item(rng, uri, text):
    """A call- or type-hierarchy item, which a client hands back from a
    `prepare` it made earlier: a name the document may declare, at a
    range that may not be one."""
    names = ["main", "helper", "f", "x", "vecNew", "", "Option", "Some"]
    r = gen_range(rng, text)
    item = {"name": rng.choice(names), "kind": rng.choice([5, 10, 12, 23, 0, -1, 99]),
            "uri": uri, "range": r, "selectionRange": r}
    if rng.below(6) == 0:
        del item[rng.choice(sorted(item))]
    if rng.below(8) == 0:
        item["data"] = rng.choice([None, 7, "x", {"k": [1]}])
    return item


def gen_params(rng, method, uri, text):
    td = {"uri": uri}
    p = gen_pos(rng, text)
    if method in ("textDocument/documentSymbol", "textDocument/foldingRange",
                  "textDocument/documentLink", "textDocument/codeLens"):
        return {"textDocument": td}
    if method == "workspace/symbol":
        return {"query": rng.choice(["", "vec", "main", "a", "Str", "\u00e9", "(", "x" * 300])}
    if method == "textDocument/references":
        return {"textDocument": td, "position": p,
                "context": {"includeDeclaration": rng.choice([True, False, None, 1])}}
    if method == "textDocument/rename":
        return {"textDocument": td, "position": p,
                "newName": rng.choice(["renamed", "", "a b", "(", "x" * 200, "\u00e9t\u00e9", "1x", "main"])}
    if method == "textDocument/formatting":
        return {"textDocument": td, "options": rng.choice([
            {"tabSize": 2, "insertSpaces": True}, {"tabSize": 0, "insertSpaces": False},
            {"tabSize": -1}, {}, None])}
    if method == "textDocument/codeAction":
        diag = {"range": gen_range(rng, text), "message": "m", "code": rng.choice(["AX3001", "AX2001", 7, None])}
        return {"textDocument": td, "range": gen_range(rng, text),
                "context": {"diagnostics": [diag] if rng.below(2) else []}}
    if method == "textDocument/inlayHint":
        return {"textDocument": td, "range": gen_range(rng, text)}
    if method == "textDocument/selectionRange":
        return {"textDocument": td, "positions": [gen_pos(rng, text) for _ in range(rng.below(4))]}
    if method in ("callHierarchy/incomingCalls", "callHierarchy/outgoingCalls",
                  "typeHierarchy/supertypes", "typeHierarchy/subtypes"):
        return {"item": gen_item(rng, uri, text)}
    return {"textDocument": td, "position": p}


def spoil_params(rng, params):
    """Params a careless client sends: a key missing, the wrong type, or
    no params at all."""
    k = rng.below(5)
    if k == 0:
        return rng.choice([None, [], 7, "params", {}])
    if k == 1 and isinstance(params, dict) and params:
        params = dict(params)
        del params[rng.choice(sorted(params))]
        return params
    if k == 2 and isinstance(params, dict) and "textDocument" in params:
        params = dict(params)
        params["textDocument"] = rng.choice([None, {}, {"uri": 7}, {"uri": ""}, "file:///x",
                                             {"uri": "file:///nonexistent/Nope.ax"},
                                             {"uri": "untitled:Untitled-1"},
                                             {"uri": "file://" + ROOT_MARK + "/%zz%2"}])
        return params
    if k == 3 and isinstance(params, dict):
        params = dict(params)
        params["position"] = rng.choice(ODD_VALUES)
        return params
    return params


# ---------------------------------------------------------------------
# Documents and edits.

def eligible_docs(corpus, max_doc=MAX_DOC):
    """Corpus indices a session may open: at most `max_doc` bytes, and,
    under the default, not the compiler's own modules, which import one
    another and would make every `didOpen` a check of the whole
    compiler. The size is the file's bytes, read from the corpus text so
    the answer is the same on every host."""
    out = []
    for i, p in enumerate(corpus.paths):
        if p.startswith("self_host/") and max_doc <= MAX_DOC:
            continue
        if len(corpus.text(i).encode("utf-8", "surrogateescape")) > max_doc:
            continue
        out.append(i)
    return out


def edit(rng, text, corpus):
    """`text` with one of `fuzz.py`'s mutations applied, or a
    keystroke-sized edit, or a wholesale one."""
    k = rng.below(10)
    if k < 5:
        for _ in range(4):
            name, fn, _w = rng.weighted([(o, o[2]) for o in OPS])
            r = fn(rng, text, corpus)
            if r is not None:
                return r[0]
        return text
    if k < 8:
        at = rng.below(len(text) + 1)
        if rng.below(2) and text:
            n = 1 + rng.below(8)
            return text[:at] + text[at + n:]
        return text[:at] + rng.choice(["(", ")", " ", "x", "\n", "\"", ";", "(fn ", "é", "\U0001F600", "\t"]) + text[at:]
    if k == 8:
        return text[:rng.below(len(text) + 1)]
    return rng.choice(["", "(", ")", "\n\n", "(import", text + text])


# ---------------------------------------------------------------------
# Chunks.

ASCII_ONLY = [False]


def body_bytes(obj):
    # `allow_nan=False`: Python would otherwise write `Infinity`, which
    # is not JSON, into a message the oracle then expects answered.
    # A session drawn ASCII-only writes every non-ASCII character as a
    # `\u` escape, so a raw byte that is not UTF-8 arrives as a lone
    # surrogate escape instead.
    return json.dumps(obj, ensure_ascii=ASCII_ONLY[0], separators=(",", ":"),
                      allow_nan=False).encode("utf-8", "surrogateescape")


def chunk(kind, data, expect):
    try:
        return {"k": kind, "t": data.decode("utf-8"), "x": expect}
    except UnicodeDecodeError:
        return {"k": kind, "b": base64.b64encode(data).decode("ascii"), "x": expect}


def frame_bytes(body):
    return b"Content-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body


BROKEN = [
    ("no Content-Length", lambda rng, b: b"Content-Type: application/vscode-jsonrpc\r\n\r\n" + b),
    ("a length that is not a number", lambda rng, b: b"Content-Length: twelve\r\n\r\n" + b),
    ("a negative length", lambda rng, b: b"Content-Length: -" + str(len(b)).encode() + b"\r\n\r\n" + b),
    ("a length over the framer's ceiling", lambda rng, b: b"Content-Length: 99999999999\r\n\r\n" + b),
    ("a length that wraps", lambda rng, b: b"Content-Length: 18446744073709551621\r\n\r\n" + b),
    ("a length shorter than the body", lambda rng, b: b"Content-Length: " + str(max(0, len(b) - 1 - rng.below(len(b) or 1))).encode() + b"\r\n\r\n" + b),
    ("a header ended by LF LF", lambda rng, b: b"Content-Length: " + str(len(b)).encode() + b"\n\n" + b),
    ("garbage before the header", lambda rng, b: b"\x00\xff garbage \r\n" + frame_bytes(b)),
    ("two lengths that disagree", lambda rng, b: b"Content-Length: " + str(len(b)).encode() + b"\r\nContent-Length: 3\r\n\r\n" + b),
    ("a NUL in the header", lambda rng, b: b"Content-Length:\x00 " + str(len(b)).encode() + b"\r\n\r\n" + b),
    ("an empty header block", lambda rng, b: b"\r\n\r\n" + b),
    ("a truncated body at the end of input", None),
]

# `@ID@` becomes a fresh id, so a lenient parser that reads one of these
# anyway answers an id no other message carries.
MALFORMED_BODIES = [
    b"", b"{", b"}", b"[]", b"null", b"42", b"\"str\"", b"{\"jsonrpc\":\"2.0\",\"id\":",
    b"{\"jsonrpc\":\"2.0\",\"id\":@ID@,\"method\":\"textDocument/hover\",}",
    b"\xff\xfe\x00{}", b"{\"a\":\"\\ud800\"}", b"{\"a\":\"\\u00\"}", b"{\"a\":1e999999}",
    b"{\"a\":-}", b"{'id':@ID@}", b"{\"id\":@ID@ \"method\":\"x\"}", b"\x00" * 16,
    b"{\"jsonrpc\":\"2.0\",\"id\":@ID@,\"method\":\"textDocument/hover\",\"params\":{\"position\":{\"line\":1,\"character\":2}}} trailing",
    b"{\"jsonrpc\":\"2.0\",\"id\":@ID@,\"method\":\"shutdown\"",
]


def deep_json(rng):
    d = rng.choice([100, 1000, 5000, 20000])
    o = rng.choice([("[", "]"), ("{\"a\":", "}")])
    return (o[0] * d + "1" + o[1] * d).encode()


class Session:
    def __init__(self, seed, index, corpus, docs):
        self.rng = Rng(mix(seed ^ 0x4C535046555A5A, index))
        self.corpus = corpus
        self.docs = docs
        self.chunks = []
        self.next_id = 1
        self.open = []          # [uri, text] of documents opened
        self.broken = False
        self.summary = []

    def new_id(self):
        i = self.next_id
        self.next_id += 1
        return i

    def send(self, obj, expect):
        if self.broken and expect == "answer":
            expect = "maybe"
        self.chunks.append(chunk("frame", body_bytes(obj), expect))

    def raw(self, data, expect):
        self.chunks.append(chunk("raw", data, expect))

    def request(self, method, params, expect="answer", rid=None):
        rid = self.new_id() if rid is None else rid
        msg = {"jsonrpc": "2.0", "id": rid, "method": method}
        if params is not None or self.rng.below(2):
            msg["params"] = params
        self.send(msg, expect)

    def notify(self, method, params):
        self.send({"jsonrpc": "2.0", "method": method, "params": params}, "none")

    def pick_doc(self):
        live = [d for d in self.open if d[1] is not None]
        return self.rng.choice(live) if live else None

    def open_doc(self, i, mutate):
        path = self.corpus.paths[i]
        text = self.corpus.text(i)
        if mutate:
            for _ in range(1 + self.rng.below(3)):
                text = edit(self.rng, text, self.corpus)
        uri = "file://" + ROOT_MARK + "/" + path
        k = self.rng.below(24)
        if k == 0:
            uri = "file://" + ROOT_MARK + "/" + path.replace("/", "/./", 1)
        elif k == 1:
            uri = "file://" + ROOT_MARK + "/" + os.path.dirname(path)
        elif k == 2:
            uri = "file://" + ROOT_MARK + "/README.md"
        elif k == 3:
            uri = "file://" + ROOT_MARK + "/" + path.replace("a", "%61", 1).replace(".ax", "%2Eax")
        elif k == 4:
            uri = self.rng.choice(["untitled:Untitled-1", "file:///", "", "file://" + ROOT_MARK + "/no/such/Dir/X.ax",
                                   "file://" + ROOT_MARK + "/stdlib/../" + path, "file://localhost" + ROOT_MARK + "/" + path])
        for d in self.open:
            if d[0] == uri:
                d[1] = text
                break
        else:
            self.open.append([uri, text])
        self.notify("textDocument/didOpen", {"textDocument": {
            "uri": uri, "languageId": "axiom", "version": 1, "text": text}})
        self.summary.append("open " + path + (" (mutated)" if mutate else ""))

    def act(self):
        rng = self.rng
        kind = rng.weighted([("request", 50), ("change", 12), ("incremental", 3),
                             ("open", 3), ("close", 2), ("malformed", 5), ("spoiled", 8),
                             ("badid", 3), ("unknown", 3), ("notify", 3), ("deep", 1)])
        doc = self.pick_doc()
        if doc is None and kind in ("request", "change", "incremental", "close", "spoiled"):
            kind = "open"
        if kind == "open":
            self.open_doc(rng.choice(self.docs), rng.below(2) == 0)
            return
        if kind == "request" or kind == "spoiled":
            uri, text = doc
            if rng.below(20) == 0:
                uri = rng.choice(["file://" + ROOT_MARK + "/stdlib/NotOpen.ax", "file:///", "x"])
            m = rng.choice(METHODS)
            params = gen_params(rng, m, uri, text)
            if kind == "spoiled":
                params = spoil_params(rng, params)
            self.request(m, params)
            self.summary.append(kind + " " + m)
            return
        if kind == "change":
            uri, text = doc
            doc[1] = edit(rng, text, self.corpus)
            self.notify("textDocument/didChange", {
                "textDocument": {"uri": uri, "version": 2 + rng.below(1000)},
                "contentChanges": [{"text": doc[1]}]})
            self.summary.append("change")
            return
        if kind == "incremental":
            # The server syncs FULL documents; a client that sends an
            # incremental change anyway must not bring it down.
            uri, text = doc
            ch = rng.choice([
                {"range": gen_range(rng, text), "text": "x"},
                {"range": gen_range(rng, text)},
                {},
                {"text": 7},
            ])
            changes = rng.choice([[ch], [], [ch, {"text": text}], None, "x"])
            if isinstance(changes, list) and changes and "text" in changes[-1] and isinstance(changes[-1]["text"], str):
                doc[1] = changes[-1]["text"]
            elif isinstance(changes, list) and changes:
                doc[1] = ""
            self.notify("textDocument/didChange", {
                "textDocument": {"uri": uri, "version": 2}, "contentChanges": changes})
            self.summary.append("incremental change")
            return
        if kind == "close":
            uri, _ = doc
            doc[1] = None
            self.notify("textDocument/didClose", {"textDocument": {"uri": uri}})
            self.summary.append("close")
            return
        if kind == "malformed":
            body = rng.choice(MALFORMED_BODIES).replace(b"@ID@", str(self.new_id()).encode())
            self.chunks.append(chunk("frame", body, "maybe"))
            self.summary.append("malformed body")
            return
        if kind == "deep":
            self.chunks.append(chunk("frame", deep_json(rng), "maybe"))
            self.summary.append("deeply nested body")
            return
        if kind == "badid":
            rid = rng.choice([1.5, True, [1], {"a": 1}, None, 2 ** 70, -(2 ** 70), 1e300])
            msg = {"jsonrpc": "2.0", "id": rid, "method": rng.choice(METHODS + ["initialize", "shutdown"][:1]),
                   "params": gen_params(rng, "textDocument/hover", doc[0] if doc else "x", doc[1] if doc else "")}
            if rng.below(3) == 0:
                del msg["jsonrpc"]
            self.send(msg, "maybe")
            self.summary.append("bad id")
            return
        if kind == "unknown":
            if rng.below(2):
                self.request(rng.choice(UNKNOWN), rng.choice([None, {}, {"x": 1}]))
            else:
                # A request with no method, or a method that is not a string.
                rid = self.new_id()
                msg = {"jsonrpc": "2.0", "id": rid}
                if rng.below(2):
                    msg["method"] = rng.choice([7, None, [], {"m": 1}])
                self.send(msg, "answer")
            self.summary.append("unknown method")
            return
        if kind == "notify":
            m = rng.choice(NOTIFICATIONS)
            params = {"id": rng.below(50)} if m == "$/cancelRequest" else rng.choice([None, {}, {"settings": {}}])
            self.notify(m, params)
            self.summary.append("notification " + m)
            return

    def build(self):
        rng = self.rng
        ASCII_ONLY[0] = rng.below(4) == 0
        self.request("initialize", {"processId": None, "rootUri": rng.choice(
            [None, "file://" + ROOT_MARK]), "capabilities": rng.choice([{}, {"textDocument": {}}])})
        self.notify("initialized", {})
        self.open_doc(rng.choice(self.docs), rng.below(10) < 7)
        n = rng.choice([4, 8, 16, 32, 64])
        ending = rng.weighted([("clean", 80), ("break", 10), ("eof", 5), ("noshutdown", 5)])
        break_at = rng.below(n) if ending == "break" else -1
        truncated = False
        for a in range(n):
            if a == break_at:
                what, fn = rng.choice(BROKEN)
                sample = body_bytes({"jsonrpc": "2.0", "id": self.new_id(),
                                     "method": "textDocument/hover", "params": {}})
                if fn is None:
                    # The last thing the client ever sends.
                    self.raw(b"Content-Length: " + str(len(sample) + 50).encode() + b"\r\n\r\n" + sample, "break")
                    self.broken = True
                    truncated = True
                    self.summary.append("broken frame: " + what)
                    break
                self.raw(fn(rng, sample), "break")
                self.broken = True
                self.summary.append("broken frame: " + what)
            self.act()
        if not truncated:
            if ending in ("clean", "break"):
                self.request("shutdown", None)
                self.notify("exit", None)
            elif ending == "noshutdown":
                self.notify("exit", None)
        self.summary.append("end " + ending)
        return self.chunks


def make_session(seed, index, corpus, docs):
    s = Session(seed, index, corpus, docs)
    return s.build(), s.summary


def dump_session(chunks):
    return "".join(json.dumps(c, ensure_ascii=True, sort_keys=True) + "\n" for c in chunks)


def load_session(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(ln) for ln in f if ln.strip()]


def chunk_data(c, root):
    data = c["t"].encode("utf-8") if "t" in c else base64.b64decode(c["b"])
    rootj = json.dumps(root.replace(" ", "%20"))[1:-1].encode("utf-8")
    return data.replace(ROOT_MARK.encode(), rootj)


def session_input(chunks, root):
    out = []
    for c in chunks:
        data = chunk_data(c, root)
        out.append(frame_bytes(data) if c["k"] == "frame" else data)
    return b"".join(out)


# ---------------------------------------------------------------------
# The oracle.

def unframe_strict(out):
    """(messages, why): every frame of `out`, or the first reason it is
    not a well-formed stream."""
    msgs, i, n = [], 0, len(out)
    while i < n:
        j = out.find(b"\r\n\r\n", i)
        if j < 0:
            return msgs, "%d bytes after the last frame are not a header" % (n - i)
        try:
            hdr = out[i:j].decode("ascii")
        except UnicodeDecodeError:
            return msgs, "frame %d's header is not ASCII" % (len(msgs) + 1)
        length = None
        for line in hdr.split("\r\n"):
            name, _, value = line.partition(":")
            if name.strip().lower() == "content-length":
                if not value.strip().isdigit():
                    return msgs, "frame %d's Content-Length is %r" % (len(msgs) + 1, value.strip())
                length = int(value.strip())
            elif name.strip().lower() != "content-type":
                return msgs, "frame %d has a header line %r" % (len(msgs) + 1, line[:60])
        if length is None:
            return msgs, "frame %d has no Content-Length" % (len(msgs) + 1)
        body = out[j + 4:j + 4 + length]
        if len(body) < length:
            return msgs, "frame %d promises %d bytes and %d follow" % (len(msgs) + 1, length, len(body))
        try:
            msgs.append(json.loads(body.decode("utf-8")))
        except (UnicodeDecodeError, ValueError) as e:
            return msgs, "frame %d's body is not UTF-8 JSON (%s): %r" % (len(msgs) + 1, str(e)[:60], body[:80])
        i = j + 4 + length
    return msgs, None


def bad_position(v, path="result"):
    """The first `line`/`character` in `v` that is not a uinteger. An
    explicit stack, since a selection range's parent chain is as deep
    as the document's nesting."""
    stack = [(v, path)]
    while stack:
        v, path = stack.pop()
        if isinstance(v, dict):
            for k in ("line", "character"):
                if k in v and ("start" not in v):
                    x = v[k]
                    if type(x) is not int or x < 0 or x > 2147483647:
                        return "%s.%s is %r" % (path, k, x)
            for k in sorted(v, reverse=True):
                stack.append((v[k], path + "." + k))
        elif isinstance(v, list):
            for i in range(len(v) - 1, -1, -1):
                stack.append((v[i], "%s[%d]" % (path, i)))
    return None


def id_key(v):
    return json.dumps(v, sort_keys=True)


ID_RE = re.compile(rb'"id"\s*:\s*(-?[0-9][0-9.eE+-]*|"(?:[^"\\]|\\.)*"|true|false|null|\{[^{}]*\}|\[[^\[\]]*\])')


def id_key_text(raw):
    """The key of an id written as JSON text, or its text when it does
    not parse on its own."""
    try:
        return id_key(json.loads(raw.decode("utf-8")))
    except (UnicodeDecodeError, ValueError):
        return raw.decode("utf-8", "replace")


def expectations(chunks, root):
    """What the session obliges the server to do: the ids that must be
    answered, how many answers each other id may have, and the exit
    statuses allowed. An id is read out of a malformed message or a
    broken frame too, since a lenient reader may still answer it."""
    must, may, order = {}, {}, []
    shutdown = broken = False
    exited = False
    for c in chunks:
        x = c["x"]
        if x == "break":
            broken = True
            for m in ID_RE.finditer(chunk_data(c, root)):
                k = id_key_text(m.group(1))
                may[k] = may.get(k, 0) + 1
            continue
        if exited:
            continue
        data = chunk_data(c, root)
        try:
            msg = json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            msg = None
        if not isinstance(msg, dict):
            for m in ID_RE.finditer(data):
                k = id_key_text(m.group(1))
                may[k] = may.get(k, 0) + 1
            continue
        if "id" in msg:
            k = id_key(msg["id"])
            if x == "answer" and not broken:
                meth = msg.get("method")
                must[k] = meth if isinstance(meth, str) else repr(meth)
                order.append(k)
            else:
                may[k] = may.get(k, 0) + 1
        if msg.get("method") == "shutdown" and x == "answer" and not broken:
            shutdown = True
        if msg.get("method") == "exit" and x == "none" and not broken:
            exited = True
    if broken:
        statuses = (0, 1)
    else:
        statuses = (0,) if shutdown else (1,)
    return must, may, statuses, order


def judge(chunks, root, rc, timed_out, out, deadline):
    """(verdict, stage, why, stats): verdict `ok` or `fail`."""
    must, may, statuses, _ = expectations(chunks, root)
    stats = {"requests": len(must), "answered": 0, "results": 0, "nonnull": 0,
             "errors": 0, "notifications": 0, "methods": {}}
    if timed_out:
        return "fail", "hang", "no end within %ds" % deadline, stats
    if rc < 0:
        try:
            name = signal.Signals(-rc).name
        except ValueError:
            name = "?"
        return "fail", "signal", "killed by signal %d (%s)" % (-rc, name), stats
    msgs, why = unframe_strict(out)
    if why:
        return "fail", "frame", why, stats
    seen = {}
    for n, m in enumerate(msgs, 1):
        if not isinstance(m, dict) or m.get("jsonrpc") != "2.0":
            return "fail", "jsonrpc", "message %d is not a JSON-RPC 2.0 object: %.80r" % (n, m), stats
        if "method" in m:
            if not isinstance(m["method"], str):
                return "fail", "jsonrpc", "message %d's method is %r" % (n, m["method"]), stats
            if "id" in m:
                return "fail", "jsonrpc", "message %d is a request to the client (%s), which a batch session cannot answer" % (n, m["method"]), stats
            stats["notifications"] += 1
            r = bad_position(m.get("params"), "params")
            if r:
                return "fail", "jsonrpc", "notification %s: %s" % (m["method"], r), stats
            continue
        if "id" not in m:
            return "fail", "jsonrpc", "message %d has neither a method nor an id" % n, stats
        k = id_key(m["id"])
        if ("result" in m) == ("error" in m):
            return "fail", "jsonrpc", "the answer to id %s has %s" % (k, "both result and error" if "result" in m else "neither result nor error"), stats
        seen[k] = seen.get(k, 0) + 1
        if k not in must and k not in may:
            return "fail", "answer", "an answer to id %s, which no request carried" % k, stats
        if seen[k] > (k in must) + may.get(k, 0):
            return "fail", "answer", "id %s was answered %d times and sent %d" % (
                k, seen[k], (k in must) + may.get(k, 0)), stats
        if "error" in m:
            e = m["error"]
            if not (isinstance(e, dict) and type(e.get("code")) is int and isinstance(e.get("message"), str)):
                return "fail", "jsonrpc", "the error answering id %s is %.80r" % (k, e), stats
            stats["errors"] += 1
        else:
            r = bad_position(m["result"])
            if r:
                return "fail", "jsonrpc", "the answer to id %s (%s): %s" % (k, must.get(k, "?"), r), stats
            stats["results"] += 1
            if m["result"] not in (None, [], {}):
                stats["nonnull"] += 1
        if k in must:
            stats["answered"] += 1
            meth = must[k] or "-"
            stats["methods"][meth] = stats["methods"].get(meth, 0) + 1
    missing = [k for k in must if k not in seen]
    if missing:
        return "fail", "answer", "%d request(s) never answered, the first id %s (%s)" % (
            len(missing), missing[0], must[missing[0]]), stats
    if rc not in statuses:
        return "fail", "exit", "exited %d where the session allows %s" % (rc, "/".join(map(str, statuses))), stats
    return "ok", "", "", stats


def run_one(server, chunks, root, deadline):
    """Run one session: (rc, timed_out, stdout, stderr)."""
    data = session_input(chunks, root)
    with tempfile.TemporaryDirectory() as cwd:
        p = subprocess.Popen(server, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, cwd=cwd, start_new_session=True)
        try:
            out, err = p.communicate(data, timeout=deadline)
            return p.returncode, False, out, err
        except subprocess.TimeoutExpired:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                p.kill()
            out, err = p.communicate()
            return p.returncode, True, out, err


def verdict_line(name, v, stage, why):
    return "%s\t%s\t%s\t%s" % (name, v, stage, why.replace("\t", " ").replace("\n", " "))


# ---------------------------------------------------------------------
# Subcommands.

def parse_args(argv):
    args, pos, i = {}, [], 0
    flags = {"--transcript"}
    while i < len(argv):
        a = argv[i]
        if a in flags:
            args[a] = True
            i += 1
        elif a.startswith("--"):
            args[a] = argv[i + 1]
            i += 2
        else:
            pos.append(a)
            i += 1
    return args, pos


def load_corpus(args):
    corpus = read_corpus_list(args["--corpus"], args.get("--root", "."))
    docs = eligible_docs(corpus, int(args.get("--max-doc", str(MAX_DOC))))
    if not docs:
        raise SystemExit("no corpus file is small enough to open")
    return corpus, docs


def cmd_gen(args):
    corpus, docs = load_corpus(args)
    seed, count = int(args["--seed"]), int(args["--count"])
    start = int(args.get("--start", "0"))
    out = args["--out"]
    os.makedirs(out, exist_ok=True)
    h = hashlib.sha256()
    rows = []
    for i in range(start, start + count):
        name = "s%05d" % i
        chunks, summary = make_session(seed, i, corpus, docs)
        text = dump_session(chunks)
        with open(os.path.join(out, name + ".lspfuzz"), "w", encoding="utf-8") as f:
            f.write(text)
        row = "%s\t%s" % (name, " | ".join(summary[:1] + ["%d chunks" % len(chunks)] + summary[-1:]))
        rows.append(row)
        h.update(row.encode("utf-8") + b"\n")
        h.update(hashlib.sha256(text.encode("utf-8")).digest())
    with open(os.path.join(out, "manifest.tsv"), "w", encoding="utf-8") as f:
        f.write("\n".join(rows) + "\n")
    print("digest %s sessions %d docs %d" % (h.hexdigest(), count, len(docs)))
    return 0


def cmd_one(args):
    corpus, docs = load_corpus(args)
    chunks, summary = make_session(int(args["--seed"]), int(args["--index"]), corpus, docs)
    with open(args["--out"], "w", encoding="utf-8") as f:
        f.write(dump_session(chunks))
    print("s%05d\t%s" % (int(args["--index"]), " | ".join(summary)))
    return 0


def run_and_judge(server, path, root, deadline):
    chunks = load_session(path)
    t0 = time.monotonic()
    rc, to, out, err = run_one(server, chunks, root, deadline)
    secs = time.monotonic() - t0
    v, stage, why, stats = judge(chunks, root, rc, to, out, deadline)
    stats["secs"] = round(secs, 3)
    return v, stage, why, stats, (rc, out, err)


def cmd_run(args, pos):
    server = shlex.split(args["--server"])
    root = args["--root"]
    deadline = int(args.get("--deadline", "60"))
    bad = 0
    for path in pos:
        v, stage, why, stats, (rc, out, err) = run_and_judge(server, path, root, deadline)
        print(verdict_line(os.path.basename(path), v, stage, why))
        if args.get("--transcript"):
            print("  exit %d, %d bytes out, stderr: %r" % (rc, len(out), err[-400:]))
            for c in load_session(path):
                d = chunk_data(c, root)
                print("  >> %s %s %r" % (c["k"], c["x"], d[:160]))
            msgs, why2 = unframe_strict(out)
            for m in msgs:
                print("  << %s" % json.dumps(m)[:200])
            if why2:
                print("  << (%s)" % why2)
        bad += v != "ok"
    return 1 if bad else 0


def cmd_batch(args):
    server = shlex.split(args["--server"])
    root = args["--root"]
    deadline = int(args.get("--deadline", "60"))
    jobs = int(args.get("--jobs", "4"))
    d = args["--dir"]
    with open(os.path.join(d, "manifest.tsv"), encoding="utf-8") as f:
        names = [ln.split("\t")[0] for ln in f if ln.strip()]
    total = {"sessions": 0, "requests": 0, "answered": 0, "results": 0, "nonnull": 0,
             "errors": 0, "notifications": 0, "methods": {}, "failed": 0, "clean": 0,
             "breaks": 0, "changes": 0, "malformed": 0, "spoiled": 0}

    def one(name):
        return name, run_and_judge(server, os.path.join(d, name + ".lspfuzz"), root, deadline)

    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as ex:
        results = list(ex.map(one, names))
    slowest = (0.0, "")
    for name, (v, stage, why, stats, _) in results:
        print(verdict_line(name, v, stage, why))
        if stats.get("secs", 0) > slowest[0]:
            slowest = (stats["secs"], name)
        total["sessions"] += 1
        total["failed"] += v != "ok"
        for k in ("requests", "answered", "results", "nonnull", "errors", "notifications"):
            total[k] += stats[k]
        for m, c in stats["methods"].items():
            total["methods"][m] = total["methods"].get(m, 0) + c
        chunks = load_session(os.path.join(d, name + ".lspfuzz"))
        total["breaks"] += any(c["x"] == "break" for c in chunks)
        total["clean"] += v == "ok" and not any(c["x"] == "break" for c in chunks) and \
            expectations(chunks, root)[2] == (0,)
        for c in chunks:
            t = chunk_data(c, root)
            if b'"textDocument/didChange"' in t:
                total["changes"] += 1
            if c["x"] == "maybe":
                total["malformed"] += 1
    total["slowest"] = "%s %.2fs" % (slowest[1], slowest[0])
    print("stats " + json.dumps(total, sort_keys=True))
    return 0


def cmd_caps(args):
    server = shlex.split(args["--server"])
    msgs = [frame_bytes(body_bytes(m)) for m in (
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "rootUri": None, "capabilities": {}}},
        {"jsonrpc": "2.0", "id": 2, "method": "shutdown"},
        {"jsonrpc": "2.0", "method": "exit"})]
    p = subprocess.run(server, input=b"".join(msgs), capture_output=True, timeout=120)
    got, why = unframe_strict(p.stdout)
    if why:
        print("the initialize session's output is malformed: " + why)
        return 1
    caps = [m for m in got if m.get("id") == 1][0]["result"]["capabilities"]
    unknown = [k for k in sorted(caps) if caps[k] not in (None, False) and k not in CAP_METHODS]
    for k in unknown:
        print(k)
    advertised = [k for k in sorted(caps) if caps[k] not in (None, False)]
    print("advertised %d" % len(advertised), file=sys.stderr)
    return 1 if unknown else 0


def read_frames(stream, on_frame, on_raw):
    """Read `stream` frame by frame, calling `on_frame(header, body)`;
    bytes that do not frame go to `on_raw` once, with the rest."""
    buf = b""
    while True:
        j = buf.find(b"\r\n\r\n")
        while j < 0:
            more = stream.read1(65536) if hasattr(stream, "read1") else stream.read(65536)
            if not more:
                if buf:
                    on_raw(buf)
                return
            buf += more
            j = buf.find(b"\r\n\r\n")
        hdr = buf[:j]
        length = None
        for line in hdr.split(b"\r\n"):
            if line.lower().startswith(b"content-length:"):
                v = line.split(b":", 1)[1].strip()
                length = int(v) if v.isdigit() else None
        if length is None:
            on_raw(buf)
            while True:
                more = stream.read1(65536) if hasattr(stream, "read1") else stream.read(65536)
                if not more:
                    return
                on_raw(more)
        while len(buf) < j + 4 + length:
            more = stream.read1(65536) if hasattr(stream, "read1") else stream.read(65536)
            if not more:
                on_raw(buf)
                return
            buf += more
        on_frame(hdr, buf[j + 4:j + 4 + length])
        buf = buf[j + 4 + length:]


def cmd_planted(args):
    """A wrapper server. `clean` passes everything through; `crash`
    dies by SIGSEGV once it has passed K requests to the real server
    and seen their answers; `frame` lengthens the Content-Length of
    the server's K-th frame by one."""
    real = shlex.split(args["--real"])
    mode = args["--mode"]
    after = int(args.get("--after", "2"))
    p = subprocess.Popen(real, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    out = sys.stdout.buffer
    lock = threading.Lock()
    state = {"requests": 0, "frames": 0, "answers": 0}

    def die():
        try:
            p.kill()
        except OSError:
            pass
        out.flush()
        os.kill(os.getpid(), signal.SIGSEGV)

    def pump_in():
        def on_frame(hdr, body):
            try:
                msg = json.loads(body)
            except ValueError:
                msg = None
            if isinstance(msg, dict) and "id" in msg and "method" in msg:
                with lock:
                    state["requests"] += 1
            p.stdin.write(hdr + b"\r\n\r\n" + body)
            p.stdin.flush()

        def on_raw(data):
            p.stdin.write(data)
            p.stdin.flush()
        try:
            read_frames(sys.stdin.buffer, on_frame, on_raw)
            p.stdin.close()
        except (BrokenPipeError, OSError):
            pass

    t = threading.Thread(target=pump_in, daemon=True)
    t.start()

    def on_out(hdr, body):
        state["frames"] += 1
        try:
            msg = json.loads(body)
        except ValueError:
            msg = None
        if mode == "frame" and state["frames"] == after:
            out.write(b"Content-Length: " + str(len(body) + 1).encode() + b"\r\n\r\n" + body)
        else:
            out.write(hdr + b"\r\n\r\n" + body)
        out.flush()
        if isinstance(msg, dict) and "id" in msg and "method" not in msg:
            state["answers"] += 1
            if mode == "crash" and state["answers"] >= after:
                die()

    def on_out_raw(data):
        out.write(data)
        out.flush()

    read_frames(p.stdout, on_out, on_out_raw)
    rc = p.wait()
    out.flush()
    return rc if rc >= 0 else 128 - rc


# ---------------------------------------------------------------------
# The selftest: the oracle on outputs made by hand, each of which it
# must accept or refuse, and the generator's own determinism.

PINNED_CORPUS = {
    "a.ax": '(import IO)\n\n(:: main Int)\n;@axiom:effect(io)\n(fn (main)\n'
            '  {\n    (println "h\u00e9 \\n")\n    (let ((x 42)) x)\n  })\n',
    "b.ax": '(data Shape (Circle Int) (Sq Int))\n(:: area (-> Shape Int))\n'
            '(fn (area s)\n  (match s\n    ((Circle r) (* 3 (* r r)))\n    ((Sq w) (* w w))))\n',
}
PINNED_DIGEST = "a67838039f92c4b0f4d63015c41ebaeb68bc70175c8007faf1eb6cdf3c32b79c"


def pinned_digest():
    corpus = Corpus(".", list(PINNED_CORPUS), PINNED_CORPUS)
    docs = list(range(len(corpus.paths)))
    h = hashlib.sha256()
    for i in range(60):
        chunks, summary = make_session(1, i, corpus, docs)
        h.update(dump_session(chunks).encode("utf-8"))
    return h.hexdigest()


def fr(obj):
    return frame_bytes(json.dumps(obj).encode())


def cmd_selftest():
    d = pinned_digest()
    if d != PINNED_DIGEST:
        print("the generator's output for the pinned corpus moved: %s, pinned %s" % (d, PINNED_DIGEST))
        print("(a deliberate change to the sessions updates PINNED_DIGEST; anything else is a determinism defect)")
        return 1
    root = "/r"
    sess = [chunk("frame", body_bytes({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}), "answer"),
            chunk("frame", body_bytes({"jsonrpc": "2.0", "id": 2, "method": "textDocument/hover", "params": {}}), "answer"),
            chunk("frame", b"{", "maybe"),
            chunk("frame", body_bytes({"jsonrpc": "2.0", "id": 3, "method": "shutdown"}), "answer"),
            chunk("frame", body_bytes({"jsonrpc": "2.0", "method": "exit"}), "none")]
    a1 = {"jsonrpc": "2.0", "id": 1, "result": {"capabilities": {}}}
    a2 = {"jsonrpc": "2.0", "id": 2, "result": {"range": {"start": {"line": 0, "character": 1}, "end": {"line": 0, "character": 2}}}}
    a3 = {"jsonrpc": "2.0", "id": 3, "result": None}
    note = {"jsonrpc": "2.0", "method": "textDocument/publishDiagnostics", "params": {"uri": "u", "diagnostics": []}}
    good = fr(a1) + fr(note) + fr(a2) + fr(a3)
    cases = [
        ("a good session", 0, False, good, "ok"),
        ("answers out of order", 0, False, fr(a3) + fr(a2) + fr(a1), "ok"),
        ("a signal", -11, False, good, "signal"),
        ("a hang", -9, True, good, "hang"),
        ("a missing answer", 0, False, fr(a1) + fr(a3), "answer"),
        ("an answer twice", 0, False, good + fr(a2), "answer"),
        ("an answer to no request", 0, False, good + fr({"jsonrpc": "2.0", "id": 9, "result": None}), "answer"),
        ("a Content-Length longer than its body", 0, False, fr(a1) + b"Content-Length: 99\r\n\r\n{}", "frame"),
        ("a body that is not JSON", 0, False, good + b"Content-Length: 2\r\n\r\n{x", "frame"),
        ("trailing bytes", 0, False, good + b"junk", "frame"),
        ("no jsonrpc member", 0, False, fr({"id": 1, "result": None}) + fr(a2) + fr(a3), "jsonrpc"),
        ("both result and error", 0, False, fr(dict(a1, error={"code": 1, "message": "m"})) + fr(a2) + fr(a3), "jsonrpc"),
        ("an error without a code", 0, False, fr({"jsonrpc": "2.0", "id": 1, "error": {"message": "m"}}) + fr(a2) + fr(a3), "jsonrpc"),
        ("a negative character", 0, False, fr(a1) + fr({"jsonrpc": "2.0", "id": 2, "result": {"line": 0, "character": -1}}) + fr(a3), "jsonrpc"),
        ("exit 1 after shutdown", 1, False, good, "exit"),
    ]
    for what, rc, to, out, want in cases:
        v, stage, why, _ = judge(sess, root, rc, to, out, 5)
        got = "ok" if v == "ok" else stage
        if got != want:
            print("the oracle judged %s as %r (%s), wanted %r" % (what, got, why, want))
            return 1
    # A session with a broken frame allows 0 or 1 and relaxes what follows.
    brk = sess[:2] + [chunk("raw", b"Content-Length: x\r\n\r\n{}", "break")] + sess[3:]
    for rc in (0, 1):
        v, stage, why, _ = judge(brk, root, rc, False, fr(a1) + fr(a2), 5)
        if v != "ok":
            print("the oracle refused a stop after a broken frame (exit %d): %s" % (rc, why))
            return 1
    v, stage, why, _ = judge(brk, root, 0, False, fr(a1), 5)
    if stage != "answer":
        print("the oracle excused a request before the broken frame going unanswered")
        return 1
    # Framing round trip, and @ROOT@ substitution keeps lengths right.
    c = chunk("frame", b'{"uri":"file://@ROOT@/a b"}', "none")
    data = session_input([c], "/x y")
    msgs, why = unframe_strict(data)
    if why or msgs != [{"uri": "file:///x%20y/a b"}]:
        print("the framer did not round-trip a substituted root: %r %s" % (msgs, why))
        return 1
    print("selftest: the pinned-corpus digest %s..., the oracle on %d hand-made outputs "
          "and a broken-frame session, and the framer" % (d[:12], len(cases)))
    return 0


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    cmd, rest = argv[0], argv[1:]
    args, pos = parse_args(rest)
    if cmd == "gen":
        return cmd_gen(args)
    if cmd == "one":
        return cmd_one(args)
    if cmd == "run":
        return cmd_run(args, pos)
    if cmd == "batch":
        return cmd_batch(args)
    if cmd == "caps":
        return cmd_caps(args)
    if cmd == "planted":
        return cmd_planted(args)
    if cmd == "selftest":
        return cmd_selftest()
    print("unknown subcommand %r" % cmd, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
