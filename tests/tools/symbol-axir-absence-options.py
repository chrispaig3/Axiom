#!/usr/bin/env python3
"""Check typed symbol and AXIR absence before their wire encodings."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


EXPECTED = "".join(f"{index} true\n" for index in range(1, 25))


def run(args, env, root, timeout=180):
    return subprocess.run(args, cwd=root, env=env, capture_output=True, text=True,
                          timeout=timeout)


def check(compiler, root, work):
    fixture = root / "tests/tools/symbol-axir-absence-options.axp"
    sources = {name: (root / "core" / (name + ".ax")).read_text()
               for name in ("symbols", "axir")}
    source_hashes = {name: hashlib.sha256(text.encode()).hexdigest()
                     for name, text in sources.items()}
    report = {"compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
              "source_sha256": source_hashes, "positive": {}, "controls": {},
              "refusals": {},
              "limits": ["Host O0/O2 with allocation poisoning; complete AXSYM/AXIR streams run in CI.",
                         "The AXSYM and AXIR wire spellings remain '-' for no location and omit an absent NID."]}
    base_env = dict(os.environ, AXIOM_STDLIB=str(root / "stdlib"))

    def environment(label, changed=None):
        folder = work / (label + "-modules")
        folder.mkdir()
        for path in (root / "core").iterdir():
            destination = folder / path.name
            if changed and path.name == changed[0] + ".ax":
                destination.write_text(changed[1])
            else:
                destination.symlink_to(path, target_is_directory=path.is_dir())
        return dict(base_env, AXIOM_PATH=str(folder))

    def build_run(label, level, env):
        binary = work / label
        built = run([str(compiler), "--diagnostic-format=ai", "build", str(fixture),
                     "--opt", str(level), "--alloc-poison", "-o", str(binary)],
                    env, root, 240)
        assert built.returncode == 0, (label, built.returncode, built.stdout, built.stderr)
        result = run([str(binary)], env, root, 30)
        assert result.returncode == 0 and not result.stderr, (
            label, result.returncode, result.stdout, result.stderr)
        return result.stdout

    positive = environment("positive")
    for level in (0, 2):
        actual = build_run(f"positive-O{level}", level, positive)
        assert actual == EXPECTED, (level, actual)
        report["positive"][f"O{level}"] = 24
        print(f"ok   symbol/AXIR Option O{level}: 24 cases", flush=True)

    # Change a single arm in a source overlay. Every mutation must compile
    # and make the corresponding missing-case result false.
    controls = (
        ("invent-symbol-location", "symbols", "smLocReal", "((None) None)",
         '((None) (Some ""))', {5, 8}),
        ("invent-symbol-nid", "symbols", "smNidFor", "((None) None)",
         '((None) (Some ""))', {1}),
        ("invent-axir-op", "axir", "axirOpLine", "        None))))",
         '        (Some "")))))', {14, 23, 24}),
        ("invent-axir-term", "axir", "axirTermLine", "            None))))))",
         '            (Some "")))))))', {20}),
    )
    for label, module, symbol, old, new, expected_failures in controls:
        text = sources[module]
        start = text.index("(pub fn (" + symbol + " ")
        end = text.index("\n\n", start)
        before = text[start:end]
        assert before.count(old) == 1, (label, before.count(old))
        changed = text[:start] + before.replace(old, new) + text[end:]
        actual = build_run(label, 0, environment(label, (module, changed)))
        failures = {int(line.split()[0]) for line in actual.splitlines()
                    if line.endswith(" false")}
        assert expected_failures <= failures, (label, sorted(failures))
        report["controls"][label] = sorted(failures)
        print(f"ok   {label}: failed {sorted(failures)}", flush=True)

    imports = "(import core) (import parser) (import symbols) (import mir) (import axir) (import Vec)\n"
    inst = '(MInst :op 99 :dst 0 :a 0 :b 0 :name "" :args vecNew :tgt 0 :alt 0)'
    refusals = (
        ("raw-location", "String", '(smLocReal smNew 0 1 2 "missing" vecNew)', "AX3004"),
        ("raw-nid", "String", '(smNidFor smNew "missing")', "AX3004"),
        ("raw-op", "String", f"(axirOpLine {inst})", "AX3004"),
        ("raw-term", "String", f"(axirTermLine {inst})", "AX3004"),
        ("missing-location-arm", "String",
         '(match (smLocReal smNew 0 1 2 "missing" vecNew) ((Some value) value))', "AX3005"),
        ("missing-nid-arm", "String",
         '(match (smNidFor smNew "missing") ((None) ""))', "AX3005"),
        ("missing-op-arm", "String",
         f'(match (axirOpLine {inst}) ((Some value) value))', "AX3005"),
        ("missing-term-arm", "String",
         f'(match (axirTermLine {inst}) ((None) ""))', "AX3005"),
    )
    for label, result_type, expr, code in refusals:
        path = work / (label + ".ax")
        path.write_text(imports + f"(:: bad {result_type}) (fn (bad) {expr})\n"
                        + "(:: main Int) (fn (main) 0)\n")
        checked = run([str(compiler), "--diagnostic-format=ai", "check", str(path)],
                      positive, root)
        errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
        assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
            label, checked.returncode, checked.stdout, checked.stderr)
        report["refusals"][label] = code
        print(f"ok   {label}: {code}", flush=True)

    assert hashlib.sha256(compiler.read_bytes()).hexdigest() == report["compiler_sha256"]
    for name, digest in source_hashes.items():
        assert hashlib.sha256((root / "core" / (name + ".ax")).read_bytes()).hexdigest() == digest
    (work / "symbol-axir-options-report.json").write_text(json.dumps(report, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", required=True, type=Path)
    parser.add_argument("--work", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = args.axiom.resolve()
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True)
        check(compiler, root, args.work.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix="axiom-symbol-axir-options-") as directory:
            check(compiler, root, Path(directory))


if __name__ == "__main__":
    main()
