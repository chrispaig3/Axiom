#!/usr/bin/env python3
"""Run actual symbol-ledger scope, capture and application ownership probes."""
import argparse
import os
from pathlib import Path
import runpy
import tempfile


SUPPORT = runpy.run_path(str(Path(__file__).with_name("emitter-line-buffer.py")))
run_checked = SUPPORT["run_checked"]
replace_once = SUPPORT["replace_once"]
check_output = SUPPORT["check_output"]


def check(axiom, repo, work):
    fixture = repo / "tests/selfhost/emitter-symbol-scope.ax"
    expected = fixture.with_suffix(".out").read_text().splitlines()
    if expected != [f"{i} true" for i in range(1, 44)]:
        raise RuntimeError("update the explicit 43-case assertion count")
    env = dict(os.environ, AXIOM_PATH=str(repo / "core"), AXIOM_STDLIB=str(repo / "stdlib"))

    def build_run(label, level, modules, negative=()):
        binary = work / label
        local = dict(env, AXIOM_PATH=str(modules))
        run_checked(
            [str(axiom), "build", str(fixture), "--opt", str(level), "--alloc-poison",
             "--diagnostic-format=ai", "-o", str(binary)],
            env=local, stdout=work / f"{label}.build.stdout", stderr=work / f"{label}.build.stderr",
        )
        output = work / f"{label}.stdout"
        run_checked([str(binary)], env=local, stdout=output, stderr=work / f"{label}.stderr", timeout=30)
        return check_output(output, expected, required_failures=negative)

    for level in (0, 2):
        build_run(f"positive-O{level}", level, repo / "core")
        print(f"ok   emitter symbol scopes: 43 cases at -O{level} with allocation poisoning", flush=True)

def declare_unsafe(source, name):
    """Tag fn `name` as performing an erasure, in a variant only."""
    begin = source.rindex('\n', 0, source.index(f'fn ({name} ')) + 1
    return source[:begin] + ';@axiom:effect(unsafe)\n' + source[begin:]

    original = (repo / "core/codegen.ax").read_text()
    binding = original
    for slot, reader, value in [(6, "cgSymNames", "name"), (7, "cgSymRegs", "reg"),
                                (16, "cgSymFloats", "isFloat"), (20, "cgSymKinds", "kind")]:
        binding = replace_once(
            binding, f"    (vecPush ({reader} cg) {value})\n",
            f"    (memSetWord (as cg Int) {slot} (vecPush ({reader} cg) {value}))\n",
            f"symbol slot {slot} same-header ablation")
    entry = original
    for slot, reader in [(6, "cgSymNames"), (7, "cgSymRegs"), (16, "cgSymFloats"), (20, "cgSymKinds")]:
        before = f"(vecClear ({reader} cg))"
        if entry.count(before) != 2:
            raise RuntimeError(f"expected two function/lambda reset anchors for slot {slot}")
        entry = entry.replace(before, f"(memSetWord (as cg Int) {slot} vecNew)")
    start = original.index("(pub fn (symRestore cg mark)\n  {\n")
    loop = original.index("    (while (> i mark)", start)
    end = original.index("    (memSetWord (as names Int) 0 mark)", loop)
    restore = original[:loop] + "    (set i mark)\n" + original[end:]
    app = replace_once(original,
        '    (set c.argVec nodesNew)\n    (set c.argEv vecNew)\n',
        '    (memSetWord (as cg Int) 5 nodesNew)\n    (memSetWord (as cg Int) 45 vecNew)\n',
        'typed application slot retirement')
    variants = [
        ("binding-shares", declare_unsafe(binding, 'bindSym'), (2, 4)),
        ("entry-replacement", declare_unsafe(declare_unsafe(entry, 'emitFnDef'), 'emitLamDef'),
         (23, 26, 31, 34)),
        ("restore-retirement", restore, (13, 14, 17, 18, 22)),
        ("application-shares", declare_unsafe(app, 'cgResetAppArgs'), (37, 38)),
    ]
    for label, source, negative in variants:
        modules = work / f"{label}-modules/core"
        modules.mkdir(parents=True, exist_ok=True)
        for path in (repo / "core").iterdir():
            destination = modules / path.name
            if path.name == "codegen.ax":
                destination.write_text(source)
            elif not destination.exists():
                destination.symlink_to(path, target_is_directory=path.is_dir())
        failures = build_run(label, 0, modules, negative)
        print(f"ok   negative probe {label}: cases {','.join(map(str, sorted(failures)))} fail", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--work", type=Path, help="retain logs and private negative modules")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    if args.work:
        work = args.work.resolve()
        work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), repo, work)
    else:
        with tempfile.TemporaryDirectory(prefix="axiom-symbol-scopes-") as directory:
            check(args.axiom.resolve(), repo, Path(directory))


if __name__ == "__main__":
    main()
