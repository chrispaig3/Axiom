#!/usr/bin/env python3
"""Check optional occurrence values and unchanged editor query output."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import tempfile

# Untouched fafa5906: ten inputs, six editor query responses each.
BASELINE = 'SOURCE \nnull\nnull\nnull\nnull\n[]\n{"data":[]}\nSOURCE (fn (test) { (let value 7) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value 7)\\nvalue : Int\\n```\\n\\nbound by `let` in `test`\\n"},"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}}}\n[{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"kind":3},{"range":{"start":{"line":0,"character":27},"end":{"line":0,"character":32}},"kind":2}]\n{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"placeholder":"value"}\n{"changes":{"file:///tmp/lsp-occurrence.ax":[{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"newText":"fresh"},{"range":{"start":{"line":0,"character":27},"end":{"line":0,"character":32}},"newText":"fresh"}]}}\n[{"position":{"line":0,"character":23},"label":": Int","kind":1}]\n{"data":[0,1,2,9,0,0,4,4,7,3,0,9,3,9,0,0,4,5,4,5,0,6,1,12,0,0,3,5,4,0]}\nSOURCE (fn (test) { (let value "") value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value \\"\\")\\nvalue : String\\n```\\n\\nbound by `let` in `test`\\n"},"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}}}\n[{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"kind":3},{"range":{"start":{"line":0,"character":28},"end":{"line":0,"character":33}},"kind":2}]\n{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"placeholder":"value"}\n{"changes":{"file:///tmp/lsp-occurrence.ax":[{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"newText":"fresh"},{"range":{"start":{"line":0,"character":28},"end":{"line":0,"character":33}},"newText":"fresh"}]}}\n[{"position":{"line":0,"character":23},"label":": String","kind":1}]\n{"data":[0,1,2,9,0,0,4,4,7,3,0,9,3,9,0,0,4,5,4,5,0,6,2,11,0,0,4,5,4,0]}\nSOURCE (fn (test) { (let value ()) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value ())\\nvalue : ()\\n```\\n\\nbound by `let` in `test`\\n"},"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}}}\n[{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"kind":3},{"range":{"start":{"line":0,"character":28},"end":{"line":0,"character":33}},"kind":2}]\n{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"placeholder":"value"}\n{"changes":{"file:///tmp/lsp-occurrence.ax":[{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"newText":"fresh"},{"range":{"start":{"line":0,"character":28},"end":{"line":0,"character":33}},"newText":"fresh"}]}}\n[{"position":{"line":0,"character":23},"label":": ()","kind":1}]\n{"data":[0,1,2,9,0,0,4,4,7,3,0,9,3,9,0,0,4,5,4,5,0,10,5,4,0]}\nSOURCE (:: test (-> Int Int)) (fn (test p) p)\nnull\nnull\nnull\nnull\n[{"position":{"line":0,"character":34},"label":": Int","kind":1},{"position":{"line":0,"character":35},"label":" -> Int","kind":1}]\n{"data":[0,1,2,13,0,0,3,4,7,1,0,6,2,13,0,0,3,3,1,64,0,4,3,1,64,0,7,2,9,0,0,4,4,7,3,0,5,1,3,1,0,3,1,3,0]}\nSOURCE (fn (test p) p)\n{"contents":{"kind":"markdown","value":"```axiom\\np\\n```\\n\\nparameter of `test`\\n"},"range":{"start":{"line":0,"character":10},"end":{"line":0,"character":11}}}\n[{"range":{"start":{"line":0,"character":10},"end":{"line":0,"character":11}},"kind":3},{"range":{"start":{"line":0,"character":13},"end":{"line":0,"character":14}},"kind":2}]\n{"range":{"start":{"line":0,"character":10},"end":{"line":0,"character":11}},"placeholder":"p"}\n{"changes":{"file:///tmp/lsp-occurrence.ax":[{"range":{"start":{"line":0,"character":10},"end":{"line":0,"character":11}},"newText":"fresh"},{"range":{"start":{"line":0,"character":13},"end":{"line":0,"character":14}},"newText":"fresh"}]}}\n[]\n{"data":[0,1,2,9,0,0,4,4,7,3,0,5,1,3,1,0,3,1,3,0]}\nSOURCE (fn (test) { (let value missing) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value missing)\\n```\\n\\nbound by `let` in `test`\\n"},"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}}}\n[{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"kind":3},{"range":{"start":{"line":0,"character":33},"end":{"line":0,"character":38}},"kind":2}]\n{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"placeholder":"value"}\n{"changes":{"file:///tmp/lsp-occurrence.ax":[{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"newText":"fresh"},{"range":{"start":{"line":0,"character":33},"end":{"line":0,"character":38}},"newText":"fresh"}]}}\n[]\n{"data":[0,1,2,9,0,0,4,4,7,3,0,9,3,9,0,0,4,5,4,5,0,6,7,4,0,0,9,5,4,0]}\nSOURCE (fn (test) { (let value 7) value }\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value 7)\\nvalue : Int\\n```\\n\\nbound by `let` in `test`\\n"},"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}}}\n[{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"kind":3},{"range":{"start":{"line":0,"character":27},"end":{"line":0,"character":32}},"kind":2}]\n{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"placeholder":"value"}\n{"changes":{"file:///tmp/lsp-occurrence.ax":[{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"newText":"fresh"},{"range":{"start":{"line":0,"character":27},"end":{"line":0,"character":32}},"newText":"fresh"}]}}\n[{"position":{"line":0,"character":23},"label":": Int","kind":1}]\n{"data":[0,1,2,9,0,0,4,4,7,3,0,9,3,9,0,0,4,5,4,5,0,6,1,12,0,0,3,5,4,0]}\nSOURCE (fn (test) { (let value 7) value }) @\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value 7)\\nvalue : Int\\n```\\n\\nbound by `let` in `test`\\n"},"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}}}\n[{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":23}},"kind":3},{"range":{"start":{"line":0,"character":27},"end":{"line":0,"character":32}},"kind":2}]\nnull\nnull\n[{"position":{"line":0,"character":23},"label":": Int","kind":1}]\n{"data":[0,1,2,9,0,0,4,4,7,3,0,9,3,9,0,0,4,5,4,5,0,6,1,12,0,0,3,5,4,0]}\nSOURCE (struct Box (field : Int)) (fn (test) { (let box (Box :field 1)) box.field })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let name value)\\n```\\n\\n*keyword*\\n\\nDeclares a local inside a `{ ... }` block. The value is evaluated before the name enters scope; later statements can read it, and a later declaration can shadow it. Use `(let mut name value)` for a local that `set` can change. Destructure values with `match`. The block answers its last expression.\\n\\nReference: `docs/reference.md#let-bindings`\\n"},"range":{"start":{"line":0,"character":41},"end":{"line":0,"character":44}}}\nnull\nnull\nnull\n[{"position":{"line":0,"character":48},"label":": Box","kind":1}]\n{"data":[0,1,6,9,0,0,7,3,1,1,0,5,5,5,1,0,8,3,1,64,0,7,2,9,0,0,4,4,7,3,0,9,3,9,0,0,4,3,4,5,0,5,3,6,0,0,5,5,5,0,0,6,1,12,0,0,4,3,4,0,0,4,5,5,0]}\n'
EXPECTED = "".join(f"{i} true\n" for i in range(1, 32))


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
    fixture = root / "tests/selfhost/lsp-occurrence-value-options.axp"
    goldens = root / "tests/selfhost/lsp-occurrence-value-goldens.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    original = (root / "core/lsp.ax").read_text()
    with tempfile.TemporaryDirectory(prefix="axiom-lsp-occurrence-values-") as directory:
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
            print("ok   " + name + ": exact 6854 bytes", flush=True)

        record = '(LspOcc :name "x" :span 0 :role NAV_BINDER :key "@0" :bkind NAV_B_LET :owner "f" :param 0 :value VALUE)'
        refusals = {
            "raw-record-value": ('(:: bad LspOcc) (fn (bad) ' + record.replace('VALUE', 'nilNode') + ')', 'AX3004'),
            "integer-record-value": ('(:: bad LspOcc) (fn (bad) ' + record.replace('VALUE', '(Some 0)') + ')', 'AX3004'),
            "unchecked-value": ('(:: bad (-> LspOcc ASTNode)) (fn (bad o) o.value)', 'AX3004'),
            "missing-none": ('(:: bad (-> LspOcc Int)) (fn (bad o) (match o.value ((Some value) (nodeTag value))))', 'AX3005'),
            "raw-inference-query": ('(:: bad (-> ASTNode (Option String))) (fn (bad value) (lspFieldValueStruct value))', 'AX3004'),
        }
        for name, (declaration, code) in refusals.items():
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
                ("let-value-lost", "lspNavWalkLet", "(if (nodeSame value nilNode) None (Some value))", "None"),
                ("nonbinder-value-forged", "lspNavEmit", "idx None)", "idx (Some mkTErr))"),
                ("poison-presence-lost", "lspNavWalkLet", "(if (nodeSame value nilNode) None (Some value))",
                 "(if (|| (nodeSame value nilNode) (== (nodeTag value) TAG_T_ERR)) None (Some value))"),
                ("binder-inference-lost", "lspShapeOfBinder", "(lspShapeOf decls occs v 16)", "None"),
                ("variable-inference-lost", "lspShapeVar", "(lspShapeOf decls occs v (- fuel 1))", "None"),
                ("value-identity-copied", "lspNavEmitValue", ":value value",
                 ":value (match value ((None) None) ((Some child) (Some (nodeClone child))))"),
            )
            for name, function, old, new in controls:
                prefix = "(fn (" if function == "lspNavEmitValue" else "(pub fn ("
                start = original.index(prefix + function + " ")
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
                actual = native(name, dict(env, AXIOM_PATH=str(overlay)), 0)
                assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 31, (name, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   LSP occurrence values: 31 cases O0/O2 poison, exact editor output, five type/exhaustiveness refusals")


if __name__ == "__main__":
    main()
