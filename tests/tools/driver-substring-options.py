#!/usr/bin/env python3
"""Check typed substring and Cargo manifest absence in the native driver."""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile


FIND_OUTPUT = """Some 0
Some 2
None
Some 0
Some 3
None
None
Some 0
None
bad
bad
windows-aarch64
true
false
1
"""


def call(argv, env):
    return subprocess.run(argv, env=env, capture_output=True, text=True, timeout=120)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/tools/driver-substring-options.axp"
    source = (root / "core/driver.ax").read_text()
    env = dict(os.environ, AXIOM_PATH=str(root / "core"),
               AXIOM_STDLIB=str(root / "stdlib"))

    with tempfile.TemporaryDirectory(prefix="axiom-driver-substring-options-") as directory:
        work = Path(directory)

        def native(label, level, local=env):
            output = work / label
            built = call([compiler, "--diagnostic-format=ai", "build", str(fixture),
                          "--opt", str(level), "--alloc-poison", "--output", str(output)], local)
            assert built.returncode == 0, (label, built.returncode, built.stderr)
            return output

        for level in (0, 2):
            binary = native(f"positive-O{level}", level)
            found = call([str(binary), "find"], env)
            assert (found.returncode, found.stdout, found.stderr) == (0, FIND_OUTPUT, ""), found
            print(f"ok   substring Option callers O{level}", flush=True)

            manifests = work / f"manifests-O{level}"
            manifests.mkdir()
            missing = manifests / "missing"
            valid = manifests / "valid"
            empty = manifests / "empty"
            malformed = manifests / "malformed"
            unreadable = manifests / "unreadable"
            valid.write_text('[package]\nname = "demo"\n')
            empty.write_text('[package]\nname = ""\n')
            malformed.write_text('[package]\nwrong = "x"\n')
            unreadable.mkdir()
            cases = ((missing, "Ok None\n"), (valid, "Ok Some 4:demo\n"),
                     (empty, "Ok Some 0:\n"), (malformed, "Ok None\n"),
                     (unreadable, "Err 21\n"))
            for path, expected in cases:
                got = call([str(binary), "cargo", str(path)], env)
                assert (got.returncode, got.stdout, got.stderr) == (0, expected, ""), (path, got)
            for name in ("no-manifest", "empty-name"):
                crate = manifests / name
                crate.mkdir()
                if name == "empty-name":
                    (crate / "Cargo.toml").write_text('[package]\nname = ""\n')
                got = call([str(binary), "prepare", str(crate)], env)
                assert (got.returncode, got.stdout, got.stderr) == (0, "", ""), (name, got)
            badcrate = manifests / "read-error"
            badcrate.mkdir()
            (badcrate / "Cargo.toml").mkdir()
            got = call([str(binary), "prepare", str(badcrate)], env)
            expected = f"error: could not read file '{badcrate}/Cargo.toml': Is a directory\n"
            assert (got.returncode, got.stdout, got.stderr) == (1, "", expected), got
            print(f"ok   Cargo Result/Option and prepare refusal O{level}", flush=True)

        refusals = {
            "substring-payload": ("Int", '(strFindSub "abc" "a" 0)', "AX3004"),
            "cargo-payload": ("String", '(cargoPackageName "no-file")', "AX3004"),
            "missing-none": ("Int", '(match (strFindSub "abc" "x" 0) ((Some at) at))', "AX3005"),
            "missing-some": ("Int", '(match (strFindSub "abc" "x" 0) ((None) 0))', "AX3005"),
        }
        for label, (typ, expr, code) in refusals.items():
            program = work / (label + ".ax")
            effect = ";@axiom:effect(io)\n" if label == "cargo-payload" else ""
            program.write_text("(import core)\n(import driver)\n"
                               f"(:: bad {typ})\n{effect}(fn (bad) {expr})\n"
                               "(:: main Int) (fn (main) 0)\n")
            checked = call([compiler, "--diagnostic-format=ai", "check", str(program)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                label, checked.returncode, checked.stderr)
            print(f"ok   {label}: {code}", flush=True)

        mutations = (
            ("drop-empty-needle", '      (Some from)\n      (if (let (Some i)',
             '      None\n      (if (let (Some i)', "find", FIND_OUTPUT),
            ("drop-present-needle", '          (Some i)\n          (strFindSub hay needle (+ i 1))',
             '          None\n          (strFindSub hay needle (+ i 1))', "find", FIND_OUTPUT),
            ("discard-cargo-read-error", '        (Err e))\n    )\n    ((Ok text)',
             '        (Ok None))\n    )\n    ((Ok text)', "cargo", "Err 21\n"),
        )
        for label, old, new, mode, expected in mutations:
            assert source.count(old) == 1, (label, source.count(old))
            overlay = work / (label + "-core")
            overlay.mkdir()
            for item in (root / "core").iterdir():
                dst = overlay / item.name
                if item.name == "driver.ax":
                    dst.write_text(source.replace(old, new))
                else:
                    dst.symlink_to(item, target_is_directory=item.is_dir())
            changed = native(label, 0, dict(env, AXIOM_PATH=str(overlay)))
            if mode == "find":
                observed = call([str(changed), "find"], env)
                assert observed.returncode == 0 and observed.stdout != expected, (label, observed)
            else:
                bad = work / "bad-config"
                bad.mkdir()
                observed = call([str(changed), "cargo", str(bad)], env)
                assert observed.returncode == 0 and observed.stdout != expected, (label, observed)
            print(f"ok   {label}: effective mutation", flush=True)


if __name__ == "__main__":
    main()
