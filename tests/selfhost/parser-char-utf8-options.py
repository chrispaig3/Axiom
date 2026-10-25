#!/usr/bin/env python3
"""Check typed character decoding and refusal of malformed UTF-8 literals."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile


EXPECTED = "".join(f"{n} true\n" for n in range(1, 21))


def execute(args, env):
    return subprocess.run(args, env=env, capture_output=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", required=True, type=Path)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/selfhost/parser-char-utf8-options.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))

    with tempfile.TemporaryDirectory(prefix="axiom-parser-char-options-") as directory:
        work = Path(directory)

        def direct(name, local, level):
            binary = work / name
            built = execute([compiler, "--diagnostic-format=ai", "build", str(fixture),
                             "--opt", str(level), "--alloc-poison", "-o", str(binary)], local)
            assert built.returncode == 0, (name, built.stdout, built.stderr)
            ran = execute([str(binary)], local)
            assert ran.returncode == 0 and not ran.stderr, (name, ran.stdout, ran.stderr)
            return ran.stdout.decode("utf-8")

        for level in (0, 2):
            observed = direct(f"direct-O{level}", env, level)
            assert observed == EXPECTED, (level, observed)
            print(f"ok   O{level}: 20 valid, missing and lexical character cases", flush=True)

        cases = {
            "ascii": (b"a", 0, None, None),
            "two-byte": ("é".encode(), 0, None, None),
            "three-byte": ("世".encode(), 0, None, None),
            "four-byte": ("😀".encode(), 0, None, None),
            "stray-continuation": (b"\x80", 1, "AX1001", "0x80"),
            "invalid-lead": (b"\xf8", 1, "AX1001", "0xF8"),
            "invalid-continuation": (b"\xc3\x20", 1, "AX1001", "0xC3"),
            "overlong": (b"\xc0\xaf", 1, "AX1001", "0xC0"),
            "surrogate": (b"\xed\xa0\x80", 1, "AX1001", "0xED"),
            "above-unicode": (b"\xf4\x90\x80\x80", 1, "AX1001", "0xF4"),
            "truncated": (b"\xc3", 1, "AX1003", "unterminated char literal"),
            "bad-escape": (b"\\q", 1, "AX1005", "invalid escape sequence"),
        }
        for name, (payload, status, code, fragment) in cases.items():
            source = work / (name + ".ax")
            source.write_bytes(b"(:: value Char)\n(fn (value) '" + payload +
                               b"')\n(:: main Int)\n(fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            stdout = checked.stdout.decode("utf-8")
            stderr = checked.stderr.decode("utf-8")  # Invalid source bytes must not enter AXDL.
            if status == 0:
                assert (checked.returncode, stdout, stderr) == (0, "OK\n", ""), (name, stdout, stderr)
            else:
                errors = [line for line in stderr.splitlines() if line.startswith("E ")]
                assert checked.returncode == status and len(errors) == 1, (name, stdout, stderr)
                assert re.search(rf"^E {code} .*:2:\d+(?:-\d+)? ", errors[0]), (name, errors)
                assert fragment in errors[0], (name, errors)
            print(f"ok   {name}: {code or 'valid'}", flush=True)

        refusals = {
            "unchecked": ("(charLexemeCode \"'A'\")", "AX3004"),
            "missing-none": ("(match (charLexemeCode \"'A'\") ((Some value) value))", "AX3005"),
            "missing-some": ("(match (charLexemeCode \"'A'\") ((None) 0))", "AX3005"),
        }
        for name, (expression, code) in refusals.items():
            source = work / (name + ".ax")
            source.write_text("(import parser)\n(:: bad Int)\n"
                              f"(fn (bad) {expression})\n"
                              "(:: main Int)\n(fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.decode("utf-8").splitlines()
                      if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.stdout, checked.stderr)
            print(f"ok   {name}: {code}", flush=True)

        if args.negative_controls:
            changes = {
                "unchecked-lexer": (
                    "lexer.ax",
                    "(if (|| esc (!= (utf8WellFormedAt src (+ pos 1) (- ep 1)) 0))",
                    "(if true",
                    (7, 9, 11, 13, 15),
                ),
                "forged-parser-code": (
                    "parser.ax",
                    "(if (== (utf8WellFormedAt lex 1 (- n 1)) (- n 2))\n"
                    "          (utf8DecodeAt lex 1)\n          None)",
                    "(if (== (utf8WellFormedAt lex 1 (- n 1)) (- n 2))\n"
                    "          (utf8DecodeAt lex 1)\n          (Some (- 0 1)))",
                    (6, 8, 10, 12, 14),
                ),
            }
            for name, (file, old, new, affected) in changes.items():
                original = (root / "core" / file).read_text()
                assert original.count(old) == 1, (name, original.count(old))
                overlay = work / (name + "-core")
                overlay.mkdir()
                for path in (root / "core").iterdir():
                    target = overlay / path.name
                    if path.name == file:
                        target.write_text(original.replace(old, new))
                    else:
                        target.symlink_to(path, target_is_directory=path.is_dir())
                observed = direct(name, dict(env, AXIOM_PATH=str(overlay)), 0)
                lines = observed.splitlines()
                assert len(lines) == 20 and all(lines[n - 1] == f"{n} false" for n in affected), (
                    name, observed)
                print(f"ok   {name}: effective negative control", flush=True)


if __name__ == "__main__":
    main()
