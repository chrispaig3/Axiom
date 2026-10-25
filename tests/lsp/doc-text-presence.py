#!/usr/bin/env python3
"""Pin responses for an unknown URI and an open empty document."""

import json
from pathlib import Path
import runpy
import sys
import tempfile


Client = runpy.run_path(str(Path(__file__).with_name("workspace-overlays.py")))["Client"]


def requests(uri):
    document = {"textDocument": {"uri": uri}}
    point = {**document, "position": {"line": 0, "character": 0}}
    region = {"start": {"line": 0, "character": 0},
              "end": {"line": 0, "character": 0}}
    return [
        ("textDocument/documentSymbol", document),
        ("textDocument/definition", point),
        ("textDocument/hover", point),
        ("textDocument/completion", point),
        ("textDocument/references", {**point, "context": {"includeDeclaration": True}}),
        ("textDocument/documentHighlight", point),
        ("textDocument/prepareRename", point),
        ("textDocument/rename", {**point, "newName": "next"}),
        ("textDocument/declaration", point),
        ("textDocument/prepareCallHierarchy", point),
        ("textDocument/prepareTypeHierarchy", point),
        ("textDocument/signatureHelp", point),
        ("textDocument/inlayHint", {**document, "range": region}),
        ("textDocument/foldingRange", document),
        ("textDocument/selectionRange", {**document, "positions": [point["position"]]}),
        ("textDocument/documentLink", document),
        ("textDocument/formatting", {**document, "options": {"tabSize": 2, "insertSpaces": True}}),
        ("textDocument/codeAction", {**document, "range": region, "context": {"diagnostics": []}}),
        ("textDocument/typeDefinition", point),
        ("textDocument/codeLens", document),
        ("axiom/expandMacro", point),
        ("textDocument/semanticTokens/full", document),
        ("textDocument/semanticTokens/range", {**document, "range": region}),
        ("callHierarchy/incomingCalls", {"item": {"uri": uri, "name": "f"}}),
        ("typeHierarchy/supertypes", {"item": {"uri": uri, "name": "T"}}),
    ]


def probe(compiler):
    with tempfile.TemporaryDirectory(prefix="axiom-lsp-doc-text-presence-") as directory:
        uri = (Path(directory) / "Document.ax").as_uri()
        client = Client(str(compiler))
        actual = {}
        try:
            client.request("initialize", {})
            for phase in ("absent", "empty"):
                if phase == "empty":
                    client.opening(uri, "")
                for method, params in requests(uri):
                    actual[phase + "/" + method] = client.request(method, params)
            client.change(uri, "(:: f Int)\n(fn (f) 1)\n", 2)
            actual["present/callHierarchy/incomingCalls"] = client.request(
                "callHierarchy/incomingCalls", {"item": {"uri": uri, "name": "f"}})
            actual["present/typeHierarchy/supertypes"] = client.request(
                "typeHierarchy/supertypes", {"item": {"uri": uri, "name": "Int"}})
            client.close()
        finally:
            if client.process.poll() is None:
                client.process.kill()
                client.process.wait()
        return actual


def main():
    compiler = Path(sys.argv[1]).resolve()
    expected = json.loads(Path(__file__).with_suffix(".golden.json").read_text())
    actual = probe(compiler)
    assert actual == expected, [
        (key, expected.get(key), actual.get(key))
        for key in sorted(set(expected) | set(actual)) if expected.get(key) != actual.get(key)
    ]
    assert actual["absent/textDocument/documentSymbol"] == []
    assert actual["absent/textDocument/completion"]["items"]
    assert actual["absent/textDocument/semanticTokens/full"] == {"data": []}
    assert actual["empty/textDocument/semanticTokens/full"] == {"data": [], "resultId": "0:1"}
    assert actual["present/callHierarchy/incomingCalls"] == []
    assert actual["present/typeHierarchy/supertypes"] == []
    for method, _ in requests("file:///unused.ax"):
        if method != "textDocument/semanticTokens/full":
            assert actual["absent/" + method] == actual["empty/" + method], method
    print("ok   52 exact LSP responses for unknown, empty and item documents")


if __name__ == "__main__":
    main()
