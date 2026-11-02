#!/usr/bin/env python3
"""Run actual Windows command-pool ownership and encoding with host WinAPI mocks.

The private library copy selects Windows native implementations and PATH
constants. Only file-existence probes and native API boundaries are mocked.
Native Windows execution, including OS cleanup after process exit, remains
the Windows CI fixtures' responsibility.
"""
import argparse
from platform_source import windows_platform_source
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def run(*args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def axiom_function(source, name, public=False):
    """Copy a complete real declaration, skipping quoted/comment parentheses."""
    visibility = "pub " if public else ""
    start = source.index(f"({visibility}:: {name} ")
    body = source.index(f"({visibility}fn ({name}", start)
    depth, quoted, escaped, comment = 0, False, False, False
    for end in range(body, len(source)):
        char = source[end]
        if comment:
            comment = char != "\n"
        elif quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
        elif char == ";":
            comment = True
        elif char == '"':
            quoted = True
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if not depth:
                return source[start:end + 1]
    raise AssertionError(f"unterminated Axiom function {name}")


PATH_CONSTANTS = """
(:: pathBackslashSeparates Int)
(fn (pathBackslashSeparates) 1)
(:: pathListSep Int)
(fn (pathListSep) 59)
(:: exeSuffixTried Int)
(fn (exeSuffixTried) 1)
"""
PROBES = """
(extern "windows_command_pool_test"
  (platformOpen :: (-> Int Int Int Int) (symbol "poolOpen"))
  (platformClose :: (-> Int Int) (symbol "poolClose")))
"""
BRIDGE = """(import Internal.WindowsCommands)
(import Internal.WindowsCommandsNative)
(import Internal.CommandScratch)
(import WindowsSpawnTest)
(import WindowsTask)
(import Sys)
(import Internal.ProcessRaw)
(import Vec)
(import Err)
(extern "windows_command_pool_test"
  (poolStat :: (-> Int Int) (symbol "poolStat")))
(pub :: nativeNew Int)
;@axiom:effect(io)
(pub fn (nativeNew) windowsCommandJobNew)
(pub :: nativeClose (-> Int Int))
;@axiom:effect(io)
(pub fn (nativeClose job) (windowsCommandJobClose job))
(pub :: nativeSpawn (-> Int Int Int Int Int Int))
;@axiom:effect(io)
(pub fn (nativeSpawn job path argv envp slot)
  (windowsCommandSpawn job path argv envp slot))
(pub :: nativeSpawnInherited (-> Int Int Int Int Int Int Int Int))
;@axiom:effect(io)
(pub fn (nativeSpawnInherited job path argv envp slot handles count)
  (windowsCommandSpawnInherited job path argv envp slot handles count))
(pub :: nativeWait (-> Int Int))
;@axiom:effect(io)
(pub fn (nativeWait pid) (windowsCommandWait pid))
(pub :: nativePoll (-> Int Int))
;@axiom:effect(io)
(pub fn (nativePoll pid) (windowsCommandPoll pid))
(pub :: nativeKill (-> Int Int Int))
;@axiom:effect(io)
(pub fn (nativeKill pid code) (windowsCommandKill pid code))
(pub :: nativeDispose (-> Int Int))
;@axiom:effect(io)
(pub fn (nativeDispose pid) (windowsCommandDispose pid))
(:: boom (-> Int Int))
(fn (boom n) (/ 1 n))
(pub :: scopeCommands (-> Int Int Bool Bool))
;@axiom:effect(io)
;@axiom:effect(spawn)
(pub fn (scopeCommands argv envp trap)
  (match (windowsCommandsNew 2)
    ((Err _) false)
    ((Ok pool)
      {
        (let a (windowsCommandsStart pool 0 "C:/ok" argv envp ""))
        (let b (windowsCommandsStart pool 1 "C:/ok" argv envp ""))
        (if trap (== (boom 0) 0) (&& (> a 0) (> b 0)))
      })))
(pub :: recoverCommands (-> Int Int Int))
;@axiom:effect(io)
;@axiom:effect(spawn)
(pub fn (recoverCommands argv envp)
  (__axiom_recover __axiom_arena_mark
    (lambda (unused)
      {
        (let words (vecNew))
        (vecPush words "C:/ok")
        (vecPush words "71")
        (vecPush words "payload")
        (vecPush words "")
        (vecPush words "space and\\ttab")
        (vecPush words "a\\\"b")
        (vecPush words "tail\\\\")
        (vecPush words "café")
        (let envScratch (commandScratchNew 1))
        (if (scopeCommands (WindowsTask::taskArgvVector words) (processRawEnvpInto envScratch 0) true) 0 1)
      })))
(pub :: closeCommands (-> Int Int Bool))
;@axiom:effect(io)
;@axiom:effect(spawn)
(pub fn (closeCommands argv envp)
  (match (windowsCommandsNew 2)
    ((Err _) false)
    ((Ok pool)
      {
        (let pid (windowsCommandsStart pool 0 "C:/ok" argv envp ""))
        (let once (windowsCommandsClose pool))
        (let twice (windowsCommandsClose pool))
        (&& (> pid 0) (&& (== once 0) (== twice 0)))
      })))
(pub :: failedCloseCommands (-> Int Int Int))
;@axiom:effect(io)
;@axiom:effect(spawn)
(pub fn (failedCloseCommands argv envp)
  (match (windowsCommandsNew 2)
    ((Err e) (- 0 (errCode e)))
    ((Ok pool)
      {
        (let a (windowsCommandsStart pool 0 "C:/ok" argv envp ""))
        (let b (windowsCommandsStart pool 1 "C:/ok" argv envp ""))
        (windowsCommandsClose pool)
      })))
"""

BRIDGE += """
(:: scratchLive Int)
(fn (scratchLive) (- (__axiom_mem_stat 0) (__axiom_mem_stat 1)))
(pub :: scratchStorage Int)
;@axiom:effect(io)
;@axiom:effect(unsafe)
(pub fn (scratchStorage)
  {
    (let scratch (commandScratchNew 2))
    (let before scratchLive)
    (let first (commandScratchBuffer scratch 0 64))
    (let other (commandScratchBuffer scratch 1 32))
    (__store64 first 0 123)
    (__store64 first 1 456)
    (__store64 other 0 789)
    (let reused (commandScratchBuffer scratch 0 16))
    (let zeroed (&& (== first reused) (&& (== (__load64 reused 0) 0) (== (__load64 reused 1) 0))))
    (let independent (== (__load64 other 0) 789))
    (let grown (commandScratchBuffer scratch 0 4096))
    (let growBytes (- scratchLive before))
    (let retired (&& (!= grown first) (&& (<= growBytes 4256) (== (__load64 other 0) 789))))
    (__store64 grown 511 123)
    (let cleared (commandScratchBuffer scratch 0 4096))
    (let allZero (&& (== cleared grown) (== (__load64 cleared 511) 0)))
    (let once (commandScratchClose scratch))
    (let after (- scratchLive before))
    (let twice (commandScratchClose scratch))
    (+ (if (&& zeroed allZero) 1 0)
      (+ (if independent 2 0)
        (+ (if retired 4 0) (if (&& (== once 0) (&& (== twice 0) (<= after 128))) 8 0))))
  })
(pub :: scratchRecovery Int)
;@axiom:effect(io)
(pub fn (scratchRecovery)
  (__axiom_recover __axiom_arena_mark
    (lambda (unused)
      {
        (let scratch (commandScratchNew 2))
        (let first (commandScratchBuffer scratch 0 4096))
        (let other (commandScratchBuffer scratch 1 8192))
        (if (&& (> first 0) (> other 0)) (boom 0) -1)
      })))
(pub :: scratchRefusal (-> Int Int))
;@axiom:effect(io)
(pub fn (scratchRefusal kind)
  (__axiom_recover __axiom_arena_mark
    (lambda (unused)
      {
        (let scratch (commandScratchNew (if (== kind 0) 0 1)))
        (commandScratchBuffer scratch (if (== kind 2) 1 0) (if (== kind 2) 8 (if (== kind 3) -1 0)))
      })))
(pub :: scratchOverflow (-> Bool Int))
;@axiom:effect(io)
;@axiom:effect(unsafe)
(pub fn (scratchOverflow length)
  (__axiom_recover __axiom_arena_mark
    (lambda (unused)
      {
        (let scratch (commandScratchNew 1))
        (let vector (__alloc 32))
        (if length
          {
            (let string (__alloc 24))
            (__store64 string 0 4611686018427387904)
            (let data (__alloc 8))
            (__store64 data 0 string)
            (__store64 vector 0 1)
            (__store64 vector 1 1)
            (__store64 vector 2 data)
          }
          (__store64 vector 0 576460752303423488))
        (commandScratchArgv scratch 0 (as vector (Vec String)))
      })))
"""


# Fixed inputs are retained before measurement; output payload is charged separately.
BRIDGE += r"""(:: scratchWords (Vec String))
(fn (scratchWords)
  {
    (let words (vecNew))
    (vecPush words "C:/ok")
    (vecPush words "71")
    (vecPush words "payload")
    (vecPush words "")
    (vecPush words "space and\ttab")
    (vecPush words "a\"b")
    (vecPush words "tail\\")
    (vecPush words "café")
    words
  })
(pub :: scratchDirect (-> Int Int))
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(pub fn (scratchDirect rounds)
  {
    (let words scratchWords)
    (let argv (WindowsTask::taskArgvVector words))
    (let envScratch (commandScratchNew 1))
    (let env (processRawEnvpInto envScratch 0))
    (let mut bad 0)
    (match (windowsCommandsNew 1)
      ((Err _) -1)
      ((Ok pool)
        {
          (for i in 0..16
            {
              (if (< (windowsCommandsStart pool 0 "C:/ok" argv env "") 0)
                (set bad (+ bad 1)))
              (if (!= (windowsCommandsJoin pool 0) 71)
                (set bad (+ bad 1)))
            })
          (let before scratchLive)
          (for i in 0..rounds
            {
              (if (< (windowsCommandsStart pool 0 "C:/ok" argv env "") 0)
                (set bad (+ bad 1)))
              (if (!= (windowsCommandsJoin pool 0) 71)
                (set bad (+ bad 1)))
            })
          (let grew (- scratchLive before))
          (let closed (windowsCommandsClose pool))
          (if (&& (== bad 0) (&& (== closed 0) (== (vecLen words) 8))) grew -1)
        }))
  })
(pub :: scratchPublic (-> Int Int))
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(pub fn (scratchPublic count)
  {
    (let words scratchWords)
    (let commands (vecWithCapacity count))
    (for i in 0..count (vecPush commands words))
    (let before scratchLive)
    (let results (WindowsTask::taskRunCommands commands 1))
    (let grew (- (- scratchLive before) (* count 8)))
    (if (&& (== (vecLen results) count)
          (&& (== (vecGet results 0) 71)
            (&& (== (vecGet results (- count 1)) 71) (== (vecLen words) 8))))
      grew -1)
  })
"""

BRIDGE += """
(pub :: ordinaryScratch (-> Int Int))
;@axiom:effect(io)
(pub fn (ordinaryScratch rounds)
  {
    (let words scratchWords)
    (let argv (WindowsTask::taskArgvVector words))
    (let envScratch (commandScratchNew 1))
    (let env (processRawEnvpInto envScratch 0))
    (let mut bad 0)
    (for i in 0..16
      {
        (let pid (WindowsSpawnTest::ordinarySpawn (strCStr "C:/ok.exe") argv env))
        (if (|| (< pid 0) (!= (windowsCommandWait pid) (* 71 256))) (set bad (+ bad 1)))
      })
    (let before scratchLive)
    (for i in 0..rounds
      {
        (let pid (WindowsSpawnTest::ordinarySpawn (strCStr "C:/ok.exe") argv env))
        (if (|| (< pid 0) (!= (windowsCommandWait pid) (* 71 256))) (set bad (+ bad 1)))
      })
    (let grew (- scratchLive before))
    (if (&& (== bad 0) (== (vecLen words) 8)) grew -1)
  })
"""

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", required=True)
    parser.add_argument("--keep", type=Path, help="save emitted IR, binaries and outputs here")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    axiom = str(Path(args.axiom).resolve())
    source = (root / "stdlib/Task.ax").read_text()
    assert source.count("(import Internal.CommandPool)") == 1, "Task lost its selected command-pool entry"
    pool = (root / "stdlib/Internal/WindowsCommands.windows.ax").read_text()
    anchor = "(import Internal.WindowsCommandsNative)"
    assert pool.count(anchor) == 1
    imports = list(re.finditer(r"^\(import[^\n]+\)$", pool, re.MULTILINE))
    after_imports = imports[-1].end()
    pool = pool[:after_imports] + "\n" + PROBES + pool[after_imports:]
    # The real trusted platform function becomes a raw test extern;
    # declare that boundary's Unsafe effect without changing its body.
    anchor = ";@axiom:effect(io)\n(fn (windowsCommandsExists path)"
    assert pool.count(anchor) == 1
    pool = pool.replace(anchor, ";@axiom:effect(io)\n;@axiom:effect(unsafe)\n(fn (windowsCommandsExists path)")
    path = (root / "stdlib/Internal/ProcessPath.ax").read_text()
    assert path.count("(import Sys.Platform)") == 1
    path = path.replace("(import Sys.Platform)", "(import Sys.Platform)\n" + PATH_CONSTANTS)
    process = (root / "stdlib/Internal/Process.ax").read_text()
    anchor = "(import Err)"
    assert process.count(anchor) == 1
    process = process.replace(anchor, anchor + "\n(:: usesSyscallAbi Int)\n(fn (usesSyscallAbi) 0)")
    platform = windows_platform_source(root)
    bindings = []
    for name in ("winGetLastError", "winCloseHandle", "winCreateProcessW"):
        matches = re.findall(rf"^  \({name} ::[^\n]+", platform, re.MULTILINE)
        assert len(matches) == 1, f"ordinary spawn binding changed: {name}"
        bindings.extend(matches)
    # Only the exported declaration name changes, avoiding a collision with
    # the host Sys.Platform import; the production function body stays exact.
    ordinary = axiom_function(platform, "platformSpawn", public=True)
    assert ordinary.count("platformSpawn") == 2, "ordinary spawn declaration changed"
    spawn = ('(import Internal.WindowsStartup)\n(extern "kernel32"\n'
             + "\n".join(bindings) + ")\n"
             + axiom_function(platform, "winErrnoOf") + "\n"
             + axiom_function(platform, "winLastErr") + "\n"
             + ordinary.replace("platformSpawn", "ordinarySpawn", 2))
    fixture = root / "tests/platform/windows-command-pools.ax"
    cases = 62
    assert len(re.findall(r"\(say\s", fixture.read_text())) - 1 == cases, "update the explicit assertion count"
    with tempfile.TemporaryDirectory(prefix="axiom-windows-command-pools-") as tmp:
        work = Path(tmp)
        lib = work / "stdlib"
        lib.mkdir()
        for child in (root / "stdlib").iterdir():
            if child.name == "Internal":
                internal = lib / "Internal"
                internal.mkdir()
                selected = {"CommandPool.ax", "WindowsCommands.ax", "WindowsCommandsNative.ax", "ProcessPath.ax", "Process.ax", "CommandScratch.ax", "WindowsStartup.ax"}
                for helper in child.iterdir():
                    if helper.name not in selected:
                        (internal / helper.name).symlink_to(helper, target_is_directory=helper.is_dir())
                (internal / "WindowsCommands.ax").write_text(pool)
                (internal / "CommandPool.ax").write_text((child / "CommandPool.windows.ax").read_text())
                native = (child / "WindowsCommandsNative.windows.ax").read_text()
                (internal / "WindowsCommandsNative.ax").write_text(native)
                (internal / "ProcessPath.ax").write_text(path)
                (internal / "Process.ax").write_text(process)
                startup = child / "WindowsStartup.windows.ax"
                if startup.exists():
                    (internal / "WindowsStartup.ax").write_text(startup.read_text())
                scratch = (child / "CommandScratch.ax").read_text()
                scratch = scratch.replace("(import Vec)", "(import Vec)\n"
                    '(extern "windows_command_pool_test"\n'
                    '  (poolScratchDrop :: (-> Int Int) (symbol "poolScratchDrop")))')
                # Observe the real callback before reset reclaims its records.
                # No ownership operation is replaced by this instrumentation.
                scratch = scratch.replace(";@axiom:effect(unsafe)\n(fn (commandScratchDrop",
                    ";@axiom:effect(unsafe)\n;@axiom:effect(io)\n(fn (commandScratchDrop")
                drop = "(__release address)"
                assert scratch.count(drop) == 1
                scratch = scratch.replace(drop, drop + "\n        (poolScratchDrop address)")
                (internal / "CommandScratch.ax").write_text(scratch)
            else:
                (lib / child.name).symlink_to(child, target_is_directory=child.is_dir())
        module = lib / "WindowsTask.ax"
        module.write_text(source)
        (lib / "WindowsCommandTest.ax").write_text(BRIDGE)
        (lib / "WindowsSpawnTest.ax").write_text(spawn)
        env = dict(os.environ, AXIOM_STDLIB=str(lib))
        run("cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-c",
            str(root / "tests/platform/windows-command-pools.c"), "-o", str(work / "mock.o"))

        def check(level, expected_failures=(), required_failures=(), tag=""):
            ir = work / "probe.ll"
            run(sys.executable, str(root / "scripts/lib/internal-probe.py"), axiom, "--diagnostic-format=ai", "emit-llvm", str(fixture), "-o", str(ir),
                env=env, stdout=subprocess.DEVNULL)
            if level:
                optimised = work / f"probe-O{level}.ll"
                run("opt", f"-O{level}", str(ir), "-S", "-o", str(optimised))
                ir = optimised
            obj = work / f"probe-O{level}.o"
            binary = work / f"probe-O{level}"
            run("llc", f"-O{level}", "-filetype=obj", "-relocation-model=pic", str(ir), "-o", str(obj))
            entry = ["-e", "_main"] if os.uname().sysname == "Darwin" else []
            run("cc", *entry, str(obj), str(work / "mock.o"), "-o", str(binary))
            test_env = dict(env, PATH=';C:/bad;;"C:/Program Files/Pool";C:/last;',
                            AXIOM_POOL_VALUE="forwarded")
            result = subprocess.run([str(binary)], env=test_env, capture_output=True, text=True, timeout=20)
            lines = result.stdout.splitlines()
            failures = {i + 1 for i, line in enumerate(lines) if line.startswith("FAIL ")}
            if args.keep:
                import shutil
                args.keep.mkdir(parents=True, exist_ok=True)
                name = f"probe-{tag + '-' if tag else ''}O{level}"
                shutil.copy2(ir, args.keep / f"{name}.ll")
                shutil.copy2(binary, args.keep / name)
                (args.keep / f"{name}.stdout").write_text(result.stdout)
                (args.keep / f"{name}.stderr").write_text(result.stderr)
            semantic_result = (failures == set(expected_failures) if expected_failures is not None
                               else bool(failures) and set(required_failures) <= failures)
            if (len(lines) != cases or not semantic_result
                    or result.returncode != len(failures)
                    or any(not line.startswith(("ok  ", "FAIL ")) for line in lines)):
                raise SystemExit(f"FAIL Windows command pools -O{level}: exit {result.returncode}, "
                                 f"failures {sorted(failures)}, expected {expected_failures}, "
                                 f"required {required_failures}\n"
                                 f"{result.stdout}{result.stderr}")
            return failures

        for level in (0, 2):
            check(level)
            print(f"ok   Windows command-pool ownership and WinAPI mocks: {cases} cases at -O{level} on the host")

        # A semantic assertion must fail after each precise ownership
        # ablation. Build or link failures do not count as evidence.
        publication = "(__store64 slot 0 pid)"
        assert native.count(publication) == 1, "publication ablation lost its target"
        (internal / "WindowsCommandsNative.ax").write_text(native.replace(publication, "(__store64 slot 0 0)"))
        check(2, None, (31,), "unpublished")
        print("ok   negative probe: omitting handle publication fails the before-resume ownership assertion")
        (internal / "WindowsCommandsNative.ax").write_text(native)
        job_close = "(windowsCommandJobClose handle)"
        assert pool.count(job_close) == 1, "job cleanup ablation lost its target"
        (internal / "WindowsCommands.ax").write_text(pool.replace(job_close, "0"))
        check(2, None, (33,), "unclosed-job")
        print("ok   negative probe: omitting job close fails recovery cleanup")
        close_status = "(pub fn (windowsCommandsClose pool)\n  (__resource_close pool.owner))"
        assert pool.count(close_status) == 1, "cleanup status ablation lost its target"
        (internal / "WindowsCommands.ax").write_text(pool.replace(close_status,
            "(pub fn (windowsCommandsClose pool)\n  { (let ignored (__resource_close pool.owner)) 0 })"))
        check(2, None, (46, 47, 48), "ignored-cleanup-error")
        print("ok   negative probe: ignoring cleanup status fails all three cleanup-error cases")
        (internal / "WindowsCommands.ax").write_text(pool)
        (internal / "CommandScratch.ax").write_text(scratch.replace(drop, "0"))
        check(2, None, (52,), "unclosed-scratch")
        print("ok   negative probe: omitting scratch retirement fails bounded explicit close")
        (internal / "CommandScratch.ax").write_text(scratch)
        wait_cell = "(__release cell)"
        assert native.count(wait_cell) == 1, "wait scratch ablation lost its target"
        (internal / "WindowsCommandsNative.ax").write_text(native.replace(wait_cell, "0"))
        check(2, None, (58, 59), "unreleased-wait-cell")
        print("ok   negative probe: omitting wait-cell retirement fails both bounded-scratch soaks")


if __name__ == "__main__":
    main()
