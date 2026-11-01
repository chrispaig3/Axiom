#!/usr/bin/env python3
"""Check memory-boundary guidance against compiler facts and source ranges.

Run directly with a compiler path, or through drive.py. Nothing is blessed:
the source determines the checked types, ownership-erasure counts and ranges.
"""
import json
from pathlib import Path
import subprocess
import runpy
import sys
import tempfile


def frame(message):
    body = json.dumps(message).encode()
    return b"Content-Length: %d\r\n\r\n" % len(body) + body


def unframe(stream):
    messages = []
    while stream:
        header, separator, stream = stream.partition(b"\r\n\r\n")
        assert separator, "incomplete LSP header"
        lengths = [line.split(b":", 1)[1] for line in header.split(b"\r\n")
                   if line.lower().startswith(b"content-length:")]
        assert len(lengths) == 1, "missing or repeated Content-Length"
        length = int(lengths[0])
        assert len(stream) >= length, "incomplete LSP body"
        messages.append(json.loads(stream[:length]))
        stream = stream[length:]
    return messages


def position(source, offset):
    prefix = source[:offset]
    return {"line": prefix.count("\n"),
            "character": len(prefix.rsplit("\n", 1)[-1].encode("utf-16-le")) // 2}


def source_range(source, needle, start=0):
    offset = source.index(needle, start)
    return {"start": position(source, offset),
            "end": position(source, offset + len(needle))}


def terminal(compiler, path):
    result = subprocess.run([compiler, "--diagnostic-format=json", "check", str(path)],
                            capture_output=True, timeout=60)
    diagnostics = [json.loads(line) for line in result.stderr.splitlines()
                   if line.startswith(b"{")]
    assert result.returncode == bool([d for d in diagnostics
                                     if d["severity"] == "error"]), result.stderr.decode()
    return diagnostics


def editor(compiler, path, source, words=()):
    uri = path.as_uri()
    requests = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
        {"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {
            "textDocument": {"uri": uri, "languageId": "axiom",
                             "version": 1, "text": source}}},
    ]
    for index, (word, offset) in enumerate(words, 2):
        requests.append({"jsonrpc": "2.0", "id": index,
                         "method": "textDocument/hover", "params": {
                             "textDocument": {"uri": uri},
                             "position": position(source, offset)}})
    requests.extend([
        {"jsonrpc": "2.0", "id": 100, "method": "shutdown", "params": None},
        {"jsonrpc": "2.0", "method": "exit", "params": None},
    ])
    session = runpy.run_path(str(Path(__file__).with_name("workspace-overlays.py")))["run_session"]
    result = session(compiler, b"".join(map(frame, requests)), cwd=path.parent, timeout=60)
    assert result.returncode == 0 and not result.stderr, result.stderr.decode()
    messages = unframe(result.stdout)
    assert not [message for message in messages if "error" in message], messages
    answers = {message["id"]: message.get("result") for message in messages
               if "id" in message}
    assert 100 in answers, "server did not answer shutdown"
    publications = [message["params"]["diagnostics"] for message in messages
                    if message.get("method") == "textDocument/publishDiagnostics"]
    assert len(publications) == 1, "expected one checked document publication"
    return [d for d in publications[0] if d["severity"] != 4], answers


def run(compiler):
    compiler = str(Path(compiler).resolve())
    with tempfile.TemporaryDirectory(prefix="axiom-memory-boundaries-") as directory:
        root = Path(directory)
        source = """(struct Packet (text : String))
(type Message Packet)
(:: readRaw (-> Int String))
(fn (readRaw address)
  { (let item (as address Message))
    item.text})
"""
        path = root / "Forge.ax"
        path.write_text(source)
        diagnostics = terminal(compiler, path)
        assert [d["code"] for d in diagnostics] == ["AX3073"], diagnostics
        checked = diagnostics[0]
        # The forging check reports the target resolved in its declaring scope.
        assert "`Packet` out of `Int`" in checked["message"], checked
        assert len(checked["related"]) == 1, checked
        conversion = source.index("(as address Message)")
        value_start = source.index("address", conversion)
        related = checked["related"][0]
        assert related["span"]["char_start"] == value_start, related
        assert related["span"]["char_end"] == value_start + len("address"), related
        assert "source has type `Int`" in related["label"], related
        guidance = " ".join(checked["help"])
        for obligation in ("constructor", "layout and validity", "backing owner alive",
                           "does not extend a region's scope", "every well-typed call safe",
                           "type, effect and restriction checks"):
            assert obligation in guidance, (obligation, checked)
        published, answers = editor(compiler, path, source, [("as", conversion + 1)])
        assert [d["code"] for d in published] == ["AX3073"], published
        for help_text in checked["help"]:
            assert help_text in published[0]["message"], published
        assert published[0]["relatedInformation"] == [{
            "location": {"uri": path.as_uri(),
                         "range": source_range(source, "address", conversion)},
            "message": related["label"]}], published
        explain = subprocess.run([compiler, "explain", "as"], capture_output=True,
                                 check=True, timeout=60).stdout.decode().strip()
        hover = answers[2]["contents"]["value"]
        assert explain in hover, "CLI language help and editor hover differ"
        for fact in ("keeps no ownership share", "keep the owner alive", "addrOf",
                     "effect(unsafe)", "never extends a region's scope"):
            assert fact in hover, (fact, hover)

        # An untagged reference-to-word cast is AX3073. The same cast under
        # effect(unsafe) stays quiet, keeps the erasure count, and is trusted.
        # Ascriptions and numeric conversions erase nothing.
        source = """(:: word (-> String Int))
(fn (word owner) (as owner Int))
(:: same (-> String String))
(fn (same owner) (as owner String))
(:: typed (-> String String))
(fn (typed owner) (:: owner String))
(:: numeric (-> Int Float))
(fn (numeric n) (as n Float))
"""
        path = root / "Managed.ax"
        path.write_text(source)
        refused = terminal(compiler, path)
        assert [d["code"] for d in refused] == ["AX3073"], refused
        assert "erases `String` into `Int`" in refused[0]["message"], refused
        tagged = """(:: word (-> String Int))
;@axiom:effect(unsafe)
(fn (word owner) (as owner Int))
(:: same (-> String String))
(fn (same owner) (as owner String))
(:: typed (-> String String))
(fn (typed owner) (:: owner String))
(:: numeric (-> Int Float))
(fn (numeric n) (as n Float))
"""
        path.write_text(tagged)
        assert terminal(compiler, path) == [], "a declared erasure was refused"
        published, _ = editor(compiler, path, tagged)
        assert published == [], published
        symbols = subprocess.run([compiler, "--diagnostic-format=ai", "symbols", str(path)],
                                 capture_output=True, check=True, timeout=60).stdout.decode()
        rows = {line.split()[1]: line for line in symbols.splitlines()
                if line.startswith("F ")}
        assert "#erasures=1" in rows["word"] and "#unsafe=trusted" in rows["word"], rows
        for name in ("same", "typed", "numeric"):
            assert "#erasures=" not in rows[name], rows[name]

        # Alloc and Mut are real, checked claims, despite being optional on
        # ordinary functions. Their lexicon entries must describe that contract.
        source = """(struct Counter (mut value : Int))
(:: update (-> Counter Int))
;@axiom:effect(mut)
(fn (update counter) { (set counter.value 1) counter.value })
(:: scoped Int)
;@axiom:effect(alloc)
(fn (scoped) (region scratch 0))
"""
        path = root / "Effects.ax"
        path.write_text(source)
        assert terminal(compiler, path) == [], "valid memory-effect claims refused"
        for word, claim in (("Alloc", "effect(alloc)"), ("Mut", "effect(mut)")):
            help_text = subprocess.run([compiler, "explain", word], capture_output=True,
                                       check=True, timeout=60).stdout.decode()
            assert claim in help_text and "need not declare" in help_text, help_text
        path.write_text("(:: plain Int)\n;@axiom:effect(alloc)\n(fn (plain) 0)\n")
        assert [d["code"] for d in terminal(compiler, path)] == ["AX3010"], (
            "a false allocation claim must remain an error")
    print("ok   memory-boundaries (checked forging types and operand spans, shared terminal/editor guidance, ownership erasures, quiet safe conversions and checked memory effects)")


if __name__ == "__main__":
    try:
        run(sys.argv[1])
    except (AssertionError, subprocess.SubprocessError) as error:
        sys.exit("FAIL memory-boundaries: " + str(error))
