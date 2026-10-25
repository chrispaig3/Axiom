#!/usr/bin/env python3
"""Check LSP workspace read observations and optional module paths."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


EXPECTED = "".join(f"{number} true\n" for number in range(1, 36))
PRESENT = '(pub :: value Int)\n(pub fn (value) 7)\n'


def execute(arguments, env):
    return subprocess.run(arguments, env=env, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = (root / "tests/selfhost/lsp-workspace-read-options.axp").read_text()
    original = (root / "core/lsp.ax").read_text()
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))

    with tempfile.TemporaryDirectory(prefix="axiom-lsp-workspace-read-options-") as directory:
        work = Path(directory)

        def native(name, local, level):
            files = work / (name + "-files")
            files.mkdir()
            (files / "Empty.ax").write_text("")
            (files / "Present.ax").write_text(PRESENT)
            (files / "Blocked.ax").mkdir()  # readFile on a directory is Err on every host.
            (files / "MoreEmpty.ax").write_text("")
            (files / "Never.ax").mkdir()
            source = work / (name + ".ax")
            source.write_text(fixture.replace('"__WORKSPACE__"', json.dumps(str(files))))
            binary = work / name
            built = execute([compiler, "--diagnostic-format=ai", "build", str(source),
                             "--opt", str(level), "--alloc-poison", "-o", str(binary)], local)
            assert built.returncode == 0, (name, built.returncode, built.stdout, built.stderr)
            ran = execute([str(binary)], local)
            assert ran.returncode == 0 and not ran.stderr, (name, ran.returncode, ran.stdout, ran.stderr)
            return ran.stdout

        for level in (0, 2):
            name = f"positive-O{level}"
            actual = native(name, env, level)
            assert actual == EXPECTED, (name, actual)
            print(f"ok   {name}: 35 workspace observations", flush=True)

        refusals = {
            "raw-file": ("String", '(lspWorkspaceFile (lspWorkspaceNew vecNew vecNew vecNew) "/missing")', "AX3004"),
            "raw-path": ("String", '(lspWorkspaceModulePath (lspWorkspaceNew vecNew vecNew vecNew) "Missing" 0 "/")', "AX3004"),
            "missing-file-err": ("Bool", '(match (lspWorkspaceFile (lspWorkspaceNew vecNew vecNew vecNew) "/missing") ((Some text) true))', "AX3005"),
            "missing-path-some": ("Bool", '(match (lspWorkspaceModulePath (lspWorkspaceNew vecNew vecNew vecNew) "Missing" 0 "/") ((None) false))', "AX3005"),
        }
        for name, (return_type, expression, code) in refusals.items():
            source = work / (name + ".ax")
            source.write_text("(import core)\n(import lsp)\n"
                              f"(:: bad {return_type})\n;@axiom:effect(io)\n"
                              f"(fn (bad) {expression})\n"
                              "(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print(f"ok   {name}: {code}", flush=True)

        if args.negative_controls:
            controls = (
                ("missing-forged-empty", "lspWorkspaceFile", "((Err _) None)", '((Err _) (Some ""))'),
                ("empty-read-lost", "lspWorkspaceFile", "((Ok src) (Some src))",
                 '((Ok src) (if (== (strLen src) 0) None (Some src)))'),
                ("observation-collapsed", "lspCacheInputs", "((None) jsonNull)", '((None) (jsonStr ""))'),
                ("deleted-empty-accepted", "lspCacheInputsCurrent", "((Err _) (jsonIsNull expected))",
                 '((Err _) (|| (jsonIsNull expected) (strEq (jsonStrVal expected) "")))'),
                ("empty-module-lost", "lspWorkspaceModulePath",
                 "(isSome (lspWorkspaceFile workspace candidate))",
                 '(if (let (Some text) (lspWorkspaceFile workspace candidate)) (> (strLen text) 0) false)'),
            )
            for name, function, old, new in controls:
                start = original.index("(pub fn (" + function + " ")
                end = original.index("\n\n", start)
                body = original[start:end]
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
                assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 35, (
                    name, actual)
                print(f"ok   {name}: effective mutation", flush=True)

    print("ok   LSP workspace reads: 35 O0/O2 cases, four refusals")


if __name__ == "__main__":
    main()
