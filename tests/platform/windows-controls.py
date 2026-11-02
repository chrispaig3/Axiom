#!/usr/bin/env python3
"""Run the Windows mask wrapper and IO control rows with host mocks.

The native callback/atomics and Windows console delivery are separate
checks. This probe exercises the actual library registration/decoding.
"""
import argparse
import os
from pathlib import Path
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
    source = (root / "stdlib/IO.ax").read_text()
    # Select the real table branch and Windows event layout. Only the
    # polling boundary is replaced; the mask calls its real wrapper.
    overlay = """
(import WindowsPlatform)
(:: usesSyscallAbi Int)
(fn (usesSyscallAbi) 0)
(:: pollUsesKqueue Int)
(fn (pollUsesKqueue) 0)
(:: pollEventSize Int)
(fn (pollEventSize) 24)
(:: pollEventFdOffset Int)
(fn (pollEventFdOffset) 8)
(:: pollReadFilter Int)
(fn (pollReadFilter) 1)
(:: pollAddOp Int)
(fn (pollAddOp) 1)
(:: pollDelOp Int)
(fn (pollDelOp) 2)
(:: platformSignalBlock (-> Int (Result Int Error)))
;@axiom:effect(io)
(fn (platformSignalBlock mask)
  (WindowsPlatform::controlMaskBlock mask))
(extern "windows_controls_test"
  (platformPoll :: (-> Int Int Int Int) (symbol "pollControls")))
"""
    source = source.replace("(import Fmt)", "(import Fmt)\n" + overlay, 1)
    with tempfile.TemporaryDirectory(prefix="axiom-windows-controls-") as tmp:
        work = Path(tmp)
        lib = work / "stdlib"
        lib.mkdir()
        for child in (root / "stdlib").iterdir():
            (lib / child.name).symlink_to(child, target_is_directory=child.is_dir())
        (lib / "WindowsIO.ax").write_text(source)
        # Export only the function under test, so the host's Sys module
        # still resolves its own platform constants without ambiguity.
        platform = (root / "stdlib/Sys/Platform.windows.ax").read_text()
        platform = platform.replace("(pub ", "(")
        platform = platform.replace("(:: platformSignalBlock", "(pub :: platformSignalBlock")
        platform = platform.replace("(fn (platformSignalBlock", "(pub fn (platformSignalBlock")
        platform = platform.replace("platformSignalBlock", "controlMaskBlock")
        (lib / "WindowsPlatform.ax").write_text(platform)
        env = dict(os.environ, AXIOM_STDLIB=str(lib))
        run("cc", "-c", str(root / "tests/platform/windows-controls-mock.c"),
            "-o", str(work / "mock.o"))
        probe = root / "tests/platform/windows-controls-mock.ax"

        def check(level, expected_failures=()):
            ir = work / "probe.ll"
            run(axiom, "--diagnostic-format=ai", "emit-llvm", str(probe),
                "-o", str(ir), env=env, stdout=subprocess.DEVNULL)
            if level:
                optimised = work / "probe.opt.ll"
                run("opt", f"-O{level}", str(ir), "-S", "-o", str(optimised))
                ir = optimised
            obj, binary = work / "probe.o", work / "probe"
            run("llc", f"-O{level}", "-filetype=obj", "-relocation-model=pic",
                str(ir), "-o", str(obj))
            entry = ["-e", "_main"] if os.uname().sysname == "Darwin" else []
            run("cc", *entry, str(obj), str(work / "mock.o"), "-o", str(binary))
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            lines = result.stdout.splitlines()
            failures = {i+1 for i, line in enumerate(lines) if line.startswith("FAIL ")}
            if (len(lines) != 30 or failures != set(expected_failures)
                    or result.returncode != len(expected_failures)
                    or any(not line.startswith(("ok   ", "FAIL ")) for line in lines)):
                raise SystemExit(f"FAIL Windows control IO mocks -O{level}: exit {result.returncode}\n"
                                 f"{result.stdout}{result.stderr}")

        for level in (0, 2):
            check(level)
            print(f"ok   Windows control mask and IO mocks: 30 cases at -O{level} on the host")

        # Forgetting the table's control row must reach failed semantic
        # assertions; a compile failure cannot prove the probe effective.
        original = "(pollerTable p -2 mask token pollAddOp None)"
        assert source.count(original) == 1, "control row ablation lost its target"
        (lib / "WindowsIO.ax").write_text(source.replace(original, "0"))
        check(2, (9, 10, 11, 14, 16, 20, 26, 27))
        print("ok   negative probe: omitting control rows fails eight delivery cases")


if __name__ == "__main__":
    main()
