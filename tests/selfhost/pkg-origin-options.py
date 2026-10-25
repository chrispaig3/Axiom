#!/usr/bin/env python3
"""Exercise present, absent and unreadable package origins as Result/Option."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
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
        f"Ok Some {len(good_url)}:{good_url}",
        "Ok None", "Ok None", "Ok None", "Ok Some 0:", "Err 21",
        f"git records its origin as `{good_url}`",
        no_origin, no_origin,
    )) + "\n"
    report = {
        "compiler_sha256": digest(compiler),
        "pkg_source_sha256": source_hash,
        "main_source_sha256": main_hash,
        "positive": {}, "controls": {}, "refusals": {},
        "limits": ["Host O0/O2 with allocation poisoning; the CLI probe uses a local file:// git repository."],
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
        print(f"ok   origin Result/Option O{level}: present, missing, empty and unreadable", flush=True)

    controls = {
        "skip-url-scan": (
            '    (let mut inOrigin 0)\n    (let mut found (:: None (Option String)))',
            '    (let mut inOrigin 0)\n    (let mut found (:: (Some "") (Option String)))',
            0,
        ),
        "forge-read-error": (
            '      (if (== (errCode e) 2)\n        (Ok None)\n        (Err e))',
            '      (Ok None)',
            5,
        ),
        "forge-missing-error": (
            '      (if (== (errCode e) 2)\n        (Ok None)\n        (Err e))',
            '      (Err e)',
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
        "missing-err": ("(match (pkgOrigin \"missing/\") ((Ok origin) \"\"))", "AX3005"),
        "missing-ok": ("(match (pkgOrigin \"missing/\") ((Err _) \"\"))", "AX3005"),
        "missing-none": ("(match (pkgOrigin \"missing/\") ((Err _) \"\") ((Ok origin) (match origin ((Some url) url))))", "AX3005"),
        "missing-some": ("(match (pkgOrigin \"missing/\") ((Err _) \"\") ((Ok origin) (match origin ((None) \"\"))))", "AX3005"),
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

    if shutil.which("git"):
        cli = work / "cli"
        repo = cli / "repo"
        app = cli / "app"
        repo.mkdir(parents=True)
        app.mkdir()

        def git(*args):
            got = subprocess.run(["git", *args], cwd=repo, capture_output=True,
                                 text=True, timeout=30)
            assert got.returncode == 0, (args, got.stderr)

        git("init", "-q")
        git("config", "user.email", "test@example.test")
        git("config", "user.name", "Test")
        (repo / "README").write_text("local\n")
        git("add", "README")
        git("commit", "-q", "-m", "seed")
        url = repo.as_uri()
        (app / "axiom.pkg").write_text(f"name test\ndepend {url}\n")
        entry = app / "Main.ax"
        entry.write_text("(:: main Int) (fn (main) 0)\n")

        def command(*args):
            return subprocess.run(
                [str(compiler), "--diagnostic-format=ai", *args],
                cwd=app, env=env, capture_output=True, text=True, timeout=90,
            )

        first = command("fetch")
        assert first.returncode == 0 and first.stdout.startswith("fetching "), first
        configs = list((app / ".axiom/deps").glob("*/.git/config"))
        assert len(configs) == 1, configs
        config = configs[0]
        checkout = config.parents[1]
        present_fetch = command("fetch")
        dest = "./" + str(checkout.relative_to(app)) + "/"
        assert (present_fetch.returncode, present_fetch.stdout, present_fetch.stderr) == (
            0, f"present {dest}\n", ""
        ), present_fetch
        build_args = ("build", "--input", str(entry), "--output", str(app / "out"))
        present_build = command(*build_args)
        assert present_build.returncode == 0 and (app / "out").is_file(), present_build

        config.unlink()
        missing_fetch = command("fetch")
        missing_build = command(*build_args)
        assert (missing_fetch.returncode, missing_fetch.stdout, missing_fetch.stderr) == (
            4, "", f"error: `{dest}` is not a checkout of `{url}`: {no_origin}.\n"
                   "       Remove it and run `axiom fetch` again.\n"
        ), missing_fetch
        assert (missing_build.returncode, missing_build.stdout, missing_build.stderr) == (
            3, "", f"error: {app / 'axiom.pkg'} depends on a registry URL whose checkout is not a clone of it:\n"
                   f"       {url}\n       {checkout}/\n       - {no_origin}.\n"
                   "       Remove that directory and run `axiom fetch`.\n"
        ), missing_build

        config.mkdir()
        unreadable_fetch = command("fetch")
        unreadable_build = command(*build_args)
        assert (unreadable_fetch.returncode, unreadable_fetch.stdout, unreadable_fetch.stderr) == (
            4, "", f"error: could not read git config `{dest}.git/config`: errno 21\n"
        ), unreadable_fetch
        assert (unreadable_build.returncode, unreadable_build.stdout, unreadable_build.stderr) == (
            3, "", f"error: could not read git config `{checkout}/.git/config`: errno 21\n"
        ), unreadable_build
        report["cli"] = {
            "present": [present_fetch.returncode, present_build.returncode],
            "missing": [missing_fetch.returncode, missing_build.returncode],
            "unreadable": [unreadable_fetch.returncode, unreadable_build.returncode],
        }
        print("ok   fetch/build: present 0/0, missing 4/3, unreadable 4/3", flush=True)
    else:
        report["cli"] = "skipped: git unavailable"
        print("SKIP fetch/build origin round trip (git unavailable)", flush=True)

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
