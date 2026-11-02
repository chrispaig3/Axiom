#!/usr/bin/env python3
"""Check optional field/type/constructor searches, ownership and unchanged editor responses."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import tempfile

# Unchanged 4ee86a21: thirteen sources, five editor responses each, including virtual imports.
BASELINE = 'SOURCE empty\nnull\nnull\nnull\nnull\n[]\nSOURCE field-declaration\nnull\nnull\n{"contents":{"kind":"markdown","value":"```axiom\\n(struct Box (field : Int))\\n```\\n\\nfield `field` of `struct Box`\\n"},"range":{"start":{"line":0,"character":13},"end":{"line":0,"character":18}}}\nnull\n[]\nSOURCE field-use\nnull\nnull\n{"contents":{"kind":"markdown","value":"```axiom\\n(struct Box (field : Int))\\n```\\n\\nfield `field` of `struct Box`\\n"},"range":{"start":{"line":1,"character":42},"end":{"line":1,"character":47}}}\nnull\n[{"position":{"line":1,"character":21},"label":": Box","kind":1}]\nSOURCE unknown-field\nnull\nnull\nnull\nnull\n[{"position":{"line":1,"character":21},"label":": Box","kind":1}]\nSOURCE ctor-first\n{"uri":"file:///tmp/axiom-field-fixtures/Main.ax","range":{"start":{"line":0,"character":13},"end":{"line":0,"character":19}}}\n{"uri":"file:///tmp/axiom-field-fixtures/Main.ax","range":{"start":{"line":0,"character":6},"end":{"line":0,"character":11}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(data Shape (Circle Int) (Point))\\n```\\n\\nconstructor `Circle` of `Shape`\\n"},"range":{"start":{"line":1,"character":11},"end":{"line":1,"character":17}}}\n{"signatures":[{"label":"(Circle Int)","parameters":[{"label":[8,11]}]}],"activeSignature":0,"activeParameter":0}\n[]\nSOURCE ctor-nullary\n{"uri":"file:///tmp/axiom-field-fixtures/Main.ax","range":{"start":{"line":0,"character":26},"end":{"line":0,"character":31}}}\n{"uri":"file:///tmp/axiom-field-fixtures/Main.ax","range":{"start":{"line":0,"character":6},"end":{"line":0,"character":11}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(data Shape (Circle Int) (Point))\\n```\\n\\nconstructor `Point` of `Shape`\\n"},"range":{"start":{"line":0,"character":26},"end":{"line":0,"character":31}}}\n{"signatures":[{"label":"(Point)","parameters":[]}],"activeSignature":0,"activeParameter":0}\n[]\nSOURCE ctor-missing\nnull\nnull\nnull\nnull\n[]\nSOURCE duplicate-ctor\n{"uri":"file:///tmp/axiom-field-fixtures/Main.ax","range":{"start":{"line":1,"character":12},"end":{"line":1,"character":16}}}\n{"uri":"file:///tmp/axiom-field-fixtures/Main.ax","range":{"start":{"line":1,"character":6},"end":{"line":1,"character":10}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(data Last (Make String))\\n```\\n\\nconstructor `Make` of `Last`\\n"},"range":{"start":{"line":2,"character":11},"end":{"line":2,"character":15}}}\n{"signatures":[{"label":"(Make Int)","parameters":[{"label":[6,9]}]}],"activeSignature":0,"activeParameter":0}\n[]\nSOURCE type-local\n{"uri":"file:///tmp/axiom-field-fixtures/Main.ax","range":{"start":{"line":0,"character":8},"end":{"line":0,"character":11}}}\nnull\n{"contents":{"kind":"markdown","value":"```axiom\\n(struct Box (field : Int))\\n```\\n"},"range":{"start":{"line":1,"character":13},"end":{"line":1,"character":16}}}\nnull\n[{"position":{"line":2,"character":13},"label":": Box","kind":1},{"position":{"line":2,"character":14},"label":" -> Int","kind":1}]\nSOURCE type-poison\nnull\nnull\n{"contents":{"kind":"markdown","value":"```axiom\\n(struct Box (field : Missing))\\n```\\n\\nfield `field` of `struct Box`\\n"},"range":{"start":{"line":1,"character":42},"end":{"line":1,"character":47}}}\nnull\n[{"position":{"line":1,"character":21},"label":": Box","kind":1}]\nSOURCE recovered\n{"uri":"file:///tmp/axiom-field-fixtures/Main.ax","range":{"start":{"line":0,"character":13},"end":{"line":0,"character":19}}}\n{"uri":"file:///tmp/axiom-field-fixtures/Main.ax","range":{"start":{"line":0,"character":6},"end":{"line":0,"character":11}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(data Shape (Circle Int))\\n```\\n\\nconstructor `Circle` of `Shape`\\n"},"range":{"start":{"line":1,"character":11},"end":{"line":1,"character":17}}}\n{"signatures":[{"label":"(Circle Int)","parameters":[{"label":[8,11]}]}],"activeSignature":0,"activeParameter":0}\n[]\nSOURCE imported-ctor\n{"uri":"file:///tmp/axiom-field-fixtures/Peer.ax","range":{"start":{"line":0,"character":17},"end":{"line":0,"character":23}}}\n{"uri":"file:///tmp/axiom-field-fixtures/Peer.ax","range":{"start":{"line":0,"character":10},"end":{"line":0,"character":15}}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(pub data Shape (Circle Int) (Point))\\n```\\n\\nconstructor `Circle` of `Shape`\\n\\nfrom `Peer`\\n"},"range":{"start":{"line":1,"character":11},"end":{"line":1,"character":17}}}\n{"signatures":[{"label":"(Circle Int)","parameters":[{"label":[8,11]}]}],"activeSignature":0,"activeParameter":0}\n[]\nSOURCE imported-type\n{"uri":"file:///tmp/axiom-field-fixtures/Peer.ax","range":{"start":{"line":0,"character":10},"end":{"line":0,"character":15}}}\nnull\n{"contents":{"kind":"markdown","value":"```axiom\\n(pub data Shape (Circle Int) (Point))\\n```\\n\\nfrom `Peer`\\n"},"range":{"start":{"line":1,"character":13},"end":{"line":1,"character":18}}}\nnull\n[{"position":{"line":2,"character":11},"label":": Shape","kind":1},{"position":{"line":2,"character":12},"label":" -> Int","kind":1}]\n'
EXPECTED = "".join(f"{i} true\n" for i in range(1, 59))


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
    fixture = root / "tests/selfhost/lsp-field-query-options.axp"
    goldens = root / "tests/selfhost/lsp-field-query-goldens.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    original = (root / "core/lsp.ax").read_text()
    with tempfile.TemporaryDirectory(prefix="axiom-lsp-field-options-") as directory:
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
            print("ok   " + name + ": exact 4898 bytes, fields and local/imported constructors", flush=True)

        refusals = {
            "unchecked-field": ('(:: bad ASTNode) (fn (bad) (lspStructFieldNode vecNew "x" 0))', 'AX3004'),
            "unchecked-type": ('(:: bad ASTNode) (fn (bad) (lspFindTypeDecl vecNew "T" -1))', 'AX3004'),
            "unchecked-ctor": ('(:: bad ASTNode) (fn (bad) (lspFindCtorData vecNew "C" -1))', 'AX3004'),
            "unchecked-index": ('(:: bad Int) (fn (bad) (lspCtorIndex vecNew "C" 0))', 'AX3004'),
            "missing-none": ('(:: bad Bool) (fn (bad) (match (lspViewCtorIn vecNew "C") ((Some node) true)))', 'AX3005'),
            "missing-some": ('(:: bad Bool) (fn (bad) (match (lspFindTypeImported vecNew "T" -1) ((None) false)))', 'AX3005'),
            "raw-owner": ('(:: bad (Option ASTNode)) (fn (bad) (lspCtorNodeOf nilNode "C"))', 'AX3004'),
            "raw-field-context": ('(:: bad String) (fn (bad) (lspFieldEffectsSaid nilNode))', 'AX3004'),
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
                ("field-result-lost", "lspStructFieldNode", "(Some f)", "None", False),
                ("field-span-filter-lost", "lspFieldNodeAt", "(lspSpanHas (nodeSpan f) off)", "true", False),
                ("type-span-filter-lost", "lspFindTypeDecl", "(!= (nodeSpan d) 0)", "true", False),
                ("imported-type-filter-lost", "lspFindTypeImported", "(!= (nodeModule d) 0)", "true", False),
                ("ctor-index-zero-lost", "lspCtorIndex", "(Some i)", "(Some (+ i 1))", False),
                ("ctor-order-changed", "lspViewCtorIn", "(Some (vecGet ctors i))", "(Some (vecGet ctors (- n 1)))", False),
                ("ctor-span-filter-lost", "lspCtorNodeOf", "(== (nodeSpan c) 0)", "false", False),
                ("imported-ctor-filter-lost", "lspFindCtorDataImported", "(!= (nodeModule d) 0)", "true", False),
                ("ctor-hover-context-lost", "lspCtorNote", "constructor `", "changed `", True),
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
                    assert actual != BASELINE and actual.count("SOURCE ") == 13 and len(actual.splitlines()) == len(BASELINE.splitlines()), (name, actual)
                else:
                    assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 58, (name, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   LSP field/type/constructor queries: 58 cases O0/O2 poison, exact editor output, eight type/exhaustiveness refusals")


if __name__ == "__main__":
    main()
