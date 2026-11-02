#!/usr/bin/env python3
"""Exercise the actual emitter line-buffer ownership with focused ablations.

Only the copied codegen module changes in negative probes. Each probe is an
ordinary executable fixture, not a rebuilt compiler or bootstrap ladder.
Compiler overlays retain their core/ directory; executable fixtures stay
outside it and declare their own unsafe ownership observations.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile


BRIDGES = r'''
(pub :: probeCount (-> a Int))
;@axiom:effect(unsafe)
(pub fn (probeCount value)
  (__load64 (as value Int) -2))
(pub :: probeSetCGVector (-> CG (Vec String) Int CG))
(pub fn (probeSetCGVector cg value slot)
  (if (== slot 0)
    (cgReplaceLines cg value)
    (if (== slot 1)
      (cgSetMangleBares cg value)
      (if (== slot 2)
        (cgSetMangleFulls cg value)
        (cgSetTcoSlots cg value)))))
(pub :: probeCGTailShare (-> CG Bool))
(pub fn (probeCGTailShare cg)
  {
    (let value nodesNew)
    (let before (probeCount value))
    (cgSetTailRetain cg value)
    (== (probeCount value) (+ before 1))
  })
; Private-copy-only probes; production does not export raw CG setters.
(pub :: probeSetHoisted (-> CG (Vec String) CG))
(pub fn (probeSetHoisted cg value) (cgSetHoisted cg value))
(pub :: probeHoisted (-> CG (Vec String)))
(pub fn (probeHoisted cg) (cgHoisted cg))
(pub :: probeHoistedPayloadCount (-> CG Int Int))
;@axiom:effect(unsafe)
(pub fn (probeHoistedPayloadCount cg index)
  { (let line (vecGet (cgHoisted cg) index)) (__load64 (as line Int) -2) })
(pub :: probeSameHoistedGetter (-> CG String Bool))
;@axiom:effect(unsafe)
(pub fn (probeSameHoistedGetter cg expected)
  {
    (let value (cgHoisted cg))
    (let before (__load64 (as value Int) -2))
    (cgSetHoisted cg value)
    (&& (== (__load64 (as value Int) -2) before) (strEq (vecGet value 0) expected))
  })

; Mirror Vec's mapped header and raw data ownership, but return its word
; without a counted return cast. The real setter creates its sole share.
; This is only an ordering proof, never an ordinary Vec birth-share fix.
(:: probeRawVec Int)
;@axiom:effect(unsafe)
(fn (probeRawVec)
  {
    (let header (memAllocMapped 32 4))
    (let data (memAlloc 8))
    (__retain data)
    (memSetWord header 0 0)
    (memSetWord header 1 1)
    (memSetWord header 2 data)
    (memSetWord header 3 0)
    header
  })
(pub :: probeSoleHoistedSame Bool)
;@axiom:effect(unsafe)
(pub fn (probeSoleHoistedSame)
  {
    (let cg newCG)
    (let header (probeRawVec))
    (cgSetHoisted cg (as header (Vec String)))
    (let sole (== (__load64 header -2) 1))
    (let filed (__axiom_mem_stat 1))
    (cgSetHoisted cg (as header (Vec String)))
    (if (!= (__axiom_mem_stat 1) filed)
      false
      (&& sole (== (__load64 header -2) 1)))
  })
'''

def run_checked(command, *, env, stdout, stderr, timeout=180):
    with stdout.open("w") as out, stderr.open("w") as err:
        result = subprocess.run(command, env=env, stdout=out, stderr=err, timeout=timeout)
    if result.returncode:
        raise RuntimeError(
            f"command exited {result.returncode}: {' '.join(map(str, command))}\n"
            f"{stderr.read_text()[-6000:]}"
        )


def replace_once(source, before, after, description):
    if source.count(before) != 1:
        raise RuntimeError(f"{description}: expected one source anchor")
    return source.replace(before, after, 1)


def check_output(path, expected, *, required_failures=()):
    lines = path.read_text().splitlines()
    if len(lines) != len(expected):
        raise RuntimeError(f"{path}: expected {len(expected)} cases, got {lines!r}")
    failures = set()
    for index, (actual, wanted) in enumerate(zip(lines, expected), 1):
        if actual == f"{index} false":
            failures.add(index)
        elif actual != wanted:
            raise RuntimeError(f"{path}: malformed case {index}: {actual!r}")
    if required_failures:
        if not set(required_failures) <= failures:
            raise RuntimeError(f"{path}: expected failures {required_failures}, got {failures}")
    elif failures:
        raise RuntimeError(f"{path}: failed cases {sorted(failures)}")
    return failures


def emitted_function(module, name):
    match = re.search(r'^define [^\n]*@' + re.escape(name)
                      + r'\([^\n]*\) [^\n]*\{\n.*?^\}', module, re.M | re.S)
    if match is None:
        raise RuntimeError(f"missing actual emitted function {name}")
    return match.group()


def check_typed_slot(body, slot, value=None):
    """Check the actual field load, replacement share, store and retirement."""
    pointers = []
    for root in re.findall(r'(%\S+) = inttoptr i64 %cg to ptr', body):
        pointers.extend(re.findall(r'(%\S+) = getelementptr i64, ptr '
                                  + re.escape(root) + r', i64 ' + str(slot) + r'\n', body))
    loads = []
    stores = []
    for pointer in pointers:
        loads.extend(re.findall(r'(%\S+) = load i64, ptr ' + re.escape(pointer) + r'\n', body))
        stores.extend(re.finditer(r'store i64 (%\S+), ptr ' + re.escape(pointer) + r'\n', body))
    if len(loads) != 1 or len(stores) != 1:
        raise RuntimeError(f'typed slot {slot}: expected one displaced load and one store')
    old, store = loads[0], stores[0]
    if value is not None and store[1] != value:
        raise RuntimeError(f'typed slot {slot}: stored {store[1]}, expected {value}')
    retain = f'call void @axiom_retain(i64 {store[1]})'
    retire = f'call void @axiom_release(i64 {old})'
    if body.count(retain) != 1 or body.count(retire) != 1:
        raise RuntimeError(f'typed slot {slot}: replacement and displaced shares must each balance once')
    if not body.index(retain) < store.start() < body.index(retire):
        raise RuntimeError(f'typed slot {slot}: retain, publish and retire are out of order')


def raw_setter(source, name, field, slot, value='value', *, release_first=False):
    """Restore an unbalanced raw store only in a private negative module."""
    begin = source.index(f'(fn ({name} ')
    end = source.index('\n  })', begin) + len('\n  })')
    body = source[begin:end]
    stores = list(re.finditer(r'^    \(set c\.' + re.escape(field) + r' (.*)\)\n', body, re.M))
    if len(stores) != 1 or not re.search(r'\b' + re.escape(value) + r'\b', stores[0][1]):
        raise RuntimeError(name + ': expected one typed field store of ' + value)
    after = f'    (memSetWord (as cg Int) {slot} {value})\n'
    if release_first:
        after = f'    (let old (memGetWord (as cg Int) {slot}))\n    (__release old)\n' + after
    body = replace_once(body, stores[0][0], after, name + ' typed store ablation')
    boundary = ';@axiom:effect(unsafe)\n' if release_first else ''
    return source[:begin] + boundary + body + source[end:]


def check_hoisted_routes(binary):
    module = Path(str(binary) + ".ll").read_text()
    setter = emitted_function(module, "codegen$cgSetHoisted")
    check_typed_slot(setter, 44, '%value')
    check_typed_slot(emitted_function(module, 'codegen$cgReplaceLines'), 0, '%lines')
    for name, slot, value in [('cgSetMangleBares', 12, 'bares'), ('cgSetMangleFulls', 13, 'fulls'),
                              ('cgSetTcoSlots', 28, 'slots'), ('cgSetTailRetain', 41, 'leaves')]:
        check_typed_slot(emitted_function(module, 'codegen$' + name), slot, '%' + value)
    for name in ("openAllocaMark", "closeAllocaMark"):
        body = emitted_function(module, "codegen$" + name)
        if body.count("@codegen$cgSetHoisted(") != 1:
            raise RuntimeError(f"{name}: expected one typed hoisted-vector replacement")
        if re.search(r'@raw\$memSetWord\(i64 [^,]+, i64 44,', body):
            raise RuntimeError(f"{name}: unbalanced direct hoisted-slot writer remains")
    for name in ("emitAlloca", "emitRecoverCell", "emitRegionCell", "closeAllocaMark"):
        body = emitted_function(module, "codegen$" + name)
        getter = re.findall(r'(%\S+) = call i64 @codegen\$cgHoisted\(i64 %cg\)', body)
        if len(getter) != 1:
            raise RuntimeError(f"{name}: expected one hoisted-vector getter")
        release = f"call void @axiom_release(i64 {getter[0]})"
        if body.count(release) != 1:
            raise RuntimeError(f"{name}: temporary hoisted getter share must retire once")
        if name != "closeAllocaMark":
            pushes = re.findall(r'@Vec\$vecPush\(i64 [^,]+, i64 [^,]+, i64 ([01])\)', body)
            if pushes != ["1"]:
                raise RuntimeError(f"{name}: String payload appends must retain their elements")
            value = re.search(r'@Vec\$vecPush\(i64 [^,]+, i64 (%\S+), i64 1\)', body)[1]
            cleanup = f"call void @axiom_release(i64 {value})"
            if body.count(cleanup) != 1 or body.index(cleanup) < body.index("@Vec$vecPush("):
                raise RuntimeError(f"{name}: ordinary queued String birth must retire after its store")
    for name in ("emitRecoverCell", "emitRegionCell"):
        body = emitted_function(module, "codegen$" + name)
        direct = re.search(r'(%\S+) = (?P<tail>musttail )?call i64 '
                           r'@codegen\$emitLine\(i64 %cg, i64 (?P<line>%\S+)\)', body)
        if direct is None or direct["tail"] is not None:
            raise RuntimeError(f"{name}: fresh line requires a normal emitLine call before cleanup")
        cleanup = f'call void @axiom_release(i64 {direct["line"]})'
        if body.count(cleanup) != 1 or body.index(cleanup) <= direct.end():
            raise RuntimeError(f"{name}: direct line birth must retire after emitLine returns")
        if body.index(cleanup) >= body.rindex("ret i64 "):
            raise RuntimeError(f"{name}: direct line cleanup must precede return")
    # The String a typed getter reads is either borrowed, when nothing in
    # its scope can write (no share taken, none given back), or held by
    # one temporary share given back once. Either is balanced; a share
    # taken and never returned, or returned twice, is not.
    for name in ("joinAllocas", "joinAllocasSize"):
        body = emitted_function(module, "codegen$" + name)
        reads = re.findall(r'(%\S+) = call i64 @Vec\$vecGet\(i64 [^,]+, i64 [^,]+, i64 1\)', body)
        if len(reads) != 1:
            raise RuntimeError(f"{name}: expected one typed String getter")
        taken = body.count(f"call void @axiom_retain(i64 {reads[0]})")
        given = body.count(f"call void @axiom_release(i64 {reads[0]})")
        if taken != given or given > 1:
            raise RuntimeError(f"{name}: typed String getter takes {taken} share(s) and gives back {given}")


def check(axiom, repo, work):
    source = repo / "tests/selfhost/emitter-line-buffer.axp"
    fixture = work / source.with_suffix(".ax").name
    fixture.write_bytes(source.read_bytes())
    expected = source.with_suffix(".out").read_text().splitlines()
    if expected != [f"{i} true" for i in range(1, 63)]:
        raise RuntimeError("update the explicit 62-case assertion count")
    env = dict(os.environ, AXIOM_PATH=str(repo / "core"), AXIOM_STDLIB=str(repo / "stdlib"))

    run_checked([str(axiom), "--diagnostic-format=ai", "fmt", "--check", str(fixture)],
                env=env, stdout=work / "fixture.fmt.stdout", stderr=work / "fixture.fmt.stderr")

    def prepare_module(label, source):
        module_root = work / f"{label}-modules/core"
        module_root.mkdir(parents=True, exist_ok=True)
        for path in (repo / "core").iterdir():
            destination = module_root / path.name
            if path.name == "codegen.ax":
                destination.write_text(source + BRIDGES)
            elif not destination.exists():
                destination.symlink_to(path, target_is_directory=path.is_dir())
        return module_root

    def build_run(label, level, module_root, negative=()):
        binary = work / label
        local_env = dict(env, AXIOM_PATH=str(module_root))
        run_checked(
            [str(axiom), "build", str(fixture), "--opt", str(level), "--alloc-poison",
             "--emit-llvm", "--diagnostic-format=ai", "-o", str(binary)],
            env=local_env, stdout=work / f"{label}.build.stdout", stderr=work / f"{label}.build.stderr",
        )
        output = work / f"{label}.stdout"
        run_checked([str(binary)], env=local_env, stdout=output, stderr=work / f"{label}.stderr", timeout=30)
        failures = check_output(output, expected, required_failures=negative)
        if not negative:
            check_hoisted_routes(binary)
        diagnostic = (work / f"{label}.stderr").read_text()
        growth = re.fullmatch(r"hoisted-soak-growth (-?\d+)\nhoisted-payload-soak-growth (-?\d+)\ndirect-payload-soak-growth (-?\d+)\n", diagnostic)
        if growth is None:
            raise RuntimeError(f"{label}: missing hoisted Vec ownership diagnostic: {diagnostic!r}")
        print(f"note fresh-Vec/hoisted/direct payload growth in {label}: {tuple(map(int, growth.groups()))} bytes", flush=True)
        return failures

    original = (repo / "core/codegen.ax").read_text()
    for level in (0, 2):
        label = f"positive-O{level}"
        build_run(label, level, prepare_module(label, original))
        print(f"ok   emitter line-buffer ownership: 62 cases at -O{level} with allocation poisoning", flush=True)

    variants = []
    duplicate = original
    for name, arg in [('cgReplaceLines', 'lines'), ('cgSetMangleBares', 'bares'),
                      ('cgSetMangleFulls', 'fulls'), ('cgSetTcoSlots', 'slots'),
                      ('cgSetTailRetain', 'leaves')]:
        start = duplicate.index('(fn (' + name + ' ')
        anchor = duplicate.index('    (let c ', start)
        duplicate = duplicate[:anchor] + '    (__retainref ' + arg + ')\n' + duplicate[anchor:]
    variants.append(('duplicate-vector-shares', duplicate, (58, 59, 60, 61, 62)))
    variants.append(("header-share", replace_once(
        original,
        '    (vecPush (cgLines cg) (strDup line))\n    cg',
        '    (let updated (vecPush (cgLines cg) (strDup line)))\n'
        '    (memSetWord (as cg Int) 0 updated)\n    cg',
        "same-header share ablation"), (2, 4)))
    variants.append(("mutable-snapshot", replace_once(
        original,
        '(vecPush (cgLines cg) (strDup line))',
        '(vecPush (cgLines cg) line)',
        "snapshot ablation"), (1, 5)))
    alloca = replace_once(
        original,
        '(vecSet (cgLines cg) mark (joinAllocas hoisted))',
        '(vecSet (memGetWordVec (as cg Int) 0) mark (as (joinAllocas hoisted) Int))',
        "alloca element metadata ablation")
    alloca = replace_once(alloca, '(as 0 (Vec String)))\n          (cgSetAllocaMark cg',
                          '(as 0 (Vec Int)))\n          (cgSetAllocaMark cg', "alloca branch type")
    variants.append(("alloca-metadata", alloca, (11,)))
    displaced = raw_setter(original, 'cgReplaceLines', 'lines', 0, 'lines')
    variants.append(("displaced-slot", displaced, (14, 15)))

    name = "cgSetHoisted"
    begin = original.index(f"(fn ({name} cg value)\n")
    end = original.index("\n  })", begin) + len("\n  })")
    body = original[begin:end]
    no_retire = raw_setter(original, name, 'hoisted', 44)
    variants.append(("hoisted-no-retirement", no_retire, (24, 27, 28, 29, 30, 31, 37, 40, 42, 43)))
    variants.append(("hoisted-release-first", raw_setter(
        original, name, 'hoisted', 44, release_first=True), (43,)))

    # Keep the header's retain/publish/retire ledger intact while making
    # element storage plain. This deliberately recreates the old payload
    # leak direction; it never manually spends an ordinary String share.
    plain_payload = replace_once(body, "    (set c.hoisted value)\n", """    (set c.hoisted value)
    (let h (as value Int))
    (if (> h 0)
      {
        (let data (memGetWord h 2))
        (if (> data 0)
          { (memMarkLeaf data) (memSetWord h 3 2) })
      })
""", "hoisted payload metadata ablation")
    variants.append(("hoisted-plain-payload", replace_once(
        original, body, plain_payload, "hoisted payload map"), (42, 44, 51, 53)))

    for label, source, negative in variants:
        module_root = prepare_module(label, source)
        failures = build_run(label, 0, module_root, negative)
        if label == "hoisted-plain-payload":
            header_cases = set(range(18, 42)) | {43}
            if failures & header_cases:
                raise RuntimeError(f"payload-only control damaged header ledger: {sorted(failures & header_cases)}")
        print(f"ok   negative probe {label}: cases {','.join(map(str, sorted(failures)))} fail", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--work", type=Path, help="retain logs and private ablation modules in this directory")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    axiom = args.axiom.resolve()
    if args.work:
        work = args.work.resolve()
        work.mkdir(parents=True, exist_ok=True)
        check(axiom, repo, work)
    else:
        with tempfile.TemporaryDirectory(prefix="axiom-emitter-lines-") as directory:
            check(axiom, repo, Path(directory))


if __name__ == "__main__":
    main()
