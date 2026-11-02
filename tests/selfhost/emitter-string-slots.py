#!/usr/bin/env python3
"""Exercise the actual private CG String-slot setters and their alias ledger."""
import argparse
import os
from pathlib import Path
import re
import runpy
import tempfile


SUPPORT = runpy.run_path(str(Path(__file__).with_name("emitter-line-buffer.py")))
run_checked = SUPPORT["run_checked"]
replace_once = SUPPORT["replace_once"]
check_output = SUPPORT["check_output"]
check_typed_slot = SUPPORT["check_typed_slot"]
raw_setter = SUPPORT["raw_setter"]

BRIDGES = r'''
; Private-copy-only probes: no production raw setter is exported.
(pub :: probeSetResult (-> CG String CG))
(pub fn (probeSetResult cg value) (cgSetResult cg value))
(pub :: probeSetArgsTyped (-> CG String CG))
(pub fn (probeSetArgsTyped cg value) (cgSetArgsTyped cg value))
(pub :: probeSetBlock (-> CG String CG))
(pub fn (probeSetBlock cg value) (cgSetBlock cg value))
(pub :: probeSetRawResult (-> CG Int CG))
;@axiom:effect(unsafe)
(pub fn (probeSetRawResult cg value) (cgSetResult cg (as value String)))
(pub :: probeSetRawArgsTyped (-> CG Int CG))
;@axiom:effect(unsafe)
(pub fn (probeSetRawArgsTyped cg value) (cgSetArgsTyped cg (as value String)))
(pub :: probeSameArgsGetter (-> CG String Bool))
(pub fn (probeSameArgsGetter cg expected)
  { (let value (memGetWordStr (as cg Int) 9)) (cgSetArgsTyped cg value) (strEq value expected) })
(pub :: probeGetterCount (-> CG Int Int))
;@axiom:effect(unsafe)
(pub fn (probeGetterCount cg index)
  { (let value (memGetWordStr (as cg Int) index)) (__load64 (as value Int) -2) })
(pub :: probeSameResultGetter (-> CG String Bool))
(pub fn (probeSameResultGetter cg expected)
  { (let value (memGetWordStr (as cg Int) 2)) (cgSetResult cg value) (strEq value expected) })

; This raw leaf descriptor has count0 and static bytes. The actual typed
; setter creates its sole managed share; no ordinary String share is released
; by a test helper. It is used only for retain-before-release ordering.
(:: probeStaticString Int)
(fn (probeStaticString)
  {
    (let header (memAlloc 24))
    (memSetWord header 0 8)
    (memSetWord header 1 (strData "raw-slot"))
    (memSetWord header 2 0)
    header
  })
(pub :: probeSoleResultSame Bool)
;@axiom:effect(unsafe)
(pub fn (probeSoleResultSame)
  {
    (let cg newCG)
    (let header (probeStaticString))
    (cgSetResult cg (as header String))
    (let sole (== (__load64 header -2) 1))
    (let filed (__axiom_mem_stat 1))
    (cgSetResult cg (as header String))
    (if (!= (__axiom_mem_stat 1) filed)
      false
      (&& sole (== (__load64 header -2) 1)))
  })
(pub :: probeSoleBlockSame Bool)
;@axiom:effect(unsafe)
(pub fn (probeSoleBlockSame)
  {
    (let cg newCG)
    (let header (probeStaticString))
    (cgSetBlock cg (as header String))
    (let sole (== (__load64 header -2) 1))
    (let filed (__axiom_mem_stat 1))
    (cgSetBlock cg (as header String))
    (if (!= (__axiom_mem_stat 1) filed)
      false
      (&& sole (== (__load64 header -2) 1)))
  })
(pub :: probeSoleArgsSame Bool)
;@axiom:effect(unsafe)
(pub fn (probeSoleArgsSame)
  {
    (let cg newCG)
    (let header (probeStaticString))
    (cgSetArgsTyped cg (as header String))
    (let sole (== (__load64 header -2) 1))
    (let filed (__axiom_mem_stat 1))
    (cgSetArgsTyped cg (as header String))
    (if (!= (__axiom_mem_stat 1) filed)
      false
      (&& sole (== (__load64 header -2) 1)))
  })
'''


def emitted_function(module, name):
    match = re.search(r'^define [^\n]*@' + re.escape(name)
                      + r'\([^\n]*\) [^\n]*\{\n.*?^\}', module, re.M | re.S)
    if match is None:
        raise RuntimeError(f"missing actual emitted function {name}")
    return match.group()


def check_args_routes(binary):
    module = Path(str(binary) + ".ll").read_text()
    setter = emitted_function(module, "codegen$cgSetArgsTyped")
    check_typed_slot(setter, 9, '%value')
    for name in ("emitArgsRegs", "emitArgsList"):
        body = emitted_function(module, "codegen$" + name)
        if body.count("@codegen$cgSetArgsTyped(") != 3:
            raise RuntimeError(f"{name}: expected empty/single/multiple String setter routes")
        if re.search(r'@raw\$memSetWord\(i64 [^,]+, i64 9,', body):
            raise RuntimeError(f"{name}: unbalanced direct argument-slot writer remains")


def check(axiom, repo, work):
    source = repo / "tests/selfhost/emitter-string-slots.axp"
    fixture = work / source.with_suffix(".ax").name
    fixture.write_bytes(source.read_bytes())
    expected = source.with_suffix(".out").read_text().splitlines()
    if expected != [f"{i} true" for i in range(1, 64)]:
        raise RuntimeError("update the explicit 63-case assertion count")
    env = dict(os.environ, AXIOM_PATH=str(repo / "core"), AXIOM_STDLIB=str(repo / "stdlib"))
    original = (repo / "core/codegen.ax").read_text()

    run_checked([str(axiom), "--diagnostic-format=ai", "fmt", "--check", str(fixture)],
                env=env, stdout=work / "fixture.fmt.stdout", stderr=work / "fixture.fmt.stderr")

    def build_run(label, level, source, negative=()):
        modules = work / f"{label}-modules/core"
        modules.mkdir(parents=True, exist_ok=True)
        for path in (repo / "core").iterdir():
            destination = modules / path.name
            if path.name == "codegen.ax":
                destination.write_text(source + BRIDGES)
            elif not destination.exists():
                destination.symlink_to(path, target_is_directory=path.is_dir())
        binary = work / label
        local = dict(env, AXIOM_PATH=str(modules))
        run_checked(
            [str(axiom), "build", str(fixture), "--opt", str(level), "--alloc-poison",
             "--emit-llvm", "--diagnostic-format=ai", "-o", str(binary)],
            env=local, stdout=work / f"{label}.build.stdout", stderr=work / f"{label}.build.stderr",
        )
        output = work / f"{label}.stdout"
        error = work / f"{label}.stderr"
        run_checked([str(binary)], env=local, stdout=output, stderr=error, timeout=30)
        failures = check_output(output, expected, required_failures=negative)
        if not negative:
            check_args_routes(binary)
        growth = re.fullmatch(r"ordinary-soak-growth (-?\d+)\nargs-ordinary-soak-growth (-?\d+)\n", error.read_text())
        if growth is None:
            raise RuntimeError(f"{label}: missing ordinary String ownership diagnostic: {error.read_text()!r}")
        return failures, (int(growth[1]), int(growth[2]))

    for level in (0, 2):
        _, growth = build_run(f"positive-O{level}", level, original)
        print(f"ok   emitter String slots: 63 cases at -O{level} with allocation poisoning", flush=True)
        print(f"note ordinary result/args overwrite live-storage growth at -O{level}: {growth} bytes", flush=True)

    no_retire = original
    release_first = original
    for name, slot in (("cgSetResult", 2), ("cgSetBlock", 11), ("cgSetArgsTyped", 9)):
        field = {2: 'result', 11: 'curBlock', 9: 'argsTyped'}[slot]
        no_retire = raw_setter(no_retire, name, field, slot)
        release_first = raw_setter(release_first, name, field, slot, release_first=True)

    for label, source, negative in [
        ("no-retirement", no_retire, (9, 14, 24, 25, 32, 38, 45, 46, 62)),
        ("release-first", release_first, (30, 31, 63)),
    ]:
        failures, growth = build_run(label, 0, source, negative)
        print(f"ok   negative probe {label}: cases {','.join(map(str, sorted(failures)))} fail", flush=True)
        print(f"note ordinary result/args overwrite live-storage growth in {label}: {growth} bytes", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--work", type=Path, help="retain logs and private probe modules")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    if args.work:
        work = args.work.resolve()
        work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), repo, work)
    else:
        with tempfile.TemporaryDirectory(prefix="axiom-string-slots-") as directory:
            check(args.axiom.resolve(), repo, Path(directory))


if __name__ == "__main__":
    main()
