#!/usr/bin/env python3
"""Check optional function signatures and diagnostic value carriers."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


# Exact diagnostics from the unmodified 5d86bdff diagnostic carrier.
DIAGNOSTICS = 'DIAGNOSTICS\nE AX3060 diagnostic-value.ax:1:2-5 region-escape "a value allocated in region `inner` is stored into the outer binding, which lives in this function\'s own region (its caller\'s current region) - synthetic flow" ^1:11-16:"this scope reclaims the stored value before the destination is used" ?"this store or call crosses a reclamation boundary: move it to the destination\'s outer scope, or keep the destination and every use inside the value\'s region; keeping another reference cannot postpone the reset"\nE AX3062 diagnostic-value.ax:1:2-5 region-capture "the closure captures `captured`, which lives in region `inner`, and is stored into the outer binding, which lives in this function\'s own region (its caller\'s current region) - concrete value" ^1:11-16:"this scope reclaims a value the closure captures" ?"keep the closure and every use inside its captures\' region, or create its captured values and the closure in the destination\'s outer scope; capturing a reference does not extend its region"\nE AX3062 diagnostic-value.ax:1:2-5 region-capture "the closure captures ``, which lives in region `inner`, and is stored into the outer binding, which lives in this function\'s own region (its caller\'s current region)" ^1:11-16:"this scope reclaims a value the closure captures" ?"keep the closure and every use inside its captures\' region, or create its captured values and the closure in the destination\'s outer scope; capturing a reference does not extend its region"\nE AX3060 diagnostic-value.ax:1:2-5 region-escape "a value allocated in region `inner` is stored into the outer binding, which lives in this function\'s own region (its caller\'s current region)" ^1:11-16:"this scope reclaims the stored value before the destination is used" ?"this store or call crosses a reclamation boundary: move it to the destination\'s outer scope, or keep the destination and every use inside the value\'s region; keeping another reference cannot postpone the reset"\n'
EXPECTED = "".join(f"{index} true\n" for index in range(1, 32)) + DIAGNOSTICS


def execute(args, env):
    return subprocess.run(args, env=env, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/selfhost/typecheck-signature-diagnostic-options.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    original = (root / "core/typecheck.ax").read_text()
    with tempfile.TemporaryDirectory(prefix="axiom-signature-diagnostic-options-") as directory:
        work = Path(directory)

        def native(name, local, level, first_false=None):
            binary = work / name
            built = execute([compiler, "--diagnostic-format=ai", "build", str(fixture),
                             "--opt", str(level), "--alloc-poison", "-o", str(binary)], local)
            assert built.returncode == 0, (name, built.returncode, built.stdout, built.stderr)
            ran = execute([str(binary)], local)
            assert ran.returncode == 0 and not ran.stderr, (name, ran.returncode, ran.stderr)
            if first_false is None:
                assert ran.stdout == EXPECTED, (name, ran.stdout)
            else:
                before, marker, _ = ran.stdout.partition("DIAGNOSTICS\n")
                assert marker and len(before.splitlines()) == 31, (name, ran.stdout)
                failed = [i + 1 for i, line in enumerate(before.splitlines()) if line != f"{i + 1} true"]
                assert failed and failed[0] == first_false, (name, failed, ran.stdout)
            print("ok   " + name, flush=True)

        for level in (0, 2):
            native("positive-O" + str(level), env, level)

        refused = {
            "raw-signature": ("(bindFnParams (tcNew vecNew vecNew vecNew) vecNew vecNew nilNode 0)", "AX3004"),
            "raw-diagnostic-value": ("(rgnEmitEscape context 0 0 \"into\" \"how\" nilNode)", "AX3004"),
            "missing-signature-none": ("(match (:: None (Option ASTNode)) ((Some value) (nodeTag value)))", "AX3005"),
        }
        for name, (expression, code) in refused.items():
            source = work / (name + ".ax")
            declaration = ("(:: bad (-> RgnCtx Int))\n(fn (bad context) " + expression + ")\n"
                           if name == "raw-diagnostic-value" else
                           "(:: bad Int)\n(fn (bad) { " + expression + " 0 })\n")
            source.write_text("(import core)\n(import parser)\n(import typecheck)\n(import Vec)\n" +
                              declaration + "(:: main Int)\n(fn (main) 0)\n")
            result = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in result.stderr.splitlines() if line.startswith("E ")]
            assert result.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, result.returncode, result.stdout, result.stderr)
            print("ok   " + name + ": " + code, flush=True)

        if args.negative_controls:
            controls = (
                ("missing-default-is-string", "bindFnParams", "((None) mkIntTy)", "((None) mkStringTy)", 1),
                ("lost-fresh-counter", "bindFnParams", "(tcBumpCounter tc)", "()", 2),
                ("discard-present-signature", "tcCheckFn",
                 "((Some entry) (bsTypeOpt (fnEntTy entry)))", "((Some entry) None)", 11),
                ("discard-diagnostic-value", "rgnEmitEscape",
                 "(rgnCaptureBad rc value (% (- bad 1) 64))", "0", 22),
            )
            for name, function, old, new, failed in controls:
                start = original.index("(pub fn (" + function + " ")
                end = original.index("\n\n", start)
                body = original[start:end]
                assert body.count(old) == 1, (name, body.count(old))
                changed = original[:start] + body.replace(old, new) + original[end:]
                overlay = work / (name + "-core/core")
                overlay.mkdir(parents=True)
                for path in (root / "core").iterdir():
                    if path.name == "typecheck.ax":
                        (overlay / path.name).write_text(changed)
                    else:
                        (overlay / path.name).symlink_to(path, target_is_directory=path.is_dir())
                native(name, dict(env, AXIOM_PATH=str(overlay)), 0, failed)
    print("ok   signature/diagnostic Options: 31 native cases O0/O2 poison, exact diagnostic bytes, three refusals")


if __name__ == "__main__":
    main()
