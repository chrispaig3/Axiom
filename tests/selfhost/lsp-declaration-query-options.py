#!/usr/bin/env python3
"""Check optional declaration searches, ownership and unchanged editor responses."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import tempfile

# Unchanged 7f5dff55: twelve sources, eight editor responses per source, virtual imports included.
BASELINE = 'SOURCE empty\nnull\nnull\nnull\nnull\nnull\nNO_INCOMING\nNO_OUTGOING\n[]\nSOURCE signed\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":2,"character":5},"end":{"line":2,"character":10}}}\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":1,"character":4},"end":{"line":1,"character":9}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(:: twice (-> Int Int))\\n```\\n\\ndocs\\n"},"range":{"start":{"line":3,"character":11},"end":{"line":3,"character":16}}}\n{"signatures":[{"label":"(twice x) : (-> Int Int)","parameters":[{"label":[7,8]}],"documentation":{"kind":"markdown","value":"docs\\n"}}],"activeSignature":0,"activeParameter":0}\n[{"name":"twice","kind":12,"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":2,"character":0},"end":{"line":2,"character":22}},"selectionRange":{"start":{"line":2,"character":5},"end":{"line":2,"character":10}}}]\n[{"from":{"name":"use","kind":12,"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":3,"character":0},"end":{"line":3,"character":20}},"selectionRange":{"start":{"line":3,"character":5},"end":{"line":3,"character":8}}},"fromRanges":[{"start":{"line":3,"character":11},"end":{"line":3,"character":16}}]}]\n[]\n[{"position":{"line":2,"character":12},"label":": Int","kind":1},{"position":{"line":2,"character":13},"label":" -> Int","kind":1},{"position":{"line":3,"character":17},"label":"x:","kind":2,"paddingRight":true}]\nSOURCE unsigned\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":0,"character":5},"end":{"line":0,"character":10}}}\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":0,"character":5},"end":{"line":0,"character":10}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(fn (twice x) (+ x x))\\n```\\n"},"range":{"start":{"line":1,"character":11},"end":{"line":1,"character":16}}}\n{"signatures":[{"label":"(twice x)","parameters":[{"label":[7,8]}]}],"activeSignature":0,"activeParameter":0}\n[{"name":"twice","kind":12,"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":22}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":10}}}]\n[{"from":{"name":"use","kind":12,"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":1,"character":0},"end":{"line":1,"character":20}},"selectionRange":{"start":{"line":1,"character":5},"end":{"line":1,"character":8}}},"fromRanges":[{"start":{"line":1,"character":11},"end":{"line":1,"character":16}}]}]\n[]\n[{"position":{"line":1,"character":17},"label":"x:","kind":2,"paddingRight":true}]\nSOURCE declaration\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":2,"character":5},"end":{"line":2,"character":10}}}\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":1,"character":4},"end":{"line":1,"character":9}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(:: twice (-> Int Int))\\n```\\n\\ndocs\\n"},"range":{"start":{"line":2,"character":5},"end":{"line":2,"character":10}}}\nnull\n[{"name":"twice","kind":12,"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":2,"character":0},"end":{"line":2,"character":22}},"selectionRange":{"start":{"line":2,"character":5},"end":{"line":2,"character":10}}}]\n[]\n[]\n[{"position":{"line":2,"character":12},"label":": Int","kind":1},{"position":{"line":2,"character":13},"label":" -> Int","kind":1}]\nSOURCE signature-only\nnull\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":0,"character":4},"end":{"line":0,"character":9}}}\nnull\nnull\nnull\nNO_INCOMING\nNO_OUTGOING\n[]\nSOURCE shadow\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":2,"character":9},"end":{"line":2,"character":14}}}\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":2,"character":9},"end":{"line":2,"character":14}}}\n{"contents":{"kind":"markdown","value":"```axiom\\ntwice\\n```\\n\\nparameter of `use`\\n"},"range":{"start":{"line":2,"character":17},"end":{"line":2,"character":22}}}\nnull\nnull\nNO_INCOMING\nNO_OUTGOING\n[{"position":{"line":1,"character":12},"label":": Int","kind":1},{"position":{"line":1,"character":13},"label":" -> Int","kind":1}]\nSOURCE missing\nnull\nnull\nnull\nnull\nnull\nNO_INCOMING\nNO_OUTGOING\n[]\nSOURCE recovered\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":1,"character":5},"end":{"line":1,"character":10}}}\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":0,"character":4},"end":{"line":0,"character":9}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(:: twice (-> Int Int))\\n```\\n"},"range":{"start":{"line":2,"character":11},"end":{"line":2,"character":16}}}\n{"signatures":[{"label":"(twice x) : (-> Int Int)","parameters":[{"label":[7,8]}]}],"activeSignature":0,"activeParameter":0}\n[{"name":"twice","kind":12,"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":1,"character":0},"end":{"line":1,"character":16}},"selectionRange":{"start":{"line":1,"character":5},"end":{"line":1,"character":10}}}]\n[{"from":{"name":"use","kind":12,"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":2,"character":0},"end":{"line":2,"character":19}},"selectionRange":{"start":{"line":2,"character":5},"end":{"line":2,"character":8}}},"fromRanges":[{"start":{"line":2,"character":11},"end":{"line":2,"character":16}}]}]\n[]\n[{"position":{"line":1,"character":12},"label":": Int","kind":1},{"position":{"line":1,"character":13},"label":" -> Int","kind":1},{"position":{"line":2,"character":17},"label":"x:","kind":2,"paddingRight":true}]\nSOURCE duplicate\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":3,"character":5},"end":{"line":3,"character":9}}}\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":2,"character":4},"end":{"line":2,"character":8}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(:: same String)\\n```\\n"},"range":{"start":{"line":1,"character":5},"end":{"line":1,"character":9}}}\nnull\n[{"name":"same","kind":12,"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":3,"character":0},"end":{"line":3,"character":18}},"selectionRange":{"start":{"line":3,"character":5},"end":{"line":3,"character":9}}}]\n[]\n[]\n[]\nSOURCE poison-signature\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":1,"character":5},"end":{"line":1,"character":12}}}\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":0,"character":4},"end":{"line":0,"character":11}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(:: strange Missing)\\n```\\n"},"range":{"start":{"line":1,"character":5},"end":{"line":1,"character":12}}}\nnull\n[{"name":"strange","kind":12,"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":1,"character":0},"end":{"line":1,"character":16}},"selectionRange":{"start":{"line":1,"character":5},"end":{"line":1,"character":12}}}]\n[]\n[]\n[]\nSOURCE imported\n{"uri":"file:///tmp/axiom-query-fixtures/Peer.ax","range":{"start":{"line":2,"character":9},"end":{"line":2,"character":14}}}\n{"uri":"file:///tmp/axiom-query-fixtures/Peer.ax","range":{"start":{"line":1,"character":8},"end":{"line":1,"character":13}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(pub :: twice (-> Int Int))\\n```\\n\\nfrom `Peer`\\n\\nimported docs\\n"},"range":{"start":{"line":1,"character":11},"end":{"line":1,"character":16}}}\n{"signatures":[{"label":"(twice x) : (-> Int Int) from Peer","parameters":[{"label":[7,8]}],"documentation":{"kind":"markdown","value":"imported docs\\n"}}],"activeSignature":0,"activeParameter":0}\nnull\nNO_INCOMING\nNO_OUTGOING\n[{"position":{"line":1,"character":17},"label":"x:","kind":2,"paddingRight":true}]\nSOURCE own-shadows-import\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":2,"character":5},"end":{"line":2,"character":10}}}\n{"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":1,"character":4},"end":{"line":1,"character":9}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(:: twice Int)\\n```\\n"},"range":{"start":{"line":2,"character":5},"end":{"line":2,"character":10}}}\nnull\n[{"name":"twice","kind":12,"uri":"file:///tmp/axiom-query-fixtures/Main.ax","range":{"start":{"line":2,"character":0},"end":{"line":2,"character":14}},"selectionRange":{"start":{"line":2,"character":5},"end":{"line":2,"character":10}}}]\n[]\n[]\n[]\n'
EXPECTED = "".join(f"{i} true\n" for i in range(1, 45))


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
    fixture = root / "tests/selfhost/lsp-declaration-query-options.axp"
    goldens = root / "tests/selfhost/lsp-declaration-query-goldens.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    original = (root / "core/lsp.ax").read_text()
    with tempfile.TemporaryDirectory(prefix="axiom-lsp-declaration-options-") as directory:
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
            print("ok   " + name, flush=True)
            name = "editor-bytes-O" + str(level)
            actual = native(name, env, level, goldens)
            assert actual == BASELINE, (name, actual)
            print("ok   " + name + ": exact 8450 bytes, virtual imports and call hierarchy", flush=True)

        refusals = {
            "unchecked-declaration": ('(:: bad ASTNode) (fn (bad) (lspFindDecl vecNew "f" -1))', 'AX3004'),
            "unchecked-imported": ('(:: bad ASTNode) (fn (bad) (lspFindImported vecNew "f" -1))', 'AX3004'),
            "unchecked-signature": ('(:: bad ASTNode) (fn (bad) (lspFindSig vecNew "f" -1))', 'AX3004'),
            "unchecked-imported-signature": ('(:: bad ASTNode) (fn (bad) (lspFindImportedSig vecNew "f" -1))', 'AX3004'),
            "missing-none": ('(:: bad Bool) (fn (bad) (match (lspFindFn vecNew "f" -1) ((Some node) true)))', 'AX3005'),
            "missing-some": ('(:: bad Bool) (fn (bad) (match (lspFindImportedFn vecNew "f" -1) ((None) false)))', 'AX3005'),
            "raw-hover-signature": ('(:: bad String) (fn (bad) (lspHoverCode "" nilNode nilNode 0))', 'AX3004'),
            "wrong-declaration-vector": ('(:: bad (Option ASTNode)) (fn (bad) (lspFindFn (vecPush vecNew 1) "f" 0))', 'AX3004'),
        }
        for name, (declaration, code) in refusals.items():
            source = work / (name + ".ax")
            source.write_text("(import core)\n(import parser)\n(import lsp)\n(import Vec)\n" + declaration +
                              "\n(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print("ok   " + name + ": " + code, flush=True)

        if args.negative_controls:
            controls = (
                ("found-declaration-lost", "lspFindDecl", "(Some d)", "None", False),
                ("import-module-filter-lost", "lspFindImported", "(!= (nodeModule d) 0)", "true", False),
                ("signature-winner-changed", "lspFindSig", "(Some d)", "(Some (vecGet decls 0))", False),
                ("imported-signature-bare-match-lost", "lspFindImportedSig", "(bareOf (nodeAName d))", "(nodeAName d)", False),
                ("function-kind-filter-lost", "lspFindFn", "(== (nodeTag d) TAG_D_FN)", "true", False),
                ("imported-function-span-filter-lost", "lspFindImportedFn", "(!= (nodeSpan d) 0)", "true", False),
                ("imported-signature-span-filter-lost", "lspFindImportedSig", "(!= (nodeSpan d) 0)", "true", False),
                ("signature-doc-context-lost", "lspViewSigDoc", "(if (let (Some sig) sig) sig d)", "d", True),
            )
            for name, function, old, new, wire in controls:
                start = original.index("(pub fn (" + function + " ")
                end = original.index("\n\n", start)
                body = original[start:end]
                pattern = re.compile(r"\s+".join(re.escape(part) for part in old.split()))
                assert len(pattern.findall(body)) == 1, (name, len(pattern.findall(body)))
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
                    assert actual != BASELINE and actual.count("SOURCE ") == 12 and len(actual.splitlines()) == len(BASELINE.splitlines()), (name, actual)
                else:
                    assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 44, (name, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   LSP declaration queries: 44 cases O0/O2 poison, exact editor output, eight type/exhaustiveness refusals")


if __name__ == "__main__":
    main()
