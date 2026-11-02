#!/usr/bin/env python3
"""Check typed module names, optional unit indices and imported navigation."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import tempfile

# Exact editor output from unchanged 26104a19, including incomplete headers and CRLF edits.
BASELINE = 'CASE function\n{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":3,"character":9},"end":{"line":3,"character":13}}}\n{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":2,"character":8},"end":{"line":2,"character":12}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(pub :: make (-> Int Choice))\\n```\\n\\nfrom `Peer`\\n"},"range":{"start":{"line":1,"character":11},"end":{"line":1,"character":15}}}\n{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":0,"character":10},"end":{"line":0,"character":16}}}\n{"signatures":[{"label":"(make x) : (-> Int Choice) from Peer","parameters":[{"label":[6,7]}]}],"activeSignature":0,"activeParameter":0}\n[{"uri":"file:///tmp/axiom-module-options/Main.ax","range":{"start":{"line":1,"character":11},"end":{"line":1,"character":15}}},{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":2,"character":8},"end":{"line":2,"character":12}}},{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":3,"character":9},"end":{"line":3,"character":13}}}]\nnull\n[{"name":"make","kind":12,"location":{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":3,"character":9},"end":{"line":3,"character":13}}},"containerName":"Peer"}]\nCASE constructor\n{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":0,"character":18},"end":{"line":0,"character":22}}}\n{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":0,"character":18},"end":{"line":0,"character":22}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(pub data Choice (Stop))\\n```\\n\\nconstructor `Stop` of `Choice`\\n\\nfrom `Peer`\\n"},"range":{"start":{"line":1,"character":10},"end":{"line":1,"character":14}}}\n{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":0,"character":10},"end":{"line":0,"character":16}}}\nnull\n[{"uri":"file:///tmp/axiom-module-options/Main.ax","range":{"start":{"line":1,"character":10},"end":{"line":1,"character":14}}},{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":0,"character":18},"end":{"line":0,"character":22}}}]\nnull\n[{"name":"make","kind":12,"location":{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":3,"character":9},"end":{"line":3,"character":13}}},"containerName":"Peer"}]\nCASE data-type\n{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":0,"character":10},"end":{"line":0,"character":16}}}\n{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":0,"character":10},"end":{"line":0,"character":16}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(pub data Choice (Stop))\\n```\\n\\nfrom `Peer`\\n"},"range":{"start":{"line":1,"character":12},"end":{"line":1,"character":18}}}\nnull\nnull\n[{"uri":"file:///tmp/axiom-module-options/Main.ax","range":{"start":{"line":1,"character":12},"end":{"line":1,"character":18}}},{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":0,"character":10},"end":{"line":0,"character":16}}},{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":2,"character":21},"end":{"line":2,"character":27}}}]\n[{"name":"Choice","kind":10,"detail":"data","uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":24}},"selectionRange":{"start":{"line":0,"character":10},"end":{"line":0,"character":16}}}]\n[{"name":"make","kind":12,"location":{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":3,"character":9},"end":{"line":3,"character":13}}},"containerName":"Peer"}]\nCASE struct-type\n{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":1,"character":12},"end":{"line":1,"character":15}}}\n{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":1,"character":12},"end":{"line":1,"character":15}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(pub struct Box)\\n```\\n\\nfrom `Peer`\\n"},"range":{"start":{"line":1,"character":12},"end":{"line":1,"character":15}}}\nnull\nnull\n[{"uri":"file:///tmp/axiom-module-options/Main.ax","range":{"start":{"line":1,"character":12},"end":{"line":1,"character":15}}},{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":1,"character":12},"end":{"line":1,"character":15}}}]\n[{"name":"Box","kind":23,"detail":"struct","uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":1,"character":0},"end":{"line":1,"character":16}},"selectionRange":{"start":{"line":1,"character":12},"end":{"line":1,"character":15}}}]\n[{"name":"make","kind":12,"location":{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":3,"character":9},"end":{"line":3,"character":13}}},"containerName":"Peer"}]\nCASE module\nnull\nnull\n{"contents":{"kind":"markdown","value":"```axiom\\n(import Peer)\\n```\\n\\n*module* `/tmp/axiom-module-options/Peer.ax`\\n"},"range":{"start":{"line":0,"character":8},"end":{"line":0,"character":12}}}\nnull\nnull\nnull\nnull\n[{"name":"make","kind":12,"location":{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":3,"character":9},"end":{"line":3,"character":13}}},"containerName":"Peer"}]\nCASE missing\nnull\nnull\nnull\nnull\nnull\n[{"uri":"file:///tmp/axiom-module-options/Main.ax","range":{"start":{"line":1,"character":10},"end":{"line":1,"character":17}}}]\nnull\n[{"name":"make","kind":12,"location":{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":3,"character":9},"end":{"line":3,"character":13}}},"containerName":"Peer"}]\nCASE local\n{"uri":"file:///tmp/axiom-module-options/Main.ax","range":{"start":{"line":1,"character":5},"end":{"line":1,"character":8}}}\n{"uri":"file:///tmp/axiom-module-options/Main.ax","range":{"start":{"line":1,"character":5},"end":{"line":1,"character":8}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(fn (use) 1)\\n```\\n"},"range":{"start":{"line":1,"character":5},"end":{"line":1,"character":8}}}\nnull\nnull\n[{"uri":"file:///tmp/axiom-module-options/Main.ax","range":{"start":{"line":1,"character":5},"end":{"line":1,"character":8}}}]\nnull\n[{"name":"make","kind":12,"location":{"uri":"file:///tmp/axiom-module-options/Peer.ax","range":{"start":{"line":3,"character":9},"end":{"line":3,"character":13}}},"containerName":"Peer"}]\n'
EXPECTED = "".join(f"{i} true\n" for i in range(1, 34))


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
    fixture = root / "tests/selfhost/lsp-unit-query-options.axp"
    goldens = root / "tests/selfhost/lsp-unit-query-goldens.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    original = (root / "core/lsp.ax").read_text()
    with tempfile.TemporaryDirectory(prefix="axiom-lsp-unit-query-options-") as directory:
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
            print("ok   " + name + ": 33 module/unit cases", flush=True)
            name = "editor-bytes-O" + str(level)
            actual = native(name, env, level, goldens)
            assert actual == BASELINE, (name, actual)
            print("ok   " + name + f": exact {len(BASELINE.encode())} bytes, seven imported editor scenarios", flush=True)

        refusals = {
            "raw-module-word": ('(:: bad (Option Int)) (fn (bad) (lspUnitOf vecNew 0))', 'AX3004'),
            "wrong-module-payload": ('(:: bad (Option Int)) (fn (bad) (lspUnitOf vecNew (Some 0)))', 'AX3004'),
            "unchecked-unit": ('(:: bad Int) (fn (bad) (lspUnitOf vecNew None))', 'AX3004'),
            "unchecked-named-unit": ('(:: bad Int) (fn (bad) (lspUnitNamed vecNew ""))', 'AX3004'),
            "unchecked-home-uri": ('(:: bad String)\n;@axiom:effect(io)\n(fn (bad) (lspNavHomeUri (lspWorkspaceNew vecNew vecNew vecNew) "" "" vecNew "" vecNew))', 'AX3004'),
            "missing-none": ('(:: bad Bool) (fn (bad) (match (lspUnitOf vecNew None) ((Some i) true)))', 'AX3005'),
            "missing-some": ('(:: bad Bool) (fn (bad) (match (lspUnitNamed vecNew "") ((None) false)))', 'AX3005'),
        }
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
                ('module-name-lost', 'lspUnitOf', '((Some name) (lspUnitNamed units name))', '((Some name) { (lspUnitNamed units name) None })', False),
                ('module-absence-forged', 'lspUnitOf', '((None) None)', '((None) (Some 1))', False),
                ('unit-first-winner-lost', 'lspUnitNamed', '(set i (vecLen units))', '()', False),
                ('unit-empty-name-lost', 'lspUnitNamed', '(unitNameIs (vecGet units i) w)', '(if (== (strLen w) 0) false (unitNameIs (vecGet units i) w))', False),
                ('home-uri-lost', 'lspNavHomeUri', '(Some huri)', 'None', False),
                ('unit-location-lost', 'lspUnitLocation', '(lspNavLocOf (lspPathToUri (unitFile unit)) (unitSrc unit) (nodeSpan d))', '{ (lspNavLocOf (lspPathToUri (unitFile unit)) (unitSrc unit) (nodeSpan d)) jsonNull }', False),
                ('call-hierarchy-lost', 'lspChImportedItem', '(lspChItem (unitSrc unit) (lspLineIndex (unitSrc unit)) (lspPathToUri (unitFile unit)) d)', '{ (lspChItem (unitSrc unit) (lspLineIndex (unitSrc unit)) (lspPathToUri (unitFile unit)) d) 0 }', False),
                ('type-hierarchy-lost', 'lspThImportedItem', '(lspThItem (unitSrc unit) (lspLineIndex (unitSrc unit)) (lspPathToUri (unitFile unit)) d)', '{ (lspThItem (unitSrc unit) (lspLineIndex (unitSrc unit)) (lspPathToUri (unitFile unit)) d) 0 }', False),
                ('imported-definition-lost', 'lspDefinitionImported', '(let u (lspUnitOf units (nodeModuleOpt d)))', '(let u (:: None (Option Int)))', True),
                ('imported-hover-lost', 'lspHoverImported', '(let u (lspUnitOf units (nodeModuleOpt d)))', '(let u (:: None (Option Int)))', True),
                ('module-hover-lost', 'lspModuleHover', '(let u (lspUnitNamed units w))', '(let u (:: None (Option Int)))', True),
                ('imported-signature-lost', 'lspViewSigImported', '(let u (lspUnitOf units (nodeModuleOpt d)))', '(let u (:: None (Option Int)))', True),
                ('imported-symbols-lost', 'lspViewSymsImported', '(let u (lspUnitOf units (nodeModuleOpt d)))', '(let u (:: None (Option Int)))', True),
                ('imported-type-location-lost', 'lspTypeLocationImported', '(let u (lspUnitOf units (nodeModuleOpt d)))', '(let u (:: None (Option Int)))', True),
            )
            for name, function, old, new, wire in controls:
                start = original.index("(pub fn (" + function + " ")
                end = original.index("\n\n", start)
                body = original[start:end]
                pattern = re.compile(r"\s*".join(re.escape(part) for part in re.findall(r'"(?:\\.|[^"\\])*"|[(){}]|[^\s(){}]+', old)))
                want = 1
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
                    assert actual != BASELINE and actual.count("CASE ") == 7 and len(actual.splitlines()) == len(BASELINE.splitlines()), (name, actual)
                else:
                    assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 33, (name, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   LSP module/unit Options: 33 cases O0/O2 poison, exact editor bytes, seven refusals")


if __name__ == "__main__":
    main()
