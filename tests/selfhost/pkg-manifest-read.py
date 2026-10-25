#!/usr/bin/env python3
"""Check that a found manifest's read failure cannot become empty text."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


MODES = ("dirs", "search", "name", "opt", "entry", "verify")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, *, env, cwd=None):
    return subprocess.run(command, env=env, cwd=cwd, capture_output=True,
                          text=True, timeout=240)


def check(compiler, root, work):
    source = (root / "core/pkg.ax").read_text()
    main_hash = digest(root / "core/main.ax")
    source_hash = digest(root / "core/pkg.ax")
    compiler_hash = digest(compiler)
    fixture = root / "tests/selfhost/pkg-manifest-read.axp"
    inputs = work / "inputs"
    paths = {name: inputs / name for name in (
        "present", "present-dirs", "missing", "unreadable"
    )}
    for path in paths.values():
        path.mkdir(parents=True)
    (paths["present"] / "axiom.pkg").write_text(
        "name demo\nopt 2\nmain Main.ax\n"
    )
    (paths["present-dirs"] / "axiom.pkg").write_text(
        "depend vendor/dep\n"
    )
    (paths["present-dirs"] / "vendor/dep").mkdir(parents=True)
    (paths["unreadable"] / "axiom.pkg").mkdir()
    env = dict(os.environ, AXIOM_PATH=str(root / "core"),
               AXIOM_STDLIB=str(root / "stdlib"))
    report = {
        "compiler_sha256": compiler_hash,
        "pkg_source_sha256": source_hash,
        "main_source_sha256": main_hash,
        "positive": {}, "controls": {}, "refusals": {},
        "limits": ["Host O0/O2 with allocation poisoning; no network access."],
    }

    def build_fixture(label, level, local):
        target = work / label
        got = run([str(compiler), "--diagnostic-format=ai", "build",
                   str(fixture), "--opt", str(level), "--alloc-poison",
                   "-o", str(target)], env=local)
        assert got.returncode == 0, (label, got.stdout, got.stderr)
        return target

    def invoke(binary, path, mode, local=env):
        return run([str(binary), str(path), mode], env=local)

    expected_present = {
        "dirs": "dirs 0\n", "search": "search 0\n",
        "name": "name demo\n", "opt": "opt 2\n",
        "entry": f"entry {paths['present']}/Main.ax\n",
        "verify": "verified\n",
    }
    expected_missing = {
        "dirs": "dirs 0\n", "search": "search 0\n",
        "name": "name None\n", "opt": "opt None\n",
        "entry": "entry None\n", "verify": "verified\n",
    }
    read_error = re.compile(
        rf"^error: could not read manifest `{re.escape(str(paths['unreadable'] / 'axiom.pkg'))}`: errno ([1-9][0-9]*)\n$"
    )
    for level in (0, 2):
        label = f"manifest-O{level}"
        binary = build_fixture(label, level, env)
        for mode in MODES:
            for path, expected in ((paths["present"], expected_present[mode]),
                                   (paths["missing"], expected_missing[mode])):
                got = invoke(binary, path, mode)
                assert (got.returncode, got.stdout, got.stderr) == (0, expected, ""), (
                    label, path, mode, got
                )
            got = invoke(binary, paths["unreadable"], mode)
            assert got.returncode == 3 and got.stdout == "" and read_error.fullmatch(got.stderr), (
                label, mode, got
            )
            report["positive"][f"{label}-{mode}"] = {
                "read_errno": int(read_error.fullmatch(got.stderr).group(1))
            }
        for mode in ("dirs", "search"):
            got = invoke(binary, paths["present-dirs"], mode)
            assert (got.returncode, got.stdout, got.stderr) == (0, f"{mode} 1\n", ""), (
                label, mode, got
            )
        print(f"ok   manifest read O{level}: present, absent and unreadable across six readers", flush=True)

    # The actual compiler's fetch path must use the same read policy.
    fetch_expected = (
        (paths["present"], 0, "nothing to fetch: no registry dependencies\n", ""),
        (paths["missing"], 1, "", "error: no axiom.pkg at or above the working directory\n"),
        (paths["unreadable"], 3, "", "error: could not read manifest `./axiom.pkg`: errno "),
    )
    for path, status, stdout, stderr in fetch_expected:
        got = run([str(compiler), "--diagnostic-format=ai", "fetch"],
                  env=env, cwd=path)
        if path == paths["unreadable"]:
            assert (got.returncode, got.stdout) == (status, stdout) and re.fullmatch(
                re.escape(stderr) + r"[1-9][0-9]*\n", got.stderr
            ), (path, got)
        else:
            assert (got.returncode, got.stdout, got.stderr) == (status, stdout, stderr), (
                path, got
            )
        report["positive"][f"fetch-{path.name}"] = {
            "status": got.returncode, "stdout": got.stdout, "stderr": got.stderr
        }
    print("ok   fetch: present, absent and unreadable manifests", flush=True)

    # A mutation that restores the erased-error fallback must be observed.
    start = source.index("(pub fn (pkgReadManifest mf)")
    end = source.index("\n\n; The first nonempty value", start)
    changed = source[:start] + (
        "(pub fn (pkgReadManifest mf)\n"
        "  (match (readFile mf)\n"
        "    ((Ok text) text)\n"
        "    ((Err _) \"\")))"
    ) + source[end:]
    modules = work / "erased-error-core"
    modules.mkdir()
    for path in (root / "core").iterdir():
        dest = modules / path.name
        if path.name == "pkg.ax":
            dest.write_text(changed)
        else:
            dest.symlink_to(path, target_is_directory=path.is_dir())
    mutated_env = dict(env, AXIOM_PATH=str(modules))
    mutated = build_fixture("erased-error", 0, mutated_env)
    got = invoke(mutated, paths["unreadable"], "name", mutated_env)
    assert (got.returncode, got.stdout, got.stderr) == (0, "name None\n", ""), got
    report["controls"]["erased-error"] = got.stdout
    print("ok   erased-error: effective counterexample", flush=True)

    for label, arms in (("missing-err", "((Ok text) text)"),
                        ("missing-ok", "((Err e) \"\")")):
        path = work / f"{label}.ax"
        path.write_text(
            "(import IO)\n(:: bad (-> String String))\n;@axiom:effect(io)\n"
            f"(fn (bad p) (match (readFile p) {arms}))\n"
        )
        got = run([str(compiler), "--diagnostic-format=ai", "check", str(path)], env=env)
        errors = [line for line in got.stderr.splitlines() if line.startswith("E ")]
        assert got.returncode == 1 and len(errors) == 1 and "E AX3005 " in errors[0], (
            label, got.returncode, got.stderr
        )
        report["refusals"][label] = errors[0]
        print(f"ok   {label}: AX3005", flush=True)

    assert digest(compiler) == compiler_hash
    assert digest(root / "core/pkg.ax") == source_hash
    assert digest(root / "core/main.ax") == main_hash
    (work / "report.json").write_text(json.dumps(report, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", required=True, type=Path)
    parser.add_argument("--work", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), root, args.work.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix="axiom-pkg-manifest-") as temp:
            check(args.axiom.resolve(), root, Path(temp))


if __name__ == "__main__":
    main()
