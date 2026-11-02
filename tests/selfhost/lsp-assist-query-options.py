#!/usr/bin/env python3
"""Check optional assist and indexed declaration searches, ownership and unchanged editor responses."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import tempfile

# Unchanged 063eebd6: eight labelled editor scenarios and their exact responses.
BASELINE = 'CASE signed\n[{"position":{"line":1,"character":11},"label":": Int","kind":1},{"position":{"line":1,"character":13},"label":": Int","kind":1},{"position":{"line":1,"character":14},"label":" -> Int","kind":1},{"position":{"line":2,"character":16},"label":"x:","kind":2,"paddingRight":true},{"position":{"line":2,"character":18},"label":"y:","kind":2,"paddingRight":true}]\n{"data":[0,1,2,13,0,0,3,4,7,1,0,6,2,13,0,0,3,3,1,64,0,4,3,1,64,0,4,3,1,64,1,1,2,9,0,0,4,4,7,3,0,5,1,3,1,0,2,1,3,1,0,4,1,13,64,0,2,1,3,0,0,2,1,3,0,1,1,2,9,0,0,4,3,7,3,0,6,4,7,0,0,5,1,12,0,0,2,1,12,0]}\n[{"title":"Add type signature for `use`","kind":"refactor.rewrite","edit":{"changes":{"file:///tmp/axiom-assist-fixtures/Main.ax":[{"range":{"start":{"line":2,"character":0},"end":{"line":2,"character":0}},"newText":"(:: use Int)\\n"}]}}}]\nCASE unsigned\n[{"position":{"line":1,"character":17},"label":"x:","kind":2,"paddingRight":true}]\n{"data":[0,1,2,9,0,0,4,5,7,3,0,6,1,3,1,0,4,1,13,64,0,2,1,3,0,0,2,1,12,0,1,1,2,9,0,0,4,3,7,3,0,6,5,7,0,0,6,1,12,0]}\n[{"title":"Add type signature for `value`","kind":"refactor.rewrite","edit":{"changes":{"file:///tmp/axiom-assist-fixtures/Main.ax":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"newText":"(:: value (-> Int Int))\\n"}]}}},{"title":"Add type signature for `use`","kind":"refactor.rewrite","edit":{"changes":{"file:///tmp/axiom-assist-fixtures/Main.ax":[{"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":0}},"newText":"(:: use Int)\\n"}]}}}]\nCASE unresolved\n[]\n{"data":[0,1,2,9,0,0,4,5,7,3,0,7,7,4,0]}\n[]\nCASE imports\n{"changes":{"file:///tmp/axiom-assist-fixtures/Main.ax":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"newText":"(import Peer (value))\\n"}]}}\nnull\n{"changes":{"file:///tmp/axiom-assist-fixtures/Main.ax":[{"range":{"start":{"line":0,"character":18},"end":{"line":0,"character":18}},"newText":"\\n(import Peer (value))"}]}}\n{"contents":{"kind":"markdown","value":"```axiom\\n(import Peer)\\n```\\n\\n*module* `/tmp/axiom-assist-fixtures/Peer.ax`\\n"},"range":{}}\nnull\nCASE lint\n[{"title":"Suppress `lint-unused-let` on `value`","kind":"quickfix","diagnostics":[{"range":{"start":{"line":0,"character":19},"end":{"line":0,"character":25}},"severity":4,"code":"lint-unused-let","source":"axiom","message":"`unused` is bound here and never read"}],"edit":{"changes":{"file:///tmp/axiom-assist-fixtures/Main.ax":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"newText":";@axiom:nolint(lint-unused-let)\\n"}]}}}]\n[]\nCASE effect\n[{"title":"Treat unhandled `Stop` as a deliberate abort","kind":"quickfix","diagnostics":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":36}},"severity":2,"code":"AX3053","source":"axiom","message":"unhandled effect `Stop`"}],"edit":{"changes":{"file:///tmp/axiom-assist-fixtures/Main.ax":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"newText":";@axiom:unhandled(trap)\\n"}]}}}]\n[]\nCASE public\n[{"title":"Make `value` public in `Peer`","kind":"quickfix","diagnostics":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}},"severity":2,"code":"AX3023","source":"axiom","message":"`Peer` does not export `value`"}],"edit":{"changes":{"file:///tmp/axiom-assist-fixtures/Peer.ax":[{"range":{"start":{"line":0,"character":1},"end":{"line":0,"character":1}},"newText":"pub "}]}}}]\n[]\nCASE extract\n{"title":"Extract to `let`","kind":"refactor.extract","edit":{"changes":{"file:///tmp/axiom-assist-fixtures/Main.ax":[{"range":{"start":{"line":0,"character":12},"end":{"line":0,"character":19}},"newText":"{ (let extracted (+ 1 2)) extracted }"}]}}}\nnull\n'
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
    fixture = root / "tests/selfhost/lsp-assist-query-options.axp"
    goldens = root / "tests/selfhost/lsp-assist-query-goldens.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    original = (root / "core/lsp.ax").read_text()
    with tempfile.TemporaryDirectory(prefix="axiom-lsp-assist-options-") as directory:
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
            print("ok   " + name + ": exact 3681 bytes, inlay/semantic/assists/imports/extraction", flush=True)

        refusals = {
            "unchecked-indexed-node": ('(:: bad ASTNode) (fn (bad) (lspViewIdxFind lspViewIdxNew "x"))', 'AX3004'),
            "unchecked-lint-owner": ('(:: bad ASTNode) (fn (bad) (lspLintOwnerDecl vecNew "x" 0))', 'AX3004'),
            "unchecked-effect": ('(:: bad ASTNode) (fn (bad) (lspFindEffect vecNew "E" -1))', 'AX3004'),
            "unchecked-import": ('(:: bad ASTNode) (fn (bad) (lspFixFindImport vecNew "M" -1))', 'AX3004'),
            "unchecked-last-import": ('(:: bad ASTNode) (fn (bad) (lspFixLastImport vecNew -1))', 'AX3004'),
            "unchecked-module-decl": ('(:: bad ASTNode) (fn (bad) (lspFixDeclIn vecNew "M" "f" -1))', 'AX3004'),
            "unchecked-function-decl": ('(:: bad ASTNode) (fn (bad) (lspFixFnDeclIn vecNew 0 0 0))', 'AX3004'),
            "unchecked-form-offset": ('(:: bad Int) (fn (bad) (lspFixFnFormAt "" vecNew 0 0))', 'AX3004'),
            "raw-header-signature": ('(:: bad Int) (fn (bad) (lspViewHintsHeader 0 "" vecNew nilNode nilNode 0 0))', 'AX3004'),
            "missing-none": ('(:: bad Bool) (fn (bad) (match (lspViewIdxFind lspViewIdxNew "x") ((Some node) true)))', 'AX3005'),
            "missing-some": ('(:: bad Bool) (fn (bad) (match (lspFixFindImport vecNew "M" -1) ((None) false)))', 'AX3005'),
            "wrong-bucket-elements": ('(:: bad (Option ASTNode)) (fn (bad) (lspViewIdxFind (vecPush vecNew 1) "x"))', 'AX3004'),
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
                ("local-preference-lost", "lspViewIdxFind", "(if (isSome local) local other)", "other", False),
                ("lint-winner-changed", "lspLintOwnerDecl", "(Some d)", "(Some (vecGet decls (- (vecLen decls) 1)))", False),
                ("effect-kind-filter-lost", "lspFindEffect", "(== (nodeTag d) TAG_D_EFFECT)", "true", False),
                ("import-result-lost", "lspFixFindImport", "(Some d)", "None", False),
                ("last-import-order-changed", "lspFixLastImport", "(Some d)", "(Some (vecGet decls 0))", False),
                ("module-filter-lost", "lspFixDeclIn", "(strEq (nodeModuleName d) mod)", "true", False),
                ("function-upper-bound-changed", "lspFixFnDeclIn", "(< (spanStart (nodeSpan d)) e)", "(<= (spanStart (nodeSpan d)) e)", False),
                ("valid-zero-form-lost", "lspFixFnFormAt", "(Some o)", "None", False),
                ("header-hints-lost", "lspViewHintsHeader", '(lspViewHint out src ix e (concat ": " (tyRender pt)) 1 0 rs re)', "0", False),
                ("missing-signature-offer-lost", "lspSigAssists", "(isNone (lspViewIdxFind sigs (nodeAName d)))", "(isSome (lspViewIdxFind sigs (nodeAName d)))", True),
                ("semantic-kind-lost", "lspHlDeclClass", "(nodeTag d)", "TAG_D_ALIAS", True),
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
                    assert actual != BASELINE and actual.count("CASE ") == 8 and len(actual.splitlines()) == len(BASELINE.splitlines()), (name, actual)
                else:
                    assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 58, (name, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   LSP assist and indexed declaration queries: 58 cases O0/O2 poison, exact editor output, twelve type/exhaustiveness refusals")


if __name__ == "__main__":
    main()
