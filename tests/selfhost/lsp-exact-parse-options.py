#!/usr/bin/env python3
"""Check exact parse presence and unchanged loss-sensitive rename edits."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

# Unchanged 3d1f7937: empty, clean/additive/lossy recovery, collision and top rename.
BASELINE = 'SOURCE \nnull\nnull\nSOURCE (fn (identity x) x)\n{"range":{"start":{"line":0,"character":14},"end":{"line":0,"character":15}},"placeholder":"x"}\n{"changes":{"file:///tmp/exact.ax":[{"range":{"start":{"line":0,"character":14},"end":{"line":0,"character":15}},"newText":"value"},{"range":{"start":{"line":0,"character":17},"end":{"line":0,"character":18}},"newText":"value"}]}}\nSOURCE (fn (identity x) x\n{"range":{"start":{"line":0,"character":14},"end":{"line":0,"character":15}},"placeholder":"x"}\n{"changes":{"file:///tmp/exact.ax":[{"range":{"start":{"line":0,"character":14},"end":{"line":0,"character":15}},"newText":"value"},{"range":{"start":{"line":0,"character":17},"end":{"line":0,"character":18}},"newText":"value"}]}}\nSOURCE (fn (identity x) x) @\nnull\nnull\nSOURCE (fn (identity x) { (let value 1) x })\n{"range":{"start":{"line":0,"character":14},"end":{"line":0,"character":15}},"placeholder":"x"}\nnull\nSOURCE (fn (identity x) x) (fn (second) 2)\n{"range":{"start":{"line":0,"character":5},"end":{"line":0,"character":13}},"placeholder":"identity"}\n{"changes":{"file:///tmp/exact.ax":[{"range":{"start":{"line":0,"character":5},"end":{"line":0,"character":13}},"newText":"value"}]}}\n'
EXPECTED = "".join(f"{i} true\n" for i in range(1, 21))


def execute(arguments, env):
    return subprocess.run(arguments, env=env, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/selfhost/lsp-exact-parse-options.axp"
    goldens = root / "tests/selfhost/lsp-exact-parse-goldens.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    original = (root / "core/lsp.ax").read_text()
    with tempfile.TemporaryDirectory(prefix="axiom-lsp-exact-options-") as directory:
        work = Path(directory)

        def native(name, local, level, source=fixture):
            binary = work / name
            built = execute([compiler, "--diagnostic-format=ai", "build", str(source),
                             "--opt", str(level), "--alloc-poison", "-o", str(binary)], local)
            assert built.returncode == 0, (name, built.returncode, built.stdout, built.stderr)
            ran = execute([str(binary)], local)
            assert ran.returncode == 0 and not ran.stderr, (name, ran.returncode, ran.stdout, ran.stderr)
            return ran.stdout

        for level in (0, 2):
            name = "positive-O" + str(level)
            actual = native(name, env, level)
            assert actual == EXPECTED, (name, actual)
            print("ok   " + name, flush=True)
            name = "rename-bytes-O" + str(level)
            actual = native(name, env, level, goldens)
            assert actual == BASELINE, (name, actual)
            print("ok   " + name + ": exact 1189-byte baseline", flush=True)

        refusals = {
            "unchecked-declarations": ('(:: bad (-> String Nodes)) (fn (bad source) (lspNavParseExact source))', 'AX3004'),
            "missing-none": ('(:: bad (-> String Int)) (fn (bad source) (match (lspNavParseExact source) '
                             '((Some declarations) (vecLen declarations))))', 'AX3005'),
            "wrong-present-payload": ('(:: bad (-> String (Option ASTNode))) '
                                      '(fn (bad source) (lspNavParseExact source))', 'AX3004'),
        }
        for name, (declaration, code) in refusals.items():
            source = work / (name + ".ax")
            source.write_text("(import core)\n(import lsp)\n(import Vec)\n" + declaration +
                              "\n(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print("ok   " + name + ": " + code, flush=True)

        if args.negative_controls:
            controls = (
                ("present-lost", "lspNavParseExact", "(Some declarations)", "None"),
                ("empty-presence-lost", "lspNavParseExact", "(== position (- 0 2))",
                 "(|| (== position (- 0 2)) (== (vecLen declarations) 0))"),
                ("lossy-accepted", "lspNavParseExact", "(== position (- 0 2))", "(== position (- 0 3))"),
                ("prepare-loss-guard-lost", "lspPrepareRename", "(lspNavParseExact src)", "(Some (lspNavParse src))"),
                ("rename-loss-guard-lost", "lspRename", "(lspNavParseExact src)", "(Some (lspNavParse src))"),
            )
            for name, function, old, new in controls:
                start = original.index("(pub fn (" + function + " ")
                end = original.index("\n\n", start)
                body = original[start:end]
                assert body.count(old) == 1, (name, body.count(old))
                changed = original[:start] + body.replace(old, new) + original[end:]
                overlay = work / (name + "-core/core")
                overlay.mkdir(parents=True)
                for path in (root / "core").iterdir():
                    if path.name == "lsp.ax":
                        (overlay / path.name).write_text(changed)
                    else:
                        (overlay / path.name).symlink_to(path, target_is_directory=path.is_dir())
                actual = native(name, dict(env, AXIOM_PATH=str(overlay)), 0)
                assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 20, (name, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   LSP exact parse: 20 cases O0/O2 poison, exact edits, three type/exhaustiveness refusals")


if __name__ == "__main__":
    main()
