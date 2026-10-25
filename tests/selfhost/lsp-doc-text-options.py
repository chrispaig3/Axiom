#!/usr/bin/env python3
"""Check missing versus empty LSP document text and typed refusals."""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile


EXPECTED = "".join(f"{number} true\n" for number in range(1, 7))


def execute(arguments, env):
    return subprocess.run(arguments, env=env, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/selfhost/lsp-doc-text-options.axp"
    original = (root / "core/lsp.ax").read_text()
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    with tempfile.TemporaryDirectory(prefix="axiom-lsp-doc-text-options-") as directory:
        work = Path(directory)

        def native(name, local, level):
            binary = work / name
            built = execute([compiler, "--diagnostic-format=ai", "build", str(fixture),
                             "--opt", str(level), "--alloc-poison", "-o", str(binary)], local)
            assert built.returncode == 0, (name, built.returncode, built.stdout, built.stderr)
            ran = execute([str(binary)], local)
            assert ran.returncode == 0 and not ran.stderr, (name, ran.returncode, ran.stdout, ran.stderr)
            return ran.stdout

        for level in (0, 2):
            name = f"positive-O{level}"
            actual = native(name, env, level)
            assert actual == EXPECTED, (name, actual)
            print(f"ok   {name}: six document presence cases", flush=True)

        for name, expression, code in (
            ("unchecked-source", '(docText vecNew vecNew "file:///unknown.ax")', "AX3004"),
            ("missing-none", '(match (docText vecNew vecNew "file:///unknown.ax") ((Some src) true))', "AX3005"),
            ("missing-some", '(match (docText vecNew vecNew "file:///unknown.ax") ((None) false))', "AX3005"),
        ):
            source = work / (name + ".ax")
            return_type = "String" if name == "unchecked-source" else "Bool"
            source.write_text("(import core)\n(import lsp)\n"
                              f"(:: bad {return_type})\n(fn (bad) {expression})\n"
                              "(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print(f"ok   {name}: {code}", flush=True)

        if args.negative_controls:
            start = original.index("(pub fn (docText ")
            end = original.index("\n\n", start)
            body = original[start:end]
            controls = (
                ("missing-forged", "(< i 0)\n      None", '(< i 0)\n      (Some "")'),
                ("empty-lost", "(Some (vecGet texts i))",
                 '(if (== (strLen (vecGet texts i)) 0) None (Some (vecGet texts i)))'),
                ("present-erased", "(Some (vecGet texts i))", '(Some "")'),
            )
            for name, old, new in controls:
                assert body.count(old) == 1, (name, body.count(old))
                changed = original[:start] + body.replace(old, new) + original[end:]
                overlay = work / (name + "-core")
                overlay.mkdir()
                for path in (root / "core").iterdir():
                    target = overlay / path.name
                    if path.name == "lsp.ax":
                        target.write_text(changed)
                    else:
                        target.symlink_to(path, target_is_directory=path.is_dir())
                actual = native(name, dict(env, AXIOM_PATH=str(overlay)), 0)
                assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 6, (
                    name, actual)
                print(f"ok   {name}: effective mutation", flush=True)

    print("ok   LSP document text: six O0/O2 cases, three refusals")


if __name__ == "__main__":
    main()
