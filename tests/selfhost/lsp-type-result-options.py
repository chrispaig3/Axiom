#!/usr/bin/env python3
"""Check optional LSP result types and navigation inputs, preserving editor responses."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import tempfile

# Unchanged 685b5608: 14 navigation scenarios and six synthetic arrow-header boundaries.
BASELINE = 'CASE empty\nnull\n[]\nnull\nCASE local-result\n{"uri":"file:///tmp/axiom-type-result-fixtures/Main.ax","range":{"start":{"line":0,"character":8},"end":{"line":0,"character":11}}}\n[{"position":{"line":2,"character":11},"label":": Int","kind":1},{"position":{"line":2,"character":12},"label":" -> Box","kind":1},{"position":{"line":3,"character":16},"label":"p:","kind":2,"paddingRight":true}]\n{"contents":{"kind":"markdown","value":"```axiom\\n(:: make (-> Int Box))\\n```\\n"},"range":{"start":{"line":3,"character":11},"end":{"line":3,"character":15}}}\nCASE parameter\n{"uri":"file:///tmp/axiom-type-result-fixtures/Main.ax","range":{"start":{"line":0,"character":8},"end":{"line":0,"character":11}}}\n[{"position":{"line":2,"character":10},"label":": Box","kind":1},{"position":{"line":2,"character":11},"label":" -> Int","kind":1}]\n{"contents":{"kind":"markdown","value":"```axiom\\nbox : Box\\n```\\n\\nparameter of `f`\\n"},"range":{"start":{"line":2,"character":7},"end":{"line":2,"character":10}}}\nCASE nullary\nnull\n[]\nnull\nCASE unsigned\nnull\n[{"position":{"line":1,"character":16},"label":"p:","kind":2,"paddingRight":true}]\n{"contents":{"kind":"markdown","value":"```axiom\\n(fn (make p) p)\\n```\\n"},"range":{"start":{"line":1,"character":11},"end":{"line":1,"character":15}}}\nCASE unit\nnull\n[{"position":{"line":1,"character":11},"label":": Int","kind":1},{"position":{"line":1,"character":12},"label":" -> ()","kind":1},{"position":{"line":2,"character":16},"label":"p:","kind":2,"paddingRight":true}]\n{"contents":{"kind":"markdown","value":"```axiom\\n(:: make (-> Int ()))\\n```\\n"},"range":{"start":{"line":2,"character":11},"end":{"line":2,"character":15}}}\nCASE unknown\nnull\n[]\nnull\nCASE recovered\nnull\n[{"position":{"line":1,"character":11},"label":": Int","kind":1},{"position":{"line":1,"character":12},"label":" -> Int","kind":1}]\n{"contents":{"kind":"markdown","value":"```axiom\\n(:: make (-> Int Int))\\n```\\n"},"range":{"start":{"line":1,"character":5},"end":{"line":1,"character":9}}}\nCASE trailing\nnull\n[{"position":{"line":1,"character":11},"label":": Int","kind":1},{"position":{"line":1,"character":12},"label":" -> Int","kind":1}]\n{"contents":{"kind":"markdown","value":"```axiom\\n(:: make (-> Int Int))\\n```\\n"},"range":{"start":{"line":1,"character":5},"end":{"line":1,"character":9}}}\nCASE imported-result\n{"uri":"file:///tmp/axiom-type-result-fixtures/Peer.ax","range":{"start":{"line":0,"character":10},"end":{"line":0,"character":16}}}\n[{"position":{"line":1,"character":16},"label":"p:","kind":2,"paddingRight":true}]\n{"contents":{"kind":"markdown","value":"```axiom\\n(pub :: make (-> Int Choice))\\n```\\n\\nfrom `Peer`\\n"},"range":{"start":{"line":1,"character":11},"end":{"line":1,"character":15}}}\nCASE imported-ctor\n{"uri":"file:///tmp/axiom-type-result-fixtures/Peer.ax","range":{"start":{"line":0,"character":10},"end":{"line":0,"character":16}}}\n[]\n{"contents":{"kind":"markdown","value":"```axiom\\n(pub data Choice (Stop))\\n```\\n\\nconstructor `Stop` of `Choice`\\n\\nfrom `Peer`\\n"},"range":{"start":{"line":1,"character":10},"end":{"line":1,"character":14}}}\nCASE local-signature-imported-type\n{"uri":"file:///tmp/axiom-type-result-fixtures/Peer.ax","range":{"start":{"line":0,"character":10},"end":{"line":0,"character":16}}}\n[{"position":{"line":2,"character":10},"label":": Choice","kind":1},{"position":{"line":2,"character":11},"label":" -> Choice","kind":1}]\n{"contents":{"kind":"markdown","value":"```axiom\\np : Choice\\n```\\n\\nparameter of `use`\\n"},"range":{"start":{"line":2,"character":9},"end":{"line":2,"character":10}}}\nCASE local-type-precedence\n{"uri":"file:///tmp/axiom-type-result-fixtures/Main.ax","range":{"start":{"line":1,"character":8},"end":{"line":1,"character":14}}}\n[{"position":{"line":3,"character":10},"label":": Choice","kind":1},{"position":{"line":3,"character":11},"label":" -> Int","kind":1}]\n{"contents":{"kind":"markdown","value":"```axiom\\np : Choice\\n```\\n\\nparameter of `use`\\n"},"range":{"start":{"line":3,"character":9},"end":{"line":3,"character":10}}}\nCASE missing-imported-function\nnull\n[]\nnull\nCASE missing-result\n[{"position":{"line":0,"character":8},"label":": Int","kind":1},{"position":{"line":0,"character":9},"label":" -> {unknown}","kind":1}]\nCASE poison-result\n[{"position":{"line":0,"character":8},"label":": Int","kind":1},{"position":{"line":0,"character":9},"label":" -> {unknown}","kind":1}]\nCASE empty-result\n[{"position":{"line":0,"character":8},"label":": Int","kind":1},{"position":{"line":0,"character":9},"label":" -> ","kind":1}]\nCASE unit-result\n[{"position":{"line":0,"character":8},"label":": Int","kind":1},{"position":{"line":0,"character":9},"label":" -> ()","kind":1}]\nCASE missing-domain\n[{"position":{"line":0,"character":9},"label":" -> String","kind":1}]\nCASE poison-domain\n[{"position":{"line":0,"character":9},"label":" -> String","kind":1}]\n'
EXPECTED = "".join(f"{i} true\n" for i in range(1, 51))


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
    fixture = root / "tests/selfhost/lsp-type-result-options.axp"
    goldens = root / "tests/selfhost/lsp-type-result-goldens.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    original = (root / "core/lsp.ax").read_text()
    with tempfile.TemporaryDirectory(prefix="axiom-lsp-type-result-options-") as directory:
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
            print("ok   " + name + f": exact {len(BASELINE.encode())} bytes, 20 navigation and arrow-header scenarios", flush=True)

        refusals = {
            "unchecked-view-result": ('(:: bad ASTNode) (fn (bad) (lspViewResultTy mkIntTy))', 'AX3004'),
            "unchecked-arrow-result": ('(:: bad ASTNode) (fn (bad) (lspArrowResult mkIntTy))', 'AX3004'),
            "unchecked-local-type": ('(:: bad ASTNode) (fn (bad) (lspLocalTypeOf "" vecNew 0 "f"))', 'AX3004'),
            "raw-location-input": ('(:: bad Int) (fn (bad) (lspTypeLocation (lspWorkspaceNew vecNew vecNew vecNew) "" "" "" vecNew "f" nilNode))', 'AX3004'),
            "raw-imported-input": ('(:: bad Int) (fn (bad) (lspTypeLocationImported (lspWorkspaceNew vecNew vecNew vecNew) "" "" "" vecNew "f" nilNode))', 'AX3004'),
            "wrong-option-payload": ('(:: bad Int) (fn (bad) (lspTypeLocation (lspWorkspaceNew vecNew vecNew vecNew) "" "" "" vecNew "f" (Some 0)))', 'AX3004'),
            "missing-none": ('(:: bad Bool) (fn (bad) (match (lspArrowResult mkIntTy) ((Some ty) true)))', 'AX3005'),
            "missing-some": ('(:: bad Bool) (fn (bad) (match (lspViewResultTy mkIntTy) ((None) false)))', 'AX3005'),
            "unchecked-local-absence": ('(:: bad Bool) (fn (bad) (match (lspLocalTypeOf "" vecNew 0 "f") ((Some ty) true)))', 'AX3005'),
        }
        for name, (declaration, code) in refusals.items():
            if name in {"raw-location-input", "raw-imported-input", "wrong-option-payload"}:
                declaration = declaration.replace(" (fn", "\n;@axiom:effect(io)\n(fn", 1)
            source = work / (name + ".ax")
            source.write_text("(import core)\n(import parser)\n(import lsp)\n" + declaration +
                              "\n(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print("ok   " + name + ": " + code, flush=True)

        if args.negative_controls:
            controls = (
                ("result-present-lost", "lspViewResultTy", "(Some ty)", "None", False),
                ("result-absence-forged", "lspViewResultTy", "(if (nodeSame ty nilNode) None", "(if (nodeSame ty nilNode) (Some mkIntTy)", False),
                ("result-identity-copied", "lspViewResultTy", "(Some ty)", "(Some (nodeClone ty))", False),
                ("arrow-forwarding-lost", "lspArrowResult", "(lspViewResultTy t)", "None", False),
                ("parameter-presence-lost", "lspLocalTypeOf", "((Some parameter) (Some parameter))", "((Some parameter) None)", False),
                ("unsigned-result-forged", "lspLocalTypeOf", "(match (lspFindSig decls w (- (vecLen decls) 1)) ((None) None)", "(match (lspFindSig decls w (- (vecLen decls) 1)) ((None) (Some mkIntTy))", False),
                ("given-type-presence-lost", "lspTypeLocationImported", "((Some ty) (Some ty))", "((Some ty) None)", False),
                ("imported-result-lost", "lspTypeLocationImported", "(lspArrowResult (nodeTyChild sig))", "None", False),
                ("constructor-fallback-lost", "lspTypeLocationImported", "((None) (lspTypeCtorImported allDecls units w))", "((None) jsonNull)", False),
                ("local-location-lost", "lspTypeLocation", "(if (!= local 0) local", "(if (!= local 0) jsonNull", False),
                ("missing-header-result-lost", "lspViewHintsHeader", '((None) "{unknown}")', '((None) "")', False),
                ("poison-header-result-hidden", "lspViewHintsHeader", "((Some result) (tyRender result))", '((Some result) (if (== (nodeTag result) TAG_T_ERR) "" (tyRender result)))', False),
                ("definition-forwarding-lost", "lspTypeDefinition", '(lspTypeLocation workspace (lspUriToPath uri) src uri decls "" (Some ty))', "jsonNull", True),
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
                    assert actual != BASELINE and actual.count("CASE ") == 20 and len(actual.splitlines()) == len(BASELINE.splitlines()), (name, actual)
                else:
                    assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 50, (name, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   LSP result/navigation Options: 50 cases O0/O2 poison, exact editor bytes, nine type/exhaustiveness refusals")


if __name__ == "__main__":
    main()
