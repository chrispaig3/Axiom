#!/usr/bin/env python3
"""Check LSP absence values, their callers, and refusal of unchecked use."""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile


EXPECTED = "".join(f"{number} true\n" for number in range(1, 27))


def execute(arguments, env):
    return subprocess.run(arguments, env=env, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/selfhost/lsp-cache-sync-import-options.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    original = (root / "core/lsp.ax").read_text()

    with tempfile.TemporaryDirectory(prefix="axiom-lsp-cache-sync-import-options-") as directory:
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
            print(f"ok   {name}: 26 typed LSP cases", flush=True)

        # The compiler must reject consumers that silently treat an Option
        # as its payload, and require both arms when the value is matched.
        refusals = {
            "import-path": ("String", '(lspImportPathAt "(import " 8)', "AX3004"),
            "module-name": ("String", '(lspModOf "Vec$push")', "AX3004"),
            "preflight": ("String", '(lspPreflight vecNew 0 "." vecNew)', "AX3004"),
            "cache-result": ("String", '(lspCacheFind vecNew "D-key")', "AX3004"),
            "cache-victim": ("Int", "(lspCacheVictim vecNew true)", "AX3004"),
            "sync-offset": ("Int", '(lspSyncOffset "" (lspLineIndex "") (jsonParse "{}"))', "AX3004"),
            "missing-none": ("Bool", '(match (lspModOf "A$x") ((Some value) true))', "AX3005"),
            "missing-some": ("Bool", '(match (lspImportPathAt "plain" 5) ((None) false))', "AX3005"),
        }
        for name, (return_type, expression, code) in refusals.items():
            source = work / f"{name}.ax"
            effect = ";@axiom:effect(io)\n" if name in ("preflight", "cache-result") else ""
            source.write_text("(import core)\n(import lsp)\n(import Cereal)\n"
                              f"(:: bad {return_type})\n{effect}"
                              f"(fn (bad) {expression})\n"
                              "(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print(f"ok   {name}: {code}", flush=True)

        if args.negative_controls:
            # Each scoped mutation must compile, run, and make a relevant
            # positive case fail. Source files in the checkout stay intact.
            controls = (
                ("import-empty-lost", "lspImportPathAt", "(Some (strSlice src s (- e s)))", "None"),
                ("module-prefix-lost", "lspModOfFrom", "(Some (strSlice s 0 i))", "None"),
                ("preflight-missing-lost", "lspPreflight", "(set missing (Some name))", "(set missing None)"),
                ("cache-hit-lost", "lspCacheFind", '(set result (Some (jsonGetStr entry "result")))', "(set result None)"),
                ("cache-victim-lost", "lspCacheVictim", "(Some 0)", "None"),
                ("sync-zero-lost", "lspSyncOffset", "(Some i)", "None"),
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
                assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 26, (
                    name, actual)
                print(f"ok   {name}: effective mutation", flush=True)

    print("ok   LSP cache/sync/import Options: 26 O0/O2 cases, eight refusals")


if __name__ == "__main__":
    main()
