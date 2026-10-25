#!/usr/bin/env python3
"""Check typed absence in nolint lookup and REPL tag-line traversal."""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile


EXPECTED = "".join(f"{number} true\n" for number in range(1, 16))


def execute(arguments, env):
    return subprocess.run(arguments, env=env, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", required=True, type=Path)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/selfhost/nolint-repl-absence-options.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))

    with tempfile.TemporaryDirectory(prefix="axiom-nolint-repl-options-") as directory:
        work = Path(directory)

        def native(label, local, level):
            binary = work / label
            built = execute([compiler, "--diagnostic-format=ai", "build", str(fixture),
                             "--opt", str(level), "--alloc-poison", "--output", str(binary)], local)
            assert built.returncode == 0, (label, built.returncode, built.stdout, built.stderr)
            ran = execute([str(binary)], local)
            assert ran.returncode == 0 and not ran.stderr, (
                label, ran.returncode, ran.stdout, ran.stderr)
            return ran.stdout

        for level in (0, 2):
            actual = native(f"positive-O{level}", env, level)
            assert actual == EXPECTED, (level, actual, EXPECTED)
            print(f"ok   O{level}: fifteen typed absence cases", flush=True)

        refusals = {
            "raw-previous-line": ('(replPrevLineStart "a\\nb\\n" 2)', "AX3004"),
            "missing-none": ('(match (replPrevLineStart "a\\nb\\n" 2) ((Some p) p))', "AX3005"),
            "missing-some": ('(match (replPrevLineStart "a\\nb\\n" 2) ((None) 0))', "AX3005"),
        }
        for label, (expression, code) in refusals.items():
            source = work / (label + ".ax")
            source.write_text("(import repl)\n(:: bad Int)\n"
                              f"(fn (bad) {expression})\n"
                              "(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                label, checked.returncode, checked.stdout, checked.stderr)
            print(f"ok   {label}: {code}", flush=True)

        if args.negative_controls:
            controls = (
                ("lost-name-absence", "nolint.ax", "((None) out)",
                 '((None) (vecPush out "incorrect"))', "1 false"),
                ("lost-owner-merge", "nolint.ax", "((Some j) (nolintAppend (vecGet t.sets j) names))",
                 "((Some j) ())", "6 false"),
                ("lost-prior-line", "repl.ax", "(Some (replLineStartAt src (- s 2)))",
                 "None", "9 false"),
                ("lost-absent-tag-boundary", "repl.ax", "((None) s)",
                 "((None) 0)", "15 false"),
            )
            for label, filename, old, new, failure in controls:
                original = (root / "core" / filename).read_text()
                assert original.count(old) == 1, (label, original.count(old))
                overlay = work / (label + "-core")
                overlay.mkdir()
                for path in (root / "core").iterdir():
                    target = overlay / path.name
                    if path.name == filename:
                        target.write_text(original.replace(old, new))
                    else:
                        target.symlink_to(path, target_is_directory=path.is_dir())
                local = dict(env, AXIOM_PATH=str(overlay))
                actual = native(label, local, 0)
                assert actual != EXPECTED and failure in actual, (label, actual)
                print(f"ok   {label}: effective mutation", flush=True)


if __name__ == "__main__":
    main()
