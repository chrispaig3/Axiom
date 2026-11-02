#!/usr/bin/env python3
"""Check parameter type Options, actual consumers and exact diagnostic fallbacks."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


# Captured from the unmodified a8ac6278 checker, with the same parsed inputs.
DIAGNOSTICS = 'DIAGNOSTICS\nE AX3130 scoped-absent.ax:3:10-11 scoped-callback "a scoped parameter must have a declared function type" ?"write a lambda at the call, or forward a parameter declared scoped; a scoped callback returns a scalar and retains no invocation-owned references or allocations"\nE AX3130 scoped-exhausted.ax:3:10-11 scoped-callback "a scoped parameter must have a declared function type" ?"write a lambda at the call, or forward a parameter declared scoped; a scoped callback returns a scalar and retains no invocation-owned references or allocations"\nE AX3130 scoped-scalar.ax:3:10-11 scoped-callback "a scoped parameter must have a declared function type" ?"write a lambda at the call, or forward a parameter declared scoped; a scoped callback returns a scalar and retains no invocation-owned references or allocations"\nE AX3131 compute-absent.ax:3:10-11 compute-callback "a compute parameter requires the declared callback type (-> Int Int)" ?"pass a numeric lambda, a checked named function, or the exact parameter carrying compute; use canonical primitive captures, numeric operations and local accumulators; raw/runtime observers, references, heap stores, allocation and opaque calls are refused"\nE AX3131 compute-exhausted.ax:3:10-11 compute-callback "a compute parameter requires the declared callback type (-> Int Int)" ?"pass a numeric lambda, a checked named function, or the exact parameter carrying compute; use canonical primitive captures, numeric operations and local accumulators; raw/runtime observers, references, heap stores, allocation and opaque calls are refused"\nE AX3004 arity-refusal.ax:4:17-18 type-mismatch "`f` takes 1 argument(s), given 2" #"2 argument(s) provided here" ?"remove the extra argument(s), or add a parameter to the definition"\n'
EXPECTED = "".join(f"{index} true\n" for index in range(1, 48)) + DIAGNOSTICS


def execute(arguments, env):
    return subprocess.run(arguments, env=env, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", required=True, type=Path)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/selfhost/typecheck-nth-param-options.axp"
    environment = dict(os.environ, AXIOM_STDLIB=str(root / "stdlib"), AXIOM_PATH=str(root / "core"))
    original = {name: (root / "core" / name).read_text() for name in ("typecheck.ax", "lsp.ax")}

    with tempfile.TemporaryDirectory(prefix="axiom-nth-param-options-") as directory:
        work = Path(directory)

        def native(label, env, level, first_false=None):
            binary = work / label
            built = execute([compiler, "--diagnostic-format=ai", "build", str(fixture),
                             "--opt", str(level), "--alloc-poison", "-o", str(binary)], env)
            assert built.returncode == 0, (label, built.stdout, built.stderr)
            ran = execute([str(binary)], env)
            assert ran.returncode == 0 and not ran.stderr, (label, ran.returncode, ran.stderr)
            if first_false is None:
                assert ran.stdout == EXPECTED, (label, ran.stdout)
            else:
                lines, diagnostics = ran.stdout.split("DIAGNOSTICS\n", 1)
                assert "PARSE_FAILURE" not in lines
                failed = [index + 1 for index, line in enumerate(lines.splitlines())
                          if line != f"{index + 1} true"]
                assert failed and failed[0] == first_false, (label, failed, ran.stdout)
                assert "PARSE_FAILURE" not in diagnostics, (label, diagnostics)
            print("ok   " + label, flush=True)

        for level in (0, 2):
            native("positive-O" + str(level), environment, level)

        invalid = {
            "unchecked-option": ("(nodeTag (nthParamTy mkIntTy 0))", "AX3004"),
            "missing-none": ("(match (nthParamTy mkIntTy 0) ((Some ty) (nodeTag ty)))", "AX3005"),
            "wrong-index": ("(nthParamTy mkIntTy false)", "AX3004"),
            "unchecked-lsp-type": ("(nodeTag (lspShapeParamTy vecNew \"none\" 0))", "AX3004"),
            "unchecked-lsp-name": ("(strLen (lspFieldValueStruct (Some (mkEInt 1))))", "AX3004"),
        }
        for name, (expression, code) in invalid.items():
            source = work / (name + ".ax")
            source.write_text("(import core)\n(import parser)\n(import typecheck)\n(import lsp)\n"
                              "(import Vec)\n(import Str)\n(:: main Int)\n(fn (main) { " + expression + " 0 })\n")
            refused = execute([compiler, "--diagnostic-format=ai", "check", str(source)], environment)
            errors = [line for line in refused.stderr.splitlines() if line.startswith("E ")]
            assert refused.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, refused.returncode, refused.stdout, refused.stderr)
            print("ok   " + name + ": " + code, flush=True)

        if args.negative_controls:
            controls = (
                ("present-is-absent", "typecheck.ax", "nthParamTy",
                 "(Some parameter)", "None", 4),
                ("lost-fresh-variable", "typecheck.ax", "bindFnParams",
                 "(freshTVar tc 0)", "mkIntTy", 12),
                ("unknown-stamps-scalar", "typecheck.ax", "rgnKnownCall",
                 "(set ok 0)))", "()))", 16),
                ("missing-hover-is-int", "lsp.ax", "lspShapeParamTy",
                 "      None", "      (Some mkIntTy)", 23),
            )
            for name, module, function, old, new, failed in controls:
                text = original[module]
                start = text.index("(pub fn (" + function + " ")
                end = text.index("\n\n", start)
                body = text[start:end]
                assert body.count(old) == 1, (name, body.count(old))
                changed = text[:start] + body.replace(old, new) + text[end:]
                overlay = work / (name + "-core/core")
                overlay.mkdir(parents=True)
                for path in (root / "core").iterdir():
                    if path.name == module:
                        (overlay / path.name).write_text(changed)
                    else:
                        (overlay / path.name).symlink_to(path, target_is_directory=path.is_dir())
                native(name, dict(environment, AXIOM_PATH=str(overlay)), 0, failed)

    print("ok   nth parameter Options: 47 native cases O0/O2 poison, exact AXDL and five typed/exhaustive refusals")


if __name__ == "__main__":
    main()
