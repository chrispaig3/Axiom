#!/usr/bin/env python3
"""Check optional LSP display shapes, substitution ownership and unchanged editor responses."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import tempfile

# Unchanged 15717d23: 24 hover/inlay/semantic scenarios against the pre-migration module set.
BASELINE = 'SOURCE (fn (f) { (let value 0) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value 0)\\nvalue : Int\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[{"position":{"line":0,"character":20},"label":": Int","kind":1}]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,6,1,12,0,0,3,5,4,0]}\nSOURCE (fn (f) { (let value ()) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value ())\\nvalue : ()\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[{"position":{"line":0,"character":20},"label":": ()","kind":1}]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,10,5,4,0]}\nSOURCE (fn (f) { (let value "") value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value \\"\\")\\nvalue : String\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[{"position":{"line":0,"character":20},"label":": String","kind":1}]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,6,2,11,0,0,4,5,4,0]}\nSOURCE (fn (f) { (let value 1.5) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value 1.5)\\nvalue : Float\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[{"position":{"line":0,"character":20},"label":": Float","kind":1}]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,6,3,12,0,0,5,5,4,0]}\nSOURCE (fn (f) { (let value true) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value true)\\nvalue : Bool\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[{"position":{"line":0,"character":20},"label":": Bool","kind":1}]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,6,4,9,64,0,6,5,4,0]}\nSOURCE (fn (f) { (let value (+ 1 2)) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value (+ 1 2))\\nvalue : Int\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[{"position":{"line":0,"character":20},"label":": Int","kind":1}]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,7,1,13,64,0,2,1,12,0,0,2,1,12,0,0,4,5,4,0]}\nSOURCE (fn (f) { (let value (< 1 2)) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value (< 1 2))\\nvalue : Bool\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[{"position":{"line":0,"character":20},"label":": Bool","kind":1}]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,7,1,13,64,0,2,1,12,0,0,2,1,12,0,0,4,5,4,0]}\nSOURCE (fn (f) { (let value (! true)) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value (! true))\\nvalue : (Bool -> Bool)\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[{"position":{"line":0,"character":20},"label":": (Bool -> Bool)","kind":1}]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,7,1,13,64,0,2,4,9,64,0,7,5,4,0]}\nSOURCE (fn (f) { (let value (if true 1 2)) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value (if true 1 2))\\nvalue : Int\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[{"position":{"line":0,"character":20},"label":": Int","kind":1}]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,7,2,9,0,0,3,4,9,64,0,5,1,12,0,0,2,1,12,0,0,4,5,4,0]}\nSOURCE (fn (f) { (let value (if true 1 ())) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value (if true 1 ()))\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,7,2,9,0,0,3,4,9,64,0,5,1,12,0,0,7,5,4,0]}\nSOURCE (fn (f) { (let value (if true () ())) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value (if true () ()))\\nvalue : ()\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[{"position":{"line":0,"character":20},"label":": ()","kind":1}]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,7,2,9,0,0,3,4,9,64,0,13,5,4,0]}\nSOURCE (fn (f) { (let value { 1 () }) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value { 1 () })\\nvalue : ()\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[{"position":{"line":0,"character":20},"label":": ()","kind":1}]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,8,1,12,0,0,8,5,4,0]}\nSOURCE (fn (f) { (let value (match 1 (1 2) (_ 3))) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value (match 1 (1 2) (_ 3)))\\nvalue : Int\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[{"position":{"line":0,"character":20},"label":": Int","kind":1}]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,7,5,9,0,0,6,1,12,0,0,3,1,12,0,0,2,1,12,0,0,6,1,12,0,0,5,5,4,0]}\nSOURCE (fn (f) { (let value (match 1 (1 2) (_ ()))) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value (match 1 (1 2) (_ ())))\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,7,5,9,0,0,6,1,12,0,0,3,1,12,0,0,2,1,12,0,0,12,5,4,0]}\nSOURCE (:: make (-> Int String)) (fn (make p) "") (fn (f) { (let value (make 1)) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value (make 1))\\nvalue : String\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":58},"end":{"line":0,"character":63}}}\n[{"position":{"line":0,"character":37},"label":": Int","kind":1},{"position":{"line":0,"character":38},"label":" -> String","kind":1},{"position":{"line":0,"character":63},"label":": String","kind":1},{"position":{"line":0,"character":70},"label":"p:","kind":2,"paddingRight":true}]\n{"data":[0,1,2,13,0,0,3,4,7,1,0,6,2,13,0,0,3,3,1,64,0,4,6,1,64,0,10,2,9,0,0,4,4,7,3,0,5,1,3,1,0,3,2,11,0,0,5,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,7,4,7,0,0,5,1,12,0,0,4,5,4,0]}\nSOURCE (:: make (-> Int String)) (fn (make p) "") (fn (f) { (let value make) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value make)\\nvalue : (Int -> String)\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":58},"end":{"line":0,"character":63}}}\n[{"position":{"line":0,"character":37},"label":": Int","kind":1},{"position":{"line":0,"character":38},"label":" -> String","kind":1},{"position":{"line":0,"character":63},"label":": (Int -> String)","kind":1}]\n{"data":[0,1,2,13,0,0,3,4,7,1,0,6,2,13,0,0,3,3,1,64,0,4,6,1,64,0,10,2,9,0,0,4,4,7,3,0,5,1,3,1,0,3,2,11,0,0,5,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,6,4,7,0,0,6,5,4,0]}\nSOURCE (:: make (-> Int Int String)) (fn (make p q) "") (fn (f) { (let value make) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value make)\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":64},"end":{"line":0,"character":69}}}\n[{"position":{"line":0,"character":41},"label":": Int","kind":1},{"position":{"line":0,"character":43},"label":": Int","kind":1},{"position":{"line":0,"character":44},"label":" -> String","kind":1}]\n{"data":[0,1,2,13,0,0,3,4,7,1,0,6,2,13,0,0,3,3,1,64,0,4,3,1,64,0,4,6,1,64,0,10,2,9,0,0,4,4,7,3,0,5,1,3,1,0,2,1,3,1,0,3,2,11,0,0,5,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,6,4,7,0,0,6,5,4,0]}\nSOURCE (pub struct Box (a) (item : a)) (fn (f) { (let value (Box 3)) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value (Box 3))\\nvalue : Box Int\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":47},"end":{"line":0,"character":52}}}\n[{"position":{"line":0,"character":52},"label":": Box Int","kind":1}]\n{"data":[0,1,3,9,0,0,4,6,9,0,0,7,3,1,1,0,5,1,2,0,0,4,4,5,1,0,7,1,2,0,0,5,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,7,3,6,0,0,4,1,12,0,0,4,5,4,0]}\nSOURCE (pub struct Box (a) (item : a)) (fn (f) { (let box (Box 3)) (let value box.item) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value box.item)\\nvalue : Int\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":65},"end":{"line":0,"character":70}}}\n[{"position":{"line":0,"character":50},"label":": Box Int","kind":1},{"position":{"line":0,"character":70},"label":": Int","kind":1}]\n{"data":[0,1,3,9,0,0,4,6,9,0,0,7,3,1,1,0,5,1,2,0,0,4,4,5,1,0,7,1,2,0,0,5,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,3,4,5,0,5,3,6,0,0,4,1,12,0,0,5,3,9,0,0,4,5,4,5,0,6,3,4,0,0,4,4,5,0,0,6,5,4,0]}\nSOURCE (pub data Choice (Stop) (More Int)) (fn (f) { (let value Stop) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value Stop)\\nvalue : Choice\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":51},"end":{"line":0,"character":56}}}\n[{"position":{"line":0,"character":56},"label":": Choice","kind":1}]\n{"data":[0,1,3,9,0,0,4,4,9,0,0,5,6,1,1,0,8,4,6,1,0,7,4,6,1,0,5,3,1,64,0,7,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,6,4,6,0,0,6,5,4,0]}\nSOURCE (pub data Choice a (Stop) (More a)) (fn (f) { (let value Stop) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value Stop)\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":51},"end":{"line":0,"character":56}}}\n[]\n{"data":[0,1,3,9,0,0,4,4,9,0,0,5,6,1,1,0,7,1,2,0,0,3,4,6,1,0,7,4,6,1,0,5,1,2,0,0,5,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,6,4,6,0,0,6,5,4,0]}\nSOURCE (fn (f) { (let value missing) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value missing)\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,6,7,4,0,0,9,5,4,0]}\nSOURCE (fn (f) { (let value (lambda (x) x)) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value (lambda (x) x))\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,7,6,9,0,0,8,1,3,1,0,3,1,3,0,0,4,5,4,0]}\nSOURCE (fn (f) { (let value (Peer::make 1)) value })\n{"contents":{"kind":"markdown","value":"```axiom\\n(let value (Peer::make 1))\\n```\\n\\nbound by `let` in `f`\\n"},"range":{"start":{"line":0,"character":15},"end":{"line":0,"character":20}}}\n[]\n{"data":[0,1,2,9,0,0,4,1,7,3,0,6,3,9,0,0,4,5,4,5,0,7,4,0,0,0,6,4,7,0,0,5,1,12,0,0,4,5,4,0]}\n'
EXPECTED = "".join(f"{i} true\n" for i in range(1, 112))


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
    fixture = root / "tests/selfhost/lsp-shape-result-options.axp"
    goldens = root / "tests/selfhost/lsp-shape-result-goldens.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    original = (root / "core/lsp.ax").read_text()
    with tempfile.TemporaryDirectory(prefix="axiom-lsp-shape-options-") as directory:
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
            print("ok   " + name + f": exact {len(BASELINE.encode())} bytes, 24 hover/inlay/semantic scenarios", flush=True)

        refusals = {
            "unchecked-builtin-row": ('(:: bad Int) (fn (bad) (lspShapeBuiltinRes "+"))', 'AX3004'),
            "unchecked-spine": ('(:: bad ASTNode) (fn (bad) (lspShapeSpine mkIntTy vecNew))', 'AX3004'),
            "unchecked-field-types": ('(:: bad Nodes) (fn (bad) (lspShapeFieldTys vecNew 0 vecNew))', 'AX3004'),
            "unchecked-arrow": ('(:: bad ASTNode) (fn (bad) (lspShapeApplyArrow mkIntTy 0))', 'AX3004'),
            "unchecked-builtin": ('(:: bad ASTNode) (fn (bad) (lspShapeBuiltinTy "+" 2))', 'AX3004'),
            "unchecked-binding": ('(:: bad ASTNode) (fn (bad) (lspShapeBindGet vecNew "a"))', 'AX3004'),
            "unchecked-index": ('(:: bad Int) (fn (bad) (lspShapeParamAt vecNew "a" 0))', 'AX3004'),
            "unchecked-constructor": ('(:: bad ASTNode) (fn (bad) (lspShapeConBuild "Box" vecNew vecNew 0 vecNew))', 'AX3004'),
            "unchecked-substitution": ('(:: bad ASTNode) (fn (bad) (lspShapeSubst mkIntTy vecNew vecNew))', 'AX3004'),
            "unchecked-vector": ('(:: bad Nodes) (fn (bad) (lspShapeSubstVec vecNew vecNew vecNew 0 vecNew))', 'AX3004'),
            "unchecked-expression": ('(:: bad ASTNode) (fn (bad) (lspShapeOf vecNew vecNew (mkEInt 0) 16))', 'AX3004'),
            "raw-binding-input": ('(:: bad Int) (fn (bad) (lspShapeBind mkIntTy mkIntTy vecNew vecNew))', 'AX3004'),
            "raw-join-input": ('(:: bad (Option ASTNode)) (fn (bad) (lspShapeJoin mkIntTy None))', 'AX3004'),
            "wrong-option-payload": ('(:: bad Int) (fn (bad) (lspShapeBind mkIntTy (Some 0) vecNew vecNew))', 'AX3004'),
            "missing-none": ('(:: bad Bool) (fn (bad) (match (lspShapeOf vecNew vecNew (mkEInt 0) 16) ((Some node) true)))', 'AX3005'),
            "missing-some": ('(:: bad Bool) (fn (bad) (match (lspShapeBindGet vecNew "a") ((None) false)))', 'AX3005'),
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
                ("builtin-first-row-lost", "lspShapeBuiltinRes", '(if (strEq h "+") (Some 1)', '(if (strEq h "+") None'),
                ("spine-presence-lost", "lspShapeSpine", "(lspShapeNodeOpt h)", "None"),
                ("missing-field-type-forged", "lspShapeFieldTys", "((None) None)", "((None) (Some acc))"),
                ("arrow-success-lost", "lspShapeApplyArrow", "(Some ty)", "None"),
                ("builtin-absence-forged", "lspShapeBuiltinTy", "((None) None)", "((None) (Some mkIntTy))"),
                ("valid-zero-index-lost", "lspShapeParamAt", "(Some i)", "None"),
                ("binding-identity-copied", "lspShapeBindGetIn", "(Some binding.ty)", "(Some (nodeClone binding.ty))"),
                ("binding-contradiction-lost", "lspShapeBind", "(if (strEq (tyRender old) (tyRender arg)) 1 0)", "1"),
                ("unbound-constructor-forged", "lspShapeConBuild", "((None) None)", "((None) (Some (mkTCon tname acc)))"),
                ("substitution-presence-lost", "lspShapeSubst", "(Some arg)", "None"),
                ("empty-substitution-lost", "lspShapeSubstVec", "(Some acc)", "None"),
                ("join-mismatch-forged", "lspShapeJoin", "(if (strEq (tyRender a) (tyRender b)) (Some a) None)", "(Some a)"),
                ("block-result-order-changed", "lspShapeBegin", "(vecGet xs (- (vecLen xs) 1))", "(vecGet xs 0)"),
                ("match-success-lost", "lspShapeMatchIn", "(if (>= i (vecLen arms)) acc", "(if (>= i (vecLen arms)) None"),
                ("field-substitution-lost", "lspShapeField", "(lspShapeSubst ft ps args)", "None"),
            )
            for name, function, old, new in controls:
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
                actual = native(name, dict(env, AXIOM_PATH=str(overlay)), 0)
                assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 111, (name, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   LSP display shape Options: 111 cases O0/O2 poison, exact editor bytes, sixteen type/exhaustiveness refusals")


if __name__ == "__main__":
    main()
