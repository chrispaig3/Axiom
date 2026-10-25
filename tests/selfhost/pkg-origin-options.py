#!/usr/bin/env python3
"""Exercise present, absent, empty and unreadable package origins as Options."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check(compiler, root, work):
    source = (root / "core/pkg.ax").read_text()
    source_hash = digest(root / "core/pkg.ax")
    main_hash = digest(root / "core/main.ax")
    fixture = root / "tests/selfhost/pkg-origin-options.axp"
    good_url = "https://example.test/first"
    no_origin = (
        "it holds no git checkout with an `origin` "
        "(an interrupted or failed clone leaves one like this)"
    )
    data = work / "inputs"
    paths = {name: data / name for name in (
        "good", "missing", "empty", "other", "empty-url", "unreadable"
    )}
    for path in paths.values():
        (path / ".git").mkdir(parents=True)
    (paths["good"] / ".git/config").write_text(
        '[remote "upstream"]\n  url = https://example.test/upstream\n'
        '[remote "origin"]\n  url = ' + good_url + '\n'
        '  url = https://example.test/second\n'
    )
    (paths["empty"] / ".git/config").write_text("")
    (paths["other"] / ".git/config").write_text(
        '[remote "upstream"]\n  url = https://example.test/upstream\n'
    )
    (paths["empty-url"] / ".git/config").write_text(
        '[remote "origin"]\n  url =\n'
    )
    (paths["unreadable"] / ".git/config").mkdir()
    args = [str(paths[name]) + "/" for name in paths]
    expected = "\n".join((
        f"Some {len(good_url)}:{good_url}",
        "None", "None", "None", "Some 0:", "None",
        f"git records its origin as `{good_url}`",
        no_origin, no_origin,
    )) + "\n"
    report = {
        "compiler_sha256": digest(compiler),
        "pkg_source_sha256": source_hash,
        "main_source_sha256": main_hash,
        "positive": {}, "controls": {}, "refusals": {},
        "limits": ["Host O0/O2 with allocation poisoning; this does not test git or network access."],
    }

    def modules(label, pkg_source):
        folder = work / (label + "-core")
        folder.mkdir()
        for path in (root / "core").iterdir():
            dest = folder / path.name
            if path.name == "pkg.ax":
                dest.write_text(pkg_source)
            else:
                dest.symlink_to(path, target_is_directory=path.is_dir())
        return dict(os.environ, AXIOM_PATH=str(folder), AXIOM_STDLIB=str(root / "stdlib"))

    def build_and_run(label, level, pkg_source):
        env = modules(label, pkg_source)
        target = work / label
        built = subprocess.run(
            [str(compiler), "--diagnostic-format=ai", "build", str(fixture),
             "--opt", str(level), "--alloc-poison", "-o", str(target)],
            env=env, capture_output=True, text=True, timeout=240,
        )
        assert built.returncode == 0, (label, built.stderr)
        got = subprocess.run([str(target), *args], env=env, capture_output=True,
                             text=True, timeout=30)
        assert got.returncode == 0 and got.stderr == "", (label, got)
        return got.stdout

    for level in (0, 2):
        label = "origin-O" + str(level)
        observed = build_and_run(label, level, source)
        assert observed == expected, (label, observed, expected)
        report["positive"][label] = observed
        print(f"ok   origin Options O{level}: present, missing, empty and unreadable", flush=True)

    controls = {
        "skip-url-scan": (
            '    (let mut inOrigin 0)\n    (let mut found (:: None (Option String)))',
            '    (let mut inOrigin 0)\n    (let mut found (:: (Some "") (Option String)))',
            0,
        ),
        "forge-read-error": (
            '    ((Err _) None)',
            '    ((Err _) (Some ""))',
            1,
        ),
    }
    for label, (before, after, changed_line) in controls.items():
        assert source.count(before) == 1, label
        observed = build_and_run(label, 0, source.replace(before, after, 1))
        assert observed != expected, label
        assert observed.splitlines()[changed_line] != expected.splitlines()[changed_line], label
        report["controls"][label] = observed.splitlines()[changed_line]
        print(f"ok   {label}: effective counterexample", flush=True)

    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    refusals = {
        "raw-origin": ("(pkgOrigin \"missing/\")", "AX3004"),
        "raw-origin-why": ("(pkgOriginWhy \"\" \"url\")", "AX3004"),
        "missing-none": ("(match (pkgOrigin \"missing/\") ((Some url) url))", "AX3005"),
        "missing-some": ("(match (pkgOrigin \"missing/\") ((None) \"\"))", "AX3005"),
    }
    for label, (expr, code) in refusals.items():
        path = work / (label + ".ax")
        effect = "" if label == "raw-origin-why" else ";@axiom:effect(io)\n"
        path.write_text(
            "(import pkg)\n(:: bad String)\n" + effect +
            "(fn (bad) " + expr + ")\n(:: main Int) (fn (main) 0)\n"
        )
        got = subprocess.run([str(compiler), "--diagnostic-format=ai", "check", str(path)],
                             env=env, capture_output=True, text=True, timeout=90)
        errors = [line for line in got.stderr.splitlines() if line.startswith("E ")]
        assert got.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
            label, got.returncode, got.stderr
        )
        report["refusals"][label] = errors[0]
        print(f"ok   {label}: {code}", flush=True)

    assert digest(compiler) == report["compiler_sha256"]
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
        with tempfile.TemporaryDirectory(prefix="axiom-pkg-origin-") as temp:
            check(args.axiom.resolve(), root, Path(temp))


if __name__ == "__main__":
    main()
