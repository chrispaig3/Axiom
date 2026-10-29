#!/usr/bin/env python3
"""Check source-edit Option positions, exact fix metadata and refusal controls."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


CONTROLS = [
    ("formOpenBefore", "(Some j)", "None", 1),
    ("matchCloseAt", "          (Some next)", "          None", 2),
    ("importListOpen", "(Some i)", "None", 4),
    ("effectTagInsertAt", "(Some (lineStartOf src p))", "None", 5),
]


def build_probe(compiler, repo, env, executable):
    built = subprocess.run(
        [str(compiler), "--diagnostic-format=ai", "build",
         str(repo / "tests/selfhost/typecheck-edit-position-options.ax"),
         "--opt", "0", "--output", str(executable)],
        env=env, capture_output=True, text=True,
    )
    if built.returncode:
        raise SystemExit(built.stdout + built.stderr)


def run_probe(executable, expected, label):
    ran = subprocess.run([str(executable)], capture_output=True, text=True)
    if ran.returncode != expected or ran.stdout or ran.stderr:
        raise SystemExit(f"{label}: status={ran.returncode}, stdout={ran.stdout!r}, stderr={ran.stderr!r}")


def negative_control(compiler, repo, env, work, control):
    function, old, replacement, expected = control
    overlay = work / function
    overlay.mkdir()
    for source in (repo / "core").iterdir():
        if source.is_file() and source.name != "typecheck.ax":
            (overlay / source.name).symlink_to(source)
    source = (repo / "core/typecheck.ax").read_text()
    start = source.index(f"(pub fn ({function} ")
    end = source.index("\n\n", start)
    body = source[start:end]
    if body.count(old) != 1:
        raise SystemExit(f"{function}: mutation no longer matches its unique lookup")
    (overlay / "typecheck.ax").write_text(source[:start] + body.replace(old, replacement) + source[end:])
    executable = work / f"{function}-negative"
    build_probe(compiler, repo, dict(env, AXIOM_PATH=str(overlay)), executable)
    run_probe(executable, expected, function)
    print(f"{function}: effective missing-position mutation failed status {expected}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", required=True, type=Path)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    env = dict(os.environ, AXIOM_PATH=str(repo / "core"), AXIOM_STDLIB=str(repo / "stdlib"))
    compiler = args.axiom.resolve()
    with tempfile.TemporaryDirectory(prefix="axiom-edit-options-") as directory:
        work = Path(directory)
        executable = work / "edit-positions"
        build_probe(compiler, repo, env, executable)
        run_probe(executable, 42, "source edit positions")
        refusal = subprocess.run(
            [str(compiler), "--diagnostic-format=ai", "check",
             str(repo / "tests/selfhost/typecheck-edit-position-refusal.axp")],
            env=env, capture_output=True, text=True,
        )
        errors = [line for line in refusal.stderr.splitlines() if line.startswith("E ")]
        if refusal.returncode != 1 or len(errors) != 1 or "E AX3005 " not in errors[0] or "None" not in errors[0]:
            raise SystemExit(refusal.stdout + refusal.stderr)
        if args.negative_controls:
            for control in CONTROLS:
                negative_control(compiler, repo, env, work, control)
    print("source edit positions: native 42 and exhaustive Option refusal passed")


if __name__ == "__main__":
    main()
