#!/usr/bin/env python3
"""Execute the Windows multiplexer with deterministic host API mocks.

This checks library routing, timeouts, flags and buffer sharing. The
runtime reader and native Windows delivery have their own probes.
"""
import argparse
from platform_source import windows_platform_source
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def run(*args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    axiom = str(Path(args.axiom).resolve())
    platform = windows_platform_source(root)
    with tempfile.TemporaryDirectory(prefix="axiom-windows-readiness-") as tmp:
        work = Path(tmp)
        lib = work / "stdlib"
        lib.mkdir()
        for child in (root / "stdlib").iterdir():
            (lib / child.name).symlink_to(child, target_is_directory=child.is_dir())
        # The actual platform's Internal imports require a stdlib module.
        module = lib / "WindowsPlatform.ax"
        module.write_text(platform)
        shutil.copyfile(root / "tests/platform/windows-readiness.ax", work / "probe.ax")
        env = dict(os.environ, AXIOM_STDLIB=str(lib), AXIOM_PATH=str(work))
        run("cc", "-c", str(root / "tests/platform/windows-readiness.c"), "-o", str(work / "mock.o"))

        def check(level, expected_failures=()):
            ir = work / "probe.ll"
            run(axiom, "--diagnostic-format=ai", "emit-llvm", str(work / "probe.ax"),
                "-o", str(ir), env=env, stdout=subprocess.DEVNULL)
            if level:
                optimised = work / "probe.opt.ll"
                run("opt", f"-O{level}", str(ir), "-S", "-o", str(optimised))
                ir = optimised
            obj, binary = work / "probe.o", work / "probe"
            run("llc", f"-O{level}", "-filetype=obj", "-relocation-model=pic", str(ir), "-o", str(obj))
            entry = ["-e", "_main"] if os.uname().sysname == "Darwin" else []
            run("cc", *entry, str(obj), str(work / "mock.o"), "-o", str(binary))
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            lines = result.stdout.splitlines()
            failures = {i+1 for i, line in enumerate(lines) if line.startswith("FAIL ")}
            expected = set(expected_failures)
            if (len(lines) != 46 or result.returncode != len(failures)
                    or failures != expected
                    or any(not line.startswith(("ok   ", "FAIL ")) for line in lines)):
                raise SystemExit(f"FAIL Windows readiness mocks -O{level}: exit {result.returncode}\n"
                                 f"{result.stdout}{result.stderr}")

        for level in (0, 2):
            check(level)
            print(f"ok   Windows readiness API mocks: 46 cases at -O{level} on the host")
        original = "(let r (winReaderReady h))"
        assert platform.count(original) == 1, "readiness ablation lost its target"
        # Return no completion while preserving the actual helper call,
        # its effects and all unrelated wrappers. The indefinite case
        # gets a finite deadline so the verdict can demonstrate failure.
        module.write_text(platform.replace(original, "(let r (* 0 (winReaderReady h)))"))
        probe = work / "probe.ax"
        text = probe.read_text()
        indefinite = "WindowsPlatform::platformPoll p 1 -1"
        assert text.count(indefinite) == 2, "indefinite handle ablation lost its target"
        text = text.replace(indefinite, "WindowsPlatform::platformPoll p 1 35", 1)
        probe.write_text(text)
        check(2, (3, 5, 6, 14, 21, 22, 23, 24))
        print("ok   negative probe: discarding reader completion fails readiness assertions")

        # Positional I/O must not bypass the shared reader on a stream.
        # Keep invalid-handle failures while making consoles and pipes
        # take the disk path; all four stream refusals must go red.
        original = "(if (!= kind 1)"
        assert platform.count(original) == 2, "positional guard ablation lost its targets"
        module.write_text(platform.replace(original, "(if (== kind 0)"))
        shutil.copyfile(root / "tests/platform/windows-readiness.ax", probe)
        check(2, (36, 37, 38, 39))
        print("ok   negative probe: bypassing positional guards fails four stream cases")


if __name__ == "__main__":
    main()
