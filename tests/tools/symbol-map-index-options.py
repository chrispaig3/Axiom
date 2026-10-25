#!/usr/bin/env python3
"""Check optional symbol indexes, first matches and parallel map columns."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

BRIDGE = '''
(pub :: symbolIndexPut (-> Names Ints String Int Int))
(pub fn (symbolIndexPut names values key value) (saPut names values key value))
(pub :: symbolIndexPutSoft (-> Names Ints String Int Int))
(pub fn (symbolIndexPutSoft names values key value) (saPutSoft names values key value))
(pub :: symbolIndexPutSoft2 (-> Names Ints Ints String Int Int Int))
(pub fn (symbolIndexPutSoft2 names first second key a b) (saPutSoft2 names first second key a b))
'''


def check(compiler, root, work):
    source = (root / "core/symbols.ax").read_text()
    env = dict(os.environ, AXIOM_STDLIB=str(root / "stdlib"))
    report = {"builder": compiler, "builder_sha256": hashlib.sha256(Path(compiler).read_bytes()).hexdigest(),
              "symbols_sha256": hashlib.sha256(source.encode()).hexdigest(), "configurations": [], "controls": [], "refusals": [],
              "limits": ["Host O0/O2 allocation-poisoned checks; GitHub validates full rendered streams and targets.",
                         "Parallel name/value map columns retain their existing required length contract.",
                         "No lifetime algorithm, held work or overall completion claim."]}
    def environment(label, module):
        modules = work / (label + "-modules"); modules.mkdir(exist_ok=True)
        (modules / "symbols.ax").write_text(module + BRIDGE)
        return dict(env, AXIOM_PATH=os.pathsep.join((str(modules), str(root / "core"))))
    def invoke(args, label, local, timeout=180):
        ran = subprocess.run(args, cwd=root, env=local, capture_output=True, text=True, timeout=timeout)
        (work / (label + ".out")).write_text(ran.stdout); (work / (label + ".err")).write_text(ran.stderr)
        return ran
    def build(label, level, local):
        binary = work / (label + "-O" + level)
        ran = invoke([compiler, "--diagnostic-format=ai", "build", str(root / "tests/tools/symbol-map-index-options.axp"),
                      "--opt", level, "--alloc-poison", "-o", str(binary)], binary.name + "-build", local)
        assert ran.returncode == 0, (ran.stdout, ran.stderr)
        return binary
    local = environment("positive", source)
    expected = "".join(f"{i} true\n" for i in range(1, 27))
    for level in ("0", "2"):
        binary = build("symbol-index", level, local)
        ran = invoke([str(binary)], binary.name + "-run", local, 30)
        assert ran.returncode == 0 and not ran.stderr and ran.stdout == expected, (level, ran.returncode, ran.stdout, ran.stderr)
        report["configurations"].append({"opt": level, "allocation_poisoning": True, "outcomes": 26, "status": "passed"})
        print(f"ok   symbol index Options: 26 zero/missing/first-match/map-column outcomes O{level} poison", flush=True)
    seam = "(isNone hit)"
    start = source.index("(pub fn (saIdx ")
    end = source.index("\n\n", start)
    function = source[start:end]
    assert function.count(seam) == 1, "first-match seam changed"
    changed = source[:start] + function.replace(seam, "true") + source[end:]
    bad = environment("last-match", changed)
    binary = build("last-match", "0", bad)
    ran = invoke([str(binary)], "last-match-run", bad, 30)
    assert ran.returncode == 0 and not ran.stderr, (ran.returncode, ran.stderr)
    failed = {int(line.split()[0]) for line in ran.stdout.splitlines() if line.endswith(" false")}
    assert {2, 5, 8, 13} <= failed, failed
    report["controls"].append({"name": "last-match", "failed_cases": sorted(failed)})
    print(f"ok   counterexample last-match: cases {sorted(failed)} fail", flush=True)
    for name, declaration, code in [
        ("erased-index", '(:: bad (-> Names Int)) (fn (bad names) (saIdx names "entry"))', "AX3004"),
        ("missing-index-none", '(:: bad (-> Names Int)) (fn (bad names) (match (saIdx names "entry") ((Some index) index)))', "AX3005"),
    ]:
        path = work / (name + ".ax"); path.write_text("(import core) (import symbols)\n" + declaration + "\n(:: main Int) (fn (main) 0)\n")
        ran = invoke([compiler, "--diagnostic-format=ai", "check", str(path)], name, local)
        errors = [line for line in ran.stderr.splitlines() if line.startswith("E ")]
        assert ran.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (name, ran.stdout, ran.stderr)
        report["refusals"].append({"name": name, "code": code})
    print("ok   symbol indexes: erased and nonexhaustive APIs refused", flush=True)
    (work / "symbol-index-report.json").write_text(json.dumps(report, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("compiler"); parser.add_argument("--work", type=Path)
    args = parser.parse_args(); root = Path(__file__).resolve().parents[2]; compiler = str(Path(args.compiler).resolve())
    if args.work:
        args.work.mkdir(exist_ok=True, parents=True); check(compiler, root, args.work.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix="axiom-symbol-index-") as directory:
            check(compiler, root, Path(directory))


if __name__ == "__main__":
    main()
