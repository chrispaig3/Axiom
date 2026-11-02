#!/usr/bin/env python3
"""Check optional hierarchy searches, ownership and unchanged editor responses."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import tempfile

# Unchanged 4ee86a21: eight sources, three hierarchy responses each, including a virtual import.
BASELINE = 'SOURCE empty\nnull\nnull\nnull\nSOURCE struct\n[{"name":"Box","kind":23,"detail":"struct","uri":"file:///tmp/axiom-hierarchy-fixtures/Main.ax","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":26}},"selectionRange":{"start":{"line":0,"character":8},"end":{"line":0,"character":11}}}]\n[]\n[]\nSOURCE builtin\n[{"name":"Int","kind":5,"detail":"builtin type","uri":"file:///tmp/axiom-hierarchy-fixtures/Main.ax","range":{"start":{"line":0,"character":21},"end":{"line":0,"character":24}},"selectionRange":{"start":{"line":0,"character":21},"end":{"line":0,"character":24}}}]\n[]\n[{"name":"Positive","kind":5,"detail":"subtype of Int","uri":"file:///tmp/axiom-hierarchy-fixtures/Main.ax","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":39}},"selectionRange":{"start":{"line":0,"character":9},"end":{"line":0,"character":17}}},{"name":"Tiny","kind":5,"detail":"subtype of Int","uri":"file:///tmp/axiom-hierarchy-fixtures/Main.ax","range":{"start":{"line":1,"character":0},"end":{"line":1,"character":34}},"selectionRange":{"start":{"line":1,"character":9},"end":{"line":1,"character":13}}}]\nSOURCE subtype\n[{"name":"Positive","kind":5,"detail":"subtype of Int","uri":"file:///tmp/axiom-hierarchy-fixtures/Main.ax","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":39}},"selectionRange":{"start":{"line":0,"character":9},"end":{"line":0,"character":17}}}]\n[{"name":"Int","kind":5,"detail":"builtin type","uri":"file:///tmp/axiom-hierarchy-fixtures/Main.ax","range":{"start":{"line":0,"character":21},"end":{"line":0,"character":24}},"selectionRange":{"start":{"line":0,"character":21},"end":{"line":0,"character":24}}}]\n[]\nSOURCE missing\nnull\nnull\nnull\nSOURCE imported\n[{"name":"Box","kind":23,"detail":"struct","uri":"file:///tmp/axiom-hierarchy-fixtures/Peer.ax","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":30}},"selectionRange":{"start":{"line":0,"character":12},"end":{"line":0,"character":15}}}]\nnull\nnull\nSOURCE alias\n[{"name":"Alias","kind":5,"detail":"type","uri":"file:///tmp/axiom-hierarchy-fixtures/Main.ax","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":16}},"selectionRange":{"start":{"line":0,"character":6},"end":{"line":0,"character":11}}}]\n[]\n[]\nSOURCE recovered\n[{"name":"Positive","kind":5,"detail":"subtype of Int","uri":"file:///tmp/axiom-hierarchy-fixtures/Main.ax","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":39}},"selectionRange":{"start":{"line":0,"character":9},"end":{"line":0,"character":17}}}]\n[{"name":"Int","kind":5,"detail":"builtin type","uri":"file:///tmp/axiom-hierarchy-fixtures/Main.ax","range":{"start":{"line":0,"character":21},"end":{"line":0,"character":24}},"selectionRange":{"start":{"line":0,"character":21},"end":{"line":0,"character":24}}}]\n[]\n'
EXPECTED = "".join(f"{i} true\n" for i in range(1, 26))


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
    fixture = root / "tests/selfhost/lsp-hierarchy-query-options.axp"
    goldens = root / "tests/selfhost/lsp-hierarchy-query-goldens.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    original = (root / "core/lsp.ax").read_text()
    with tempfile.TemporaryDirectory(prefix="axiom-lsp-hierarchy-options-") as directory:
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
            print("ok   " + name + ": exact 2812 bytes, hierarchy builtins and local/imported types", flush=True)

        refusals = {
            "unchecked-type": ('(:: bad ASTNode) (fn (bad) (lspThFindType vecNew "T" -1))', 'AX3004'),
            "unchecked-imported-type": ('(:: bad ASTNode) (fn (bad) (lspThFindImportedType vecNew "T" -1))', 'AX3004'),
            "missing-none": ('(:: bad Bool) (fn (bad) (match (lspThFindType vecNew "T" -1) ((Some node) true)))', 'AX3005'),
            "missing-some": ('(:: bad Bool) (fn (bad) (match (lspThFindImportedType vecNew "T" -1) ((None) false)))', 'AX3005'),
            "raw-subject-declaration": ('(:: bad LspHierSubject) (fn (bad) (LspHierSubject :uri "" :name "" :src "" :decls vecNew :decl nilNode))', 'AX3004'),
            "unchecked-subject-declaration": ('(:: bad (-> LspHierSubject ASTNode)) (fn (bad subject) subject.decl)', 'AX3004'),
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
                ("type-result-lost", "lspThFindType", "(Some d)", "None", False),
                ("type-kind-filter-lost", "lspThFindType", "(lspThIsTypeTag (nodeTag d))", "true", False),
                ("import-name-match-lost", "lspThFindImportedType", "(bareOf (nodeAName d))", "(nodeAName d)", False),
                ("import-span-filter-lost", "lspThFindImportedType", "(!= (nodeSpan d) 0)", "true", False),
                ("builtin-subject-lost", "lspThSubject", "(lspThBuiltin name)", "false", False),
                ("declared-subject-lost", "lspThSubject", ":decl d", ":decl None", False),
                ("call-subject-declaration-lost", "lspChSubject", ":decl (Some d)", ":decl None", False),
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
                    assert actual != BASELINE and actual.count("SOURCE ") == 8 and len(actual.splitlines()) == len(BASELINE.splitlines()), (name, actual)
                else:
                    assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 25, (name, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   LSP hierarchy queries: 25 cases O0/O2 poison, exact editor output, six type/exhaustiveness refusals")


if __name__ == "__main__":
    main()
