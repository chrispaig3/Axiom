#!/usr/bin/env python3
"""Verify unsafe witness Options, selection goldens and effective counterexamples."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

BASE = "e173a9ab1315b309f46262bc5f7958e5693ff5fa"
COUNT = 28
# Captured and byte-verified against the immutable e173 checker at O0/O2 poison.
BASE_DIAGNOSTICS = (
    'E AX3073 unsafe-primitive.ax:2:17-24 undeclared-unsafe "`main` touches raw memory and its declaration does not say so" #"__load8" ?2:1:"write `;@axiom:effect(unsafe)` above the declaration"~>";@axiom:effect(unsafe)\\n" ?"the unsafe tag marks a trusted boundary: you must make every well-typed call safe. It leaves ordinary type, effect and restriction checks in place"\n'
    'E AX3042 unsafe-extern.ax:3:10-14 undeclared-effect "`main` performs IO and its declaration does not say so" !"effects are INFERRED transitively, so this fires on every function up the call chain, and each one is a place a reader would otherwise have to open the callee to learn it. If the effect is not wanted here the fix is to stop performing it, not to stop saying so. `IO`, `Entropy`, `Spawn` and `Block` are required; `Alloc` and `Mut` are ambient and never need declaring" ?3:1:"write `;@axiom:effect(io)` above the declaration"~>";@axiom:effect(io)\\n"\n'
    'E AX3073 unsafe-extern.ax:3:17-24 undeclared-unsafe "`main` calls extern `outside`, whose implementation is outside the safety checker, and its declaration does not say so" #"an extern call" ?3:1:"write `;@axiom:effect(unsafe)` above the declaration"~>";@axiom:effect(unsafe)\\n" ?"the unsafe tag marks a trusted boundary: you must make every well-typed call safe. It leaves ordinary type, effect and restriction checks in place"\n'
    'E AX3073 unsafe-forge.ax:3:19-21 undeclared-unsafe "`main` forges `Hid` out of `Int` with `as`, and its declaration does not say so" #"forges a reference" ^3:22-23:"source has type `Int`; the conversion trusts its representation" ?3:1:"write `;@axiom:effect(unsafe)` above the declaration"~>";@axiom:effect(unsafe)\\n" ?"prefer a constructor or a typed library operation. For a raw conversion, prove the target\'s layout and validity, and keep its backing owner alive. Changing the type does not extend a region\'s scope" ?"the unsafe tag marks a trusted boundary: you must make every well-typed call safe. It leaves ordinary type, effect and restriction checks in place"\n'
    'E AX3042 unsafe-mixed-order.ax:4:10-14 undeclared-effect "`main` performs IO and its declaration does not say so" !"effects are INFERRED transitively, so this fires on every function up the call chain, and each one is a place a reader would otherwise have to open the callee to learn it. If the effect is not wanted here the fix is to stop performing it, not to stop saying so. `IO`, `Entropy`, `Spawn` and `Block` are required; `Alloc` and `Mut` are ambient and never need declaring" ?4:1:"write `;@axiom:effect(io)` above the declaration"~>";@axiom:effect(io)\\n"\n'
    'E AX3073 unsafe-mixed-order.ax:4:19-26 undeclared-unsafe "`main` calls extern `outside`, whose implementation is outside the safety checker, and its declaration does not say so" #"an extern call" ?4:1:"write `;@axiom:effect(unsafe)` above the declaration"~>";@axiom:effect(unsafe)\\n" ?"the unsafe tag marks a trusted boundary: you must make every well-typed call safe. It leaves ordinary type, effect and restriction checks in place"\n'
    'E AX3042 unsafe-forge-first.ax:4:10-14 undeclared-effect "`main` performs IO and its declaration does not say so" !"effects are INFERRED transitively, so this fires on every function up the call chain, and each one is a place a reader would otherwise have to open the callee to learn it. If the effect is not wanted here the fix is to stop performing it, not to stop saying so. `IO`, `Entropy`, `Spawn` and `Block` are required; `Alloc` and `Mut` are ambient and never need declaring" ?4:1:"write `;@axiom:effect(io)` above the declaration"~>";@axiom:effect(io)\\n"\n'
    'E AX3073 unsafe-forge-first.ax:4:19-21 undeclared-unsafe "`main` forges `Hid` out of `Int` with `as`, and its declaration does not say so" #"forges a reference" ^4:22-23:"source has type `Int`; the conversion trusts its representation" ?4:1:"write `;@axiom:effect(unsafe)` above the declaration"~>";@axiom:effect(unsafe)\\n" ?"prefer a constructor or a typed library operation. For a raw conversion, prove the target\'s layout and validity, and keep its backing owner alive. Changing the type does not extend a region\'s scope" ?"the unsafe tag marks a trusted boundary: you must make every well-typed call safe. It leaves ordinary type, effect and restriction checks in place"\n'
)
CONTROLS = [
    ("missing-site", "unsafeFirstSite", "(set best (Some i))", "(set best None)", 2),
    ("last-tie", "unsafeFirstSite", "(< (spanStart sp) bestAt)", "(<= (spanStart sp) bestAt)", 4),
    ("missing-start", "unsafeSiteStart", "(Some (spanStart (spanOf (vecGet v (* index stride)))))", "None", 7),
    ("extern-before-primitive", "unsafeEarliestKind", "(Some 0)", "(Some 1)", 15),
    ("maximum-start", "unsafeMinStart", "(< right left)", "(> right left)", 12),
    ("forge-stride", "checkUndeclaredUnsafe", "(vecGet forges (* index 3))", "(vecGet forges index)", 24),
]


def build(compiler, root, env, source, output, level):
    result = subprocess.run(
        [str(compiler), "--diagnostic-format=ai", "build", str(source),
         "--opt", level, "--alloc-poison", "--output", str(output)],
        cwd=root, env=env, capture_output=True, text=True, timeout=240,
    )
    assert result.returncode == 0, (source, level, result.returncode, result.stdout, result.stderr)


def run(output):
    result = subprocess.run([str(output)], capture_output=True, text=True, timeout=45)
    assert result.returncode == 0 and not result.stderr, (output, result.returncode, result.stdout, result.stderr)
    assert "PARSE_FAILURE" not in result.stdout, result.stdout
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler", type=Path)
    parser.add_argument("--negative-controls", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = args.compiler.resolve()
    source = root / "tests/selfhost/typecheck-unsafe-site-options.axp"
    original = (root / "core/typecheck.ax").read_bytes()
    source_hash = hashlib.sha256(original).hexdigest()
    expected = "".join(f"{index} true\n" for index in range(1, COUNT + 1))
    records = {"base": BASE, "compiler": str(compiler), "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
               "typecheck_sha256": source_hash, "baseline_diagnostics_sha256": hashlib.sha256(BASE_DIAGNOSTICS.encode()).hexdigest(), "cases": COUNT, "levels": [], "refusals": [], "negative_controls": []}
    with tempfile.TemporaryDirectory(prefix="axiom-unsafe-site-options-") as directory:
        work = Path(directory)
        candidate_core = work / "candidate-core/core"
        candidate_core.mkdir(parents=True)
        for path in (root / "core").iterdir():
            if path.is_file() and path.name != "typecheck.ax":
                (candidate_core / path.name).symlink_to(path)
        (candidate_core / "typecheck.ax").write_bytes(original)
        env = dict(os.environ, AXIOM_STDLIB=str(root / "stdlib"), AXIOM_PATH=str(candidate_core))
        for level in ("0", "2"):
            candidate = work / f"candidate-O{level}"
            build(compiler, root, env, source, candidate, level)
            actual = run(candidate)
            prefix, actual_diagnostics = actual.split("DIAGNOSTICS\n", 1)
            assert prefix == expected, (level, prefix)
            assert actual_diagnostics == BASE_DIAGNOSTICS, (level, actual_diagnostics, BASE_DIAGNOSTICS)
            assert actual_diagnostics.count("E AX3073 ") >= 5, actual_diagnostics
            assert 'source has type `Int`; the conversion trusts its representation' in actual_diagnostics
            assert ';@axiom:effect(unsafe)\\n' in actual_diagnostics
            records["levels"].append({"opt": level, "alloc_poison": True,
                                      "diagnostics_sha256": hashlib.sha256(actual_diagnostics.encode()).hexdigest()})
            print(f"O{level} poison: {COUNT} cases and real-consumer diagnostics match e173 baseline", flush=True)
        refusals = {
            "erased-first": ('(:: bad (-> Nodes Int)) (fn (bad sites) (unsafeFirstSite sites 1))', "AX3004"),
            "erased-index": ('(:: bad (-> Nodes (Option Int))) (fn (bad sites) (unsafeSiteStart sites 0 1))', "AX3004"),
            "erased-start": ('(:: bad (Option Int)) (fn (bad) (unsafeEarliestKind 0 None None))', "AX3004"),
            "missing-first-none": ('(:: bad (-> Nodes Int)) (fn (bad sites) (match (unsafeFirstSite sites 1) ((Some index) index)))', "AX3005"),
            "missing-kind-none": ('(:: bad Int) (fn (bad) (match (unsafeEarliestKind None None None) ((Some kind) kind)))', "AX3005"),
        }
        for name, (declaration, code) in refusals.items():
            refusal = work / f"{name}.ax"
            refusal.write_text("(import core)\n(import typecheck)\n" + declaration + "\n(:: main Int) (fn (main) 0)\n")
            checked = subprocess.run([str(compiler), "--diagnostic-format=ai", "check", str(refusal)],
                                     cwd=root, env=env, capture_output=True, text=True, timeout=60)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (name, checked.returncode, checked.stdout, checked.stderr)
            records["refusals"].append({"name": name, "code": code})
        print("5 typed/missing-None refusals passed", flush=True)
        if args.negative_controls:
            text = original.decode()
            for name, function, old, replacement, first_false in CONTROLS:
                start = text.index(f"(pub fn ({function} ")
                end = text.index("\n\n", start)
                body = text[start:end]
                assert body.count(old) == 1, (name, function, old)
                (candidate_core / "typecheck.ax").write_text(text[:start] + body.replace(old, replacement) + text[end:])
                executable = work / name
                build(compiler, root, env, source, executable, "0")
                actual = run(executable).split("DIAGNOSTICS\n", 1)[0]
                lines = actual.splitlines()
                assert len(lines) == COUNT and lines[first_false - 1] == f"{first_false} false", (name, lines)
                assert all(line == f"{index} true" for index, line in enumerate(lines[:first_false - 1], 1)), (name, lines)
                records["negative_controls"].append({"name": name, "first_false": first_false})
                print(f"{name}: effective mutation first fails case {first_false}", flush=True)
        assert (root / "core/typecheck.ax").read_bytes() == original, "root source changed during snapshot validation"
    if args.report:
        args.report.write_text(json.dumps(records, indent=2) + "\n")
    print(f"ok unsafe-site Options: O0/O2 poison, e173 diagnostic parity, 5 refusals; {len(records['negative_controls'])} effective mutations")


if __name__ == "__main__":
    main()
