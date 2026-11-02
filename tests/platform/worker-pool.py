#!/usr/bin/env python3
"""Exercise encoded workers, their byte protocol and both Windows ABIs."""
import argparse
from collections import defaultdict
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
STDLIB = ROOT / "stdlib"
FIXTURES = ("encoded-worker-endpoint", "encoded-worker-pool", "encoded-worker-cancel")
TARGETS = {"windows-x86_64": ("i386:x86-64", "x64", "IMAGE_FILE_MACHINE_AMD64"),
           "windows-aarch64": ("arm64", "arm64", "IMAGE_FILE_MACHINE_ARM64")}


def run(command, **kwargs):
    return subprocess.run([str(x) for x in command], check=True, **kwargs)


def env():
    result = os.environ.copy()
    result["AXIOM_STDLIB"] = str(STDLIB)
    return result


def execute(command, timeout=30, runtime_env=None):
    process = subprocess.Popen([str(value) for value in command], env=runtime_env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        start_new_session=os.name == "posix")
    try:
        stdout, stderr = process.communicate(timeout=timeout)
        return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
    finally:
        if os.name == "posix":
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        elif process.poll() is None:
            process.kill()
        process.wait(timeout=5)


def emit(axiom, target, directory):
    directory.mkdir(parents=True, exist_ok=True)
    for fixture in FIXTURES:
        flags = ["--threads"] if fixture.endswith("cancel") else []
        run([axiom, "--diagnostic-format=ai", "--target=" + target, "emit-llvm", *flags,
             ROOT / "tests/platform" / (fixture + ".ax"), "-o", directory / (fixture + ".ll")], env=env())


def windows_allow(path):
    result = defaultdict(set)
    for line in path.read_text().splitlines():
        entry = line.split("#", 1)[0].strip()
        if not entry:
            continue
        name, separator, dll = entry.partition("@")
        result[dll if separator else "kernel32"].add(name)
    return result


def link_windows(directory, target, level):
    dllmachine, machine, expected = TARGETS[target]
    output = directory / ("O" + str(level))
    output.mkdir(exist_ok=True)
    allowed = windows_allow(directory.parent / "platform-allow.windows.txt")
    libraries = []
    for dll, symbols in allowed.items():
        definition = output / (dll + ".def")
        definition.write_text("LIBRARY " + dll + ".dll\nEXPORTS\n" + "\n".join(sorted(symbols)) + "\n")
        library = output / (dll + ".lib")
        run(["llvm-dlltool", "-m", dllmachine, "-d", definition, "-l", library])
        libraries.append(library)
    for fixture in FIXTURES:
        ir = output / (fixture + ".ll")
        obj = output / (fixture + ".obj")
        binary = output / (fixture + ".exe")
        run(["opt", "-O" + str(level), "-S", directory / (fixture + ".ll"), "-o", ir])
        run(["llc", "-O" + str(level), "-filetype=obj", "-relocation-model=pic", ir, "-o", obj])
        run(["lld-link", "-subsystem:console", "-entry:mainCRTStartup", "-stack:8388608",
             "-machine:" + machine, "-out:" + str(binary), obj, *libraries])
        headers = run(["llvm-readobj", "--file-headers", binary], capture_output=True, text=True).stdout
        assert "Machine: " + expected in headers, headers
        imports = run(["llvm-readobj", "--coff-imports", binary], capture_output=True, text=True).stdout
        (output / (fixture + ".imports")).write_text(imports)
        for block in imports.split("Import {")[1:]:
            dll = re.search(r"Name: ([^\n]+)", block)[1].lower().removesuffix(".dll")
            names = re.findall(r"Symbol: (\S+)", block)
            assert dll in allowed and set(names) <= allowed[dll], (dll, names)
    return output


def assert_pool(binary, endpoint, directory, runtime_env=None):
    result = execute([binary, endpoint], runtime_env=runtime_env)
    (directory / "pool.stdout").write_text(result.stdout)
    (directory / "pool.stderr").write_text(result.stderr)
    assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
    assert result.stdout.count("ok   ") == 28 and "FAIL" not in result.stdout, result.stdout
    assert "worker stdout\n" in result.stdout, result.stdout


def assert_cancel(binary, endpoint, directory, runtime_env=None):
    result = execute([binary, endpoint], timeout=15, runtime_env=runtime_env)
    (directory / "cancel.stdout").write_text(result.stdout)
    (directory / "cancel.stderr").write_text(result.stderr)
    assert result.returncode == 0 and result.stdout.startswith("ok   token propagates"), (result.returncode, result.stdout, result.stderr)


def native(axiom, work):
    transport_directory = work / "tmp"
    transport_directory.mkdir(exist_ok=True)
    runtime_env = os.environ.copy()
    runtime_env["TMPDIR"] = str(transport_directory)
    before = set(transport_directory.iterdir())
    for level in (0, 2):
        directory = work / ("host-O" + str(level))
        directory.mkdir(parents=True, exist_ok=True)
        for fixture in FIXTURES:
            flags = ["--threads"] if fixture.endswith("cancel") else []
            run([axiom, "--diagnostic-format=ai", "build", "--opt", str(level), *flags,
                 ROOT / "tests/platform" / (fixture + ".ax"), "-o", directory / fixture], env=env())
        endpoint = directory / FIXTURES[0]
        parent = directory / FIXTURES[1]
        assert_pool(parent, endpoint, directory, runtime_env)
        assert_cancel(directory / FIXTURES[2], endpoint, directory, runtime_env)
        assert subprocess.run([str(endpoint)], timeout=5, env=runtime_env).returncode == 64
        assert subprocess.run([str(endpoint), "--axiom-worker-v1", "bad", "95"], timeout=5, env=runtime_env).returncode == 22
        times = []
        for width in (1, 3):
            start = time.monotonic()
            run([parent, endpoint, "load", str(width)], timeout=15, env=runtime_env)
            times.append(time.monotonic() - start)
        assert times[1] < times[0] * .85, ("worker concurrency is not observable", times)
        print(f"ok   encoded workers O{level}: 28 API cases, cooperative token, invalid endpoint, real process concurrency ({times[0]:.3f}s / {times[1]:.3f}s)")
        snapshots = []
        for rounds in (20, 200):
            sample = run([parent, endpoint, "soak", str(rounds)], capture_output=True, text=True, timeout=30, env=runtime_env)
            match = re.fullmatch(r"held (\d+) filed (\d+) mapped (\d+)\n", sample.stdout)
            assert match, sample.stdout
            snapshots.append([int(value) for value in match.groups()])
        (directory / "soak.txt").write_text(f"20 rounds: {snapshots[0]}\n200 rounds: {snapshots[1]}\n")
        growth = (snapshots[1][0] - snapshots[1][1]) - (snapshots[0][0] - snapshots[0][1])
        print(f"observed parent allocator backlog O{level}: +{growth} bytes from 20 to 200 calls; not a WorkerOpts memory bound")

    after = set(transport_directory.iterdir())
    assert not after - before, ("transport names leaked", after - before)
    run(["python3", ROOT / "tests/platform/worker-protocol.py", "--axiom", axiom])


def controlled_lifetimes(axiom, work):
    original_backend = (STDLIB / "Internal/WorkerProcess.ax").read_text()
    original_worker = (STDLIB / "Task/Worker.ax").read_text()
    for scenario in ("launch-grace", "join-fault", "close-fault", "bounds-fault"):
        directory = work / scenario
        directory.mkdir(exist_ok=True)
        library = directory / "stdlib"
        shutil.copytree(STDLIB, library, dirs_exist_ok=True)
        backend = original_backend
        if scenario == "launch-grace":
            backend = backend.replace("(pub :: workerProcessesStart", "(:: workerProcessesStartReal").replace("(pub fn (workerProcessesStart", "(fn (workerProcessesStartReal")
            backend += """
(pub :: workerProcessesStart (-> WorkerProcesses Int String Int Int String WorkerMapping Int))
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(pub fn (workerProcessesStart pool index name argv envp path mapping)
  (if (== index 1) { (let _ (sysSleepNanos 200000000)) -13 }
    (workerProcessesStartReal pool index name argv envp path mapping)))
"""
            worker = original_worker.replace("(fn (workerStart ", ";@axiom:effect(block)\n(fn (workerStart ")
        elif scenario == "join-fault":
            backend = backend.replace("(pub :: workerProcessesJoin", "(:: workerProcessesJoinReal").replace("(pub fn (workerProcessesJoin", "(fn (workerProcessesJoinReal")
            backend += """
(pub :: workerProcessesJoin (-> WorkerProcesses Int Int))
;@axiom:effect(io)
;@axiom:effect(block)
(pub fn (workerProcessesJoin pool index)
  (if (== index 0) { (let _ (workerProcessesClose pool)) -5 }
    (workerProcessesJoinReal pool index)))
"""
            worker = original_worker
        elif scenario == "close-fault":
            backend = backend.replace("(pub :: workerProcessesClose", "(:: workerProcessesCloseReal").replace("(pub fn (workerProcessesClose", "(fn (workerProcessesCloseReal")
            backend += """
(pub :: workerProcessesClose (-> WorkerProcesses Int))
;@axiom:effect(io)
(pub fn (workerProcessesClose pool)
  { (let closed (workerProcessesCloseReal pool)) (if (< closed 0) closed -13) })
"""
            worker = original_worker
        else:
            worker = original_worker
        (library / "Internal/WorkerProcess.ax").write_text(backend)
        for level in (0, 2):
            for ablated in (False, True):
                variant = worker
                if ablated and scenario == "launch-grace":
                    anchor = "(let now sysTimeoutMicros)"
                    assert variant.count(anchor) == 1
                    variant = variant.replace(anchor, "")
                    anchor = "(while (< head count)\n      {"
                    assert variant.count(anchor) == 1
                    variant = variant.replace(anchor, anchor + "\n        (let now sysTimeoutMicros)")
                if ablated and scenario == "join-fault":
                    pattern = r"\n\s+\(if \(< slot\.status 0\)\n\s+\{\n\s+\(let failure \(- 0 slot\.status\)\)\n\s+\(let _ \(workerProcessesClose processes\)\)\n\s+\(workerPoisonSlots slots head next failure\)\n\s+\(set cancelling true\)\n\s+\}\)"
                    variant, count = re.subn(pattern, "", variant)
                    assert count == 2, count
                if ablated and scenario == "close-fault":
                    anchor = "(if (&& (< closed 0) (> (vecLen out) 0))"
                    start = variant.index(anchor)
                    depth = 0
                    for end in range(start, len(variant)):
                        depth += (variant[end] == "(") - (variant[end] == ")")
                        if depth == 0:
                            variant = variant[:start] + variant[end + 1:]
                            break
                if ablated and scenario == "bounds-fault":
                    start = variant.index("(:: workerSlotValid")
                    end = variant.index("(:: workerSlotSuccess", start)
                    old = variant[start:end]
                    anchor = "(&& (workerProtocolValidate address total)\n          (&& (== (__load64 address 2) opts.inputLimit) (== (__load64 address 4) opts.resultLimit)))"
                    assert old.count(anchor) == 1
                    changed = old.replace(anchor, "(workerProtocolValidate address total)")
                    changed = changed.replace(";@axiom:effect(unsafe)\n", "")
                    variant = variant[:start] + changed + variant[end:]
                (library / "Task/Worker.ax").write_text(variant)
                binary = directory / f"O{level}-{'ablated' if ablated else 'intact'}"
                run([axiom, "--diagnostic-format=ai", "build", "--opt", level,
                    ROOT / "tests/platform/encoded-worker-pool.ax", "-o", binary],
                    env=dict(os.environ, AXIOM_STDLIB=str(library)))
                endpoint = work / ("host-O" + str(level)) / FIXTURES[0]
                result = execute([binary, endpoint, scenario])
                (directory / (binary.name + ".stdout")).write_text(result.stdout)
                (directory / (binary.name + ".stderr")).write_text(result.stderr)
                if ablated:
                    assert result.returncode != 0, (scenario, result.stdout)
                else:
                    assert result.returncode == 0 and result.stdout.startswith("ok   "), (scenario, result.returncode, result.stdout, result.stderr)
            print(f"ok   {scenario} O{level}: actual process fault control and runnable negative ablation")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom")
    parser.add_argument("--keep", type=Path)
    parser.add_argument("--stdlib", type=Path, help="validation-only dependency overlay")
    windows = parser.add_mutually_exclusive_group()
    windows.add_argument("--emit-windows", type=Path)
    windows.add_argument("--run-windows", type=Path)
    windows.add_argument("--link-windows", type=Path, help="link both Windows architectures without executing PE files")
    parser.add_argument("--target", choices=TARGETS)
    parser.add_argument("--skip-windows", action="store_true")
    args = parser.parse_args()
    global STDLIB
    STDLIB = (args.stdlib or ROOT / "stdlib").resolve()
    if args.run_windows or args.link_windows:
        if args.run_windows and not args.target:
            parser.error("--run-windows needs the native runner --target")
        artifacts = args.run_windows or args.link_windows
        for target in TARGETS:
            for level in (0, 2):
                output = link_windows(artifacts / target, target, level)
                if args.run_windows and target == args.target:
                    assert_pool(output / (FIXTURES[1] + ".exe"), output / (FIXTURES[0] + ".exe"), output)
                    assert_cancel(output / (FIXTURES[2] + ".exe"), output / (FIXTURES[0] + ".exe"), output)
                    print(f"ok   encoded workers {target} O{level}: EXECUTED 28 cases and token cancellation")
                else:
                    print(f"ok   encoded workers {target} O{level}: PE links, NOT EXECUTED")
        return
    assert args.axiom, "--axiom is required for emission or host execution"
    axiom = str(Path(args.axiom).resolve())
    if args.emit_windows:
        for target in TARGETS:
            emit(axiom, target, args.emit_windows / target)
        shutil.copy2(ROOT / "scripts/platform-allow.windows.txt", args.emit_windows / "platform-allow.windows.txt")
        return
    with tempfile.TemporaryDirectory(prefix="axiom-encoded-workers-") as tmp:
        work = args.keep.resolve() if args.keep else Path(tmp)
        work.mkdir(parents=True, exist_ok=True)
        native(axiom, work)
        controlled_lifetimes(axiom, work)
        if not args.skip_windows:
            shutil.copy2(ROOT / "scripts/platform-allow.windows.txt", work / "platform-allow.windows.txt")
            for target in TARGETS:
                emit(axiom, target, work / target)
                for level in (0, 2):
                    link_windows(work / target, target, level)
                    print(f"ok   encoded workers {target} O{level}: PE links and permitted imports, NOT EXECUTED")


if __name__ == "__main__":
    main()
