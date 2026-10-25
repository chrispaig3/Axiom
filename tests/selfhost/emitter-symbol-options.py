#!/usr/bin/env python3
"""Check symbol absence, shadowing, emission consumers and typed refusals."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def execute(command, environment):
    return subprocess.run(command, env=environment, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    environment = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    fixture = root / "tests/selfhost/1048-codegen-symbol-options.ax"
    expected = "".join(f"{i} true\n" for i in range(1, 32))
    with tempfile.TemporaryDirectory(prefix="axiom-symbol-options-") as directory:
        work = Path(directory)
        for level in (0, 2):
            binary = work / f"positive-O{level}"
            built = execute([compiler, "--diagnostic-format=ai", "build", str(fixture),
                             "--opt", str(level), "--alloc-poison", "-o", str(binary)], environment)
            assert built.returncode == 0, (level, built.returncode, built.stdout, built.stderr)
            ran = execute([str(binary)], environment)
            assert ran.returncode == 73 and ran.stdout == expected and not ran.stderr, (
                level, ran.returncode, ran.stdout, ran.stderr)
            print(f"ok   symbol Options: 31 outcomes at O{level} with allocation poisoning", flush=True)

        refusals = [
            ("raw-index", "Int", '(symIndex newCG "missing")', "AX3004"),
            ("raw-scan", "Int", '(symIndexIn vecNew "missing" (- 0 1))', "AX3004"),
            ("unchecked-register", "String", '(symRegAt newCG (symIndex newCG "missing"))', "AX3004"),
            ("missing-none", "Int", '(match (symIndex newCG "missing") ((Some index) index))', "AX3005"),
        ]
        for name, result_type, expression, code in refusals:
            source = work / f"{name}.ax"
            source.write_text("(import codegen)\n(import Vec)\n"
                              f"(:: bad {result_type})\n(fn (bad) {expression})\n"
                              "(:: main Int)\n(fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], environment)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print(f"ok   {name}: {code}", flush=True)


if __name__ == "__main__":
    main()
