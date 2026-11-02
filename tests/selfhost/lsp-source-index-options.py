#!/usr/bin/env python3
"""Check optional source positions and preserve the LSP requests that consume them."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import tempfile

# Exact editor output from unchanged 26104a19, including incomplete headers and CRLF edits.
BASELINE = 'CASE empty\nnull\n[]\n{"data":[]}\n[]\nCASE signature\n{"signatures":[{"label":"(plus x y) : (-> Int Int Int)","parameters":[{"label":[6,7]},{"label":[8,9]}]}],"activeSignature":0,"activeParameter":0}\n[{"name":"plus","kind":12,"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":23}},"selectionRange":{"start":{"line":1,"character":5},"end":{"line":1,"character":9}}},{"name":"use","kind":12,"range":{"start":{"line":2,"character":0},"end":{"line":2,"character":21}},"selectionRange":{"start":{"line":2,"character":5},"end":{"line":2,"character":8}}}]\n{"data":[0,1,2,13,0,0,3,4,7,1,0,6,2,13,0,0,3,3,1,64,0,4,3,1,64,0,4,3,1,64,1,1,2,9,0,0,4,4,7,3,0,5,1,3,1,0,2,1,3,1,0,4,1,13,64,0,2,1,3,0,0,2,1,3,0,1,1,2,9,0,0,4,3,7,3,0,6,4,7,0,0,5,1,12,0,0,2,1,12,0]}\n[{"position":{"line":1,"character":11},"label":": Int","kind":1},{"position":{"line":1,"character":13},"label":": Int","kind":1},{"position":{"line":1,"character":14},"label":" -> Int","kind":1},{"position":{"line":2,"character":16},"label":"x:","kind":2,"paddingRight":true},{"position":{"line":2,"character":18},"label":"y:","kind":2,"paddingRight":true}]\nCASE header\nnull\n[{"name":"plus","kind":12,"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":23}},"selectionRange":{"start":{"line":1,"character":5},"end":{"line":1,"character":9}}}]\n{"data":[0,1,2,13,0,0,3,4,7,1,0,6,2,13,0,0,3,3,1,64,0,4,3,1,64,0,4,3,1,64,1,1,2,9,0,0,4,4,7,3,0,5,1,3,1,0,2,1,3,1,0,4,1,13,64,0,2,1,3,0,0,2,1,3,0]}\n[{"position":{"line":1,"character":11},"label":": Int","kind":1},{"position":{"line":1,"character":13},"label":": Int","kind":1},{"position":{"line":1,"character":14},"label":" -> Int","kind":1}]\nCASE header-open\nnull\n[{"name":"plus","kind":12,"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":13}},"selectionRange":{"start":{"line":1,"character":5},"end":{"line":1,"character":9}}}]\n{"data":[0,1,2,13,0,0,3,4,7,1,0,6,2,13,0,0,3,3,1,64,0,4,3,1,64,0,4,3,1,64,1,1,2,9,0,0,4,4,7,3,0,5,1,3,1,0,2,1,3,1]}\n[{"position":{"line":1,"character":11},"label":": Int","kind":1}]\nCASE indented\nnull\n[{"name":"plus","kind":12,"range":{"start":{"line":1,"character":7},"end":{"line":1,"character":11}},"selectionRange":{"start":{"line":1,"character":7},"end":{"line":1,"character":11}}}]\n{"data":[0,1,2,13,0,0,3,4,7,1,0,6,2,13,0,0,3,3,1,64,0,4,3,1,64,0,4,3,1,64,1,3,2,9,0,0,4,4,7,3,0,5,1,3,1,0,2,1,3,1,0,4,1,13,64,0,2,1,3,0,0,2,1,3,0]}\n[{"position":{"line":1,"character":13},"label":": Int","kind":1},{"position":{"line":1,"character":15},"label":": Int","kind":1},{"position":{"line":1,"character":16},"label":" -> Int","kind":1}]\nCASE nullary\nnull\n[]\n{"data":[0,1,2,13,0,0,3,6,7,1,0,7,3,1,64,1,1,2,9,0,0,3,6,7,3,0,7,2,12,0]}\n[]\nCASE recovered\nnull\n[{"name":"plus","kind":12,"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":22}},"selectionRange":{"start":{"line":1,"character":5},"end":{"line":1,"character":9}}}]\n{"data":[0,1,2,13,0,0,3,4,7,1,0,6,2,13,0,0,3,3,1,64,0,4,3,1,64,0,4,3,1,64,1,1,2,9,0,0,4,4,7,3,0,5,1,3,1,0,2,1,3,1,0,4,1,13,64,0,2,1,3,0,0,2,1,3,0]}\n[{"position":{"line":1,"character":11},"label":": Int","kind":1},{"position":{"line":1,"character":13},"label":": Int","kind":1},{"position":{"line":1,"character":14},"label":" -> Int","kind":1}]\nCASE qualified\nnull\n[{"name":"use","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":23}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}},{"name":"other","kind":12,"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":26}},"selectionRange":{"start":{"line":1,"character":5},"end":{"line":1,"character":10}}}]\n{"data":[0,1,2,9,0,0,4,3,7,3,0,6,1,0,0,0,3,5,7,0,0,6,1,12,0,1,1,2,9,0,0,4,5,7,3,0,6,3,3,1,0,5,3,3,0,0,4,5,5,0]}\n[]\nCASE plain\nnull\n[{"name":"use","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":20}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}}]\n{"data":[0,1,2,9,0,0,4,3,7,3,0,6,5,7,0,0,6,1,12,0]}\n[]\nCASE imports\n{"changes":{"file:///tmp/axiom-source-index/Main.ax":[{"range":{"start":{"line":0,"character":0},"end":{"line":1,"character":14}},"newText":"(import Alpha)\\n(import Zed)"}]}}\nCASE imports-docs-crlf\n{"changes":{"file:///tmp/axiom-source-index/Main.ax":[{"range":{"start":{"line":0,"character":0},"end":{"line":5,"character":14}},"newText":";;; Alpha docs\\r\\n(import Alpha)\\r\\n\\r\\n;;;; Module docs\\r\\n;;; Zed docs\\r\\n(import Zed) ; trailing"}]}}\nCASE imports-invalid-tail\nnull\nCASE extract-whole\n{"title":"Extract to `let`","kind":"refactor.extract","edit":{"changes":{"file:///tmp/axiom-source-index/Main.ax":[{"range":{"start":{"line":0,"character":12},"end":{"line":0,"character":19}},"newText":"{ (let extracted (+ 1 2)) extracted }"}]}}}\nCASE extract-block\n{"title":"Extract to `let`","kind":"refactor.extract","edit":{"changes":{"file:///tmp/axiom-source-index/Main.ax":[{"range":{"start":{"line":0,"character":24},"end":{"line":0,"character":31}},"newText":"{ (let extracted (+ x 2)) extracted }"}]}}}\nCASE extract-nested\n{"title":"Extract to `let`","kind":"refactor.extract","edit":{"changes":{"file:///tmp/axiom-source-index/Main.ax":[{"range":{"start":{"line":0,"character":12},"end":{"line":0,"character":25}},"newText":"{ (let extracted (* 2 3)) (+ 1 extracted) }"}]}}}\nCASE extract-cross-items\nnull\nCASE macro-declaration\n{"name":"identity","expansion":""}\nCASE macro-absent\nnull\nCASE macro-products\n{"name":"decl","expansion":"(pub :: answer Int)\\n\\n(pub fn (answer)\\n  42)"}\n'
EXPECTED = "".join(f"{i} true\n" for i in range(1, 88))


def execute(arguments, env):
    return subprocess.run(arguments, env=env, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--negative-controls", action="store_true")
    parser.add_argument("--skip-positive", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/selfhost/lsp-source-index-options.axp"
    goldens = root / "tests/selfhost/lsp-source-index-goldens.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    original = (root / "core/lsp.ax").read_text()
    with tempfile.TemporaryDirectory(prefix="axiom-lsp-source-index-options-") as directory:
        work = Path(directory)

        def native(name, local, level, source=fixture):
            binary = work / name
            built = execute([compiler, "--diagnostic-format=ai", "build", str(source),
                             "--opt", str(level), "--alloc-poison", "-o", str(binary)], local)
            assert built.returncode == 0, (name, built.returncode, built.stdout, built.stderr)
            ran = execute([str(binary)], local)
            assert ran.returncode == 0 and not ran.stderr, (name, ran.returncode, ran.stdout, ran.stderr)
            return ran.stdout

        for level in (() if args.skip_positive else (0, 2)):
            name = "positive-O" + str(level)
            actual = native(name, env, level)
            assert actual == EXPECTED, (name, actual)
            print("ok   " + name + ": 87 source-position cases", flush=True)
            name = "editor-bytes-O" + str(level)
            actual = native(name, env, level, goldens)
            assert actual == BASELINE, (name, actual)
            print("ok   " + name + f": exact {len(BASELINE.encode())} bytes, 19 editor scenarios", flush=True)

        queries = {
            "call": 'lspViewCallAt "(f)" 0',
            "header": 'lspHeaderOpen "(f)" 1',
            "colons": 'lspFixLastColons "::a" 1',
            "child": 'lspFixKidHolding vecNew 0 1 0',
            "statement": 'lspFixStatementAt "" vecNew',
            "import-start": 'lspOrganizeStart "(import A)" 0',
            "import-end": 'lspOrganizeEnd "" 0',
            "macro": 'lspMacroSiteAt "" vecNew 0',
            "qualified-chain": 'lspHlChainEnd "A::b" 0 4',
        }
        refusals = {"unchecked-" + name: ('(:: bad Int) (fn (bad) (' + query + '))', 'AX3004')
                    for name, query in queries.items()}
        refusals.update({
            "missing-none": ('(:: bad Bool) (fn (bad) (match (lspViewCallAt "(f)" 0) ((Some i) true)))', 'AX3005'),
            "missing-some": ('(:: bad Bool) (fn (bad) (match (lspHeaderOpen "f" 0) ((None) false)))', 'AX3005'),
            "wrong-option-index": ('(:: bad (Option String)) (fn (bad) (lspFixStatementAt "" vecNew))', 'AX3004'),
        })
        for name, (declaration, code) in refusals.items():
            source = work / (name + ".ax")
            source.write_text("(import core)\n(import lsp)\n" + declaration +
                              "\n(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print("ok   " + name + ": " + code, flush=True)

        if args.negative_controls:
            controls = (
                ("call-zero-lost", "lspViewCallAt", "(Some off)", "None", False),
                ("header-zero-lost", "lspHeaderOpen", "(Some o)", "None", False),
                ("colons-zero-lost", "lspFixLastColons", "(Some i)", "None", False),
                ("child-zero-lost", "lspFixKidHolding", "(Some k)", "None", False),
                ("last-statement-lost", "lspFixStatementAt", "(set at (Some j))", "(if (isNone at) (set at (Some j)))", False),
                ("import-start-lost", "lspOrganizeStart", "(Some start)", "None", False),
                ("import-end-lost", "lspOrganizeEnd", "(Some end)", "None", False),
                ("macro-presence-lost", "lspMacroSiteAt", "(set found (Some i))", "(set found None)", False),
                ("qualified-presence-lost", "lspHlChainEnd", "(Some c)", "None", False),
                ("header-absence-forged", "lspHeaderOpen", "(if (== (strByte src o) 40) (Some o) None)", "(Some o)", False),
                ("import-opener-forged", "lspOrganizeCollect", "(let mut opener (:: None (Option Int)))", "(let mut opener (:: (Some 0) (Option Int)))", False),
                ("child-missing-accepted", "lspFixDescend", "((None) (set go 0) )", "((None) (set done 1))", False),
                ("param-header-lost", "lspParamTypeAt", "(let hs (lspHeaderOpen src (spanStart (nodeSpan d))))", "(let hs (:: None (Option Int)))", False),
                ("header-close-lost", "lspViewHintsHeader", "(set close (Some i))", "(set close None)", True),
                ("call-request-lost", "lspSignatureHelp", '(let o (lspViewCallAt src (lspOffsetOf src ix (jsonGet params "position"))))', "(let o (:: None (Option Int)))", True),
                ("symbol-header-unchecked", "lspSymbolExtent", "((Some header) (!= o header))", "((Some header) true)", False),
                ("extraction-lost", "lspExtractIn", "(lspExtractJson src uri ix ws we fs fe (lspFixFreshName occs))", "0", True),
                ("macro-request-lost", "lspExpandMacro", "((Some site) (lspExpandAt workspace (lspUriToPath uri) src decls site))", "((Some site) { (lspExpandAt workspace (lspUriToPath uri) src decls site) jsonNull })", True),
            )
            for name, function, old, new, wire in controls:
                start = original.index("(pub fn (" + function + " ")
                end = original.index("\n\n", start)
                body = original[start:end]
                pattern = re.compile(r"\s+".join(re.escape(part) for part in old.split()))
                want = 2 if name == "macro-presence-lost" else 1
                assert len(pattern.findall(body)) == want, (name, len(pattern.findall(body)))
                changed = original[:start] + pattern.sub(lambda match: new, body) + original[end:]
                overlay = work / (name + "-core/core")
                overlay.mkdir(parents=True)
                for path in (root / "core").iterdir():
                    if path.name == "lsp.ax":
                        (overlay / path.name).write_text(changed)
                    else:
                        (overlay / path.name).symlink_to(path, target_is_directory=path.is_dir())
                actual = native(name, dict(env, AXIOM_PATH=str(overlay)), 0, goldens if wire else fixture)
                if wire:
                    assert actual != BASELINE and actual.count("CASE ") == 19 and len(actual.splitlines()) == len(BASELINE.splitlines()), (name, actual)
                else:
                    assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 87, (name, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   LSP source-position Options: 87 cases O0/O2 poison, exact editor bytes, 12 refusals")


if __name__ == "__main__":
    main()
