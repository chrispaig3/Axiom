#!/usr/bin/env python3
"""Check exhaustive REPL load reads without changing its file-error output."""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def execute(argv, env):
    return subprocess.run(argv, env=env, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", required=True, type=Path)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    fixture = root / "tests/selfhost/repl-load-result.axp"
    compiler = str(args.axiom.resolve())
    original = (root / "core/repl.ax").read_text()
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))

    with tempfile.TemporaryDirectory(prefix="axiom-repl-load-result-") as directory:
        work = Path(directory)
        source = "(:: isolatedValue Int)\n(fn (isolatedValue) 7)\n"
        present = work / "Present.ax"
        empty = work / "Empty.ax"
        missing = work / "Missing.ax"
        unreadable = work / "Unreadable.ax"
        present.write_text(source)
        empty.write_text("")
        unreadable.mkdir()  # readFile on a directory is Err, even for root.

        def file_error(path):
            return f"File error: cannot read '{path}'\n"

        expected = (
            f"OK: Loaded '{present}'\n"
            f"present:{len(source.encode()) + 1}\n"
            + file_error(empty) + f"empty:{len(source.encode()) + 1}\n"
            + file_error(missing) + f"missing:{len(source.encode()) + 1}\n"
            + file_error(unreadable) + f"unreadable:{len(source.encode()) + 1}\n"
        )

        def native(name, local, level):
            binary = work / name
            built = execute([compiler, "--diagnostic-format=ai", "build", str(fixture),
                             "--opt", str(level), "--alloc-poison", "-o", str(binary)], local)
            assert built.returncode == 0, (name, built.returncode, built.stdout, built.stderr)
            ran = execute([str(binary), str(present), str(empty), str(missing), str(unreadable)], local)
            assert ran.returncode == 0 and not ran.stderr, (name, ran.returncode, ran.stdout, ran.stderr)
            return ran.stdout

        for level in (0, 2):
            observed = native(f"positive-O{level}", env, level)
            assert observed == expected, (level, observed, expected)
            print(f"ok   REPL load O{level}: present, empty, missing, unreadable", flush=True)

        refusals = (
            ("raw-read", "String", '(readFile "missing.ax")', "AX3004"),
            ("missing-err", "String", '(match (readFile "missing.ax") ((Ok src) src))', "AX3005"),
            ("missing-ok", "String", '(match (readFile "missing.ax") ((Err _) ""))', "AX3005"),
        )
        for name, return_type, expression, code in refusals:
            bad = work / f"{name}.ax"
            bad.write_text("(import IO)\n"
                           f"(:: bad {return_type})\n;@axiom:effect(io)\n"
                           f"(fn (bad) {expression})\n"
                           "(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(bad)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print(f"ok   {name}: {code}", flush=True)

        if args.negative_controls:
            controls = (
                ("discard-read-error", "((Err _) (replLoadFileError declsSrc arg))", "((Err _) declsSrc)", 1),
                ("discard-empty-file", "(if (== (strLen src) 0)\n          (replLoadFileError declsSrc arg)",
                 "(if (== (strLen src) 0)\n          declsSrc", 2),
            )
            for name, before, after, error_count in controls:
                assert original.count(before) == 1, (name, original.count(before))
                overlay = work / (name + "-core")
                overlay.mkdir()
                for path in (root / "core").iterdir():
                    target = overlay / path.name
                    if path.name == "repl.ax":
                        target.write_text(original.replace(before, after))
                    else:
                        target.symlink_to(path, target_is_directory=path.is_dir())
                observed = native(name, dict(env, AXIOM_PATH=str(overlay)), 0)
                assert observed != expected, (name, observed)
                assert observed.count("File error: cannot read") == error_count, (name, observed)
                print(f"ok   {name}: effective mutation", flush=True)

    print("ok   REPL load Result handling and output parity")


if __name__ == "__main__":
    main()
