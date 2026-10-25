#!/usr/bin/env python3
"""Check typed Markdown closing lookups and byte-for-byte rendering."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


CASES = [
    "[a](url)", "[a[b]c](url)", "[a]", "[a](x y)", "[a](x(y)z)",
    "![alt](img.png)", "![alt](x y)", "![a[b]](x)",
    "`x`", "`x", "`` x ``", "``x`", "*x*", "**x**", "*x", "* x*",
    "x* y*", "a **b** c", "[`[x]`](y)", "``a`b``", "a`b`c", "a**b**c",
    "plain", "[a](x\n y)", "![a](x(y))", "[a](url) and `x` with *em*",
]


def execute(args, env):
    return subprocess.run(args, env=env, capture_output=True, text=True, timeout=180)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", required=True, type=Path)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    original = (root / "core/markdown.ax").read_text()
    expected = json.loads((root / "tests/selfhost/markdown-close-render.golden.json").read_text())
    assert len(expected) == len(CASES)
    environment = dict(os.environ, AXIOM_PATH=str(root / "core"),
                       AXIOM_STDLIB=str(root / "stdlib"))
    environment["PATH"] = "/opt/homebrew/opt/llvm/bin:" + environment.get("PATH", "")

    with tempfile.TemporaryDirectory(prefix="axiom-markdown-close-options-") as temporary:
        work = Path(temporary)

        def native(name, fixture, level, env):
            binary = work / name
            built = execute([compiler, "--diagnostic-format=ai", "build", str(fixture),
                             "--opt", str(level), "--alloc-poison", "-o", str(binary)], env)
            assert built.returncode == 0, (name, built.returncode, built.stdout, built.stderr)
            return binary

        def render(binary, env):
            result = execute([str(binary), *CASES], env)
            assert result.returncode == 0 and not result.stderr, (
                result.returncode, result.stdout, result.stderr)
            rows = result.stdout.splitlines()
            assert len(rows) == len(CASES), (len(rows), result.stdout)
            return [json.loads(row) for row in rows]

        direct_fixture = root / "tests/selfhost/markdown-close-options.axp"
        render_fixture = root / "tests/selfhost/markdown-close-render.axp"
        direct_expected = "".join(f"{index} true\n" for index in range(1, 22))
        for level in (0, 2):
            direct = native(f"direct-O{level}", direct_fixture, level, environment)
            observed = execute([str(direct)], environment)
            assert (observed.returncode, observed.stdout, observed.stderr) == (
                0, direct_expected, ""), (level, observed)
            rendered = native(f"render-O{level}", render_fixture, level, environment)
            actual = render(rendered, environment)
            assert actual == expected, (level, [i for i in range(len(CASES)) if actual[i] != expected[i]])
            print(f"ok   Markdown closes O{level}: 21 typed cases, {len(CASES)} exact renders", flush=True)

        refusals = {
            "raw-bracket": ("(mdBracketEnd \"[x]\" 0)", "AX3004"),
            "raw-paren": ("(mdParenEnd \"x)\" 0)", "AX3004"),
            "raw-code": ("(mdCodeClose \"`x`\" 1 1)", "AX3004"),
            "raw-emphasis": ("(mdEmClose \"a*\" 0 1)", "AX3004"),
            "missing-none": ("(match (mdParenEnd \"x)\" 0) ((Some close) close))", "AX3005"),
            "missing-some": ("(match (mdBracketEnd \"[x]\" 0) ((None) 0))", "AX3005"),
        }
        for name, (expression, code) in refusals.items():
            source = work / f"{name}.ax"
            source.write_text("(import core)\n(import markdown)\n(:: bad Int)\n"
                              f"(fn (bad) {expression})\n(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], environment)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stderr)
            print(f"ok   {name}: {code}", flush=True)

        if args.negative_controls:
            controls = (
                ("drop-bracket", "mdBracketEnd", "(set found (Some (+ j 1)))", "(set found None)", 0),
                ("drop-paren", "mdParenEnd", "(set found (Some j))", "(set found None)", 0),
                ("drop-code", "mdCodeClose", "(if (== (- m j) k)", "(if false", 8),
                ("drop-emphasis", "mdEmClose",
                 "(if (&& (== (- m j) k) (!= (strByte s (- j 1)) 32))", "(if false", 12),
            )
            for name, function, old, replacement, case in controls:
                start = original.index("(pub fn (" + function + " ")
                end = original.index("\n\n", start)
                body = original[start:end]
                assert body.count(old) == 1, (name, body.count(old))
                changed = original[:start] + body.replace(old, replacement) + original[end:]
                overlay = work / (name + "-core")
                overlay.mkdir()
                for path in (root / "core").iterdir():
                    target = overlay / path.name
                    if path.name == "markdown.ax":
                        target.write_text(changed)
                    else:
                        target.symlink_to(path, target_is_directory=path.is_dir())
                local = dict(environment, AXIOM_PATH=str(overlay))
                binary = native(name, render_fixture, 0, local)
                actual = render(binary, local)
                assert actual[case] != expected[case], (name, case, actual[case])
                print(f"ok   {name}: effective rendering counterexample", flush=True)

    print("ok   Markdown closing lookups retain exact rendering")


if __name__ == "__main__":
    main()
