#!/usr/bin/env python3
"""Exercise encoded-worker backend ownership with actual POSIX children.

The temporary library harness can reach the private backend. It checks
process and transport cleanup independently of the synchronous public
pool. Windows job-object cleanup needs native Windows execution.
"""
import argparse
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time


HARNESS = r'''
(import Internal.WorkerProcess)
(import Internal.Raw)
(import Sys)
(import Sys.Platform)
(import Str)
(import Vec)
(import Err)
(import IO)
(import Fmt)

(:: lifecycleArgv (-> String Int))
;@axiom:effect(unsafe)
(fn (lifecycleArgv executable)
  { (let words (rawAlloc 24))
    (__store64 words 0 (strCStr executable))
    (__store64 words 1 (__addr "60"))
    words })

(:: lifecycleBody (-> String String Int))
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
;@axiom:effect(unsafe)
(fn (lifecycleBody mode executable)
  (match (workerMappingNew 4096)
    ((Err error) { (println (concat "mapping-error " (fmtInt (errCode error)))) 10 })
    ((Ok mapping)
      {
        (println (concat "mapping " (workerMappingDescriptor mapping)))
        (match (workerProcessesNew 1)
          ((Err error) { (println (concat "process-error " (fmtInt (errCode error)))) 11 })
          ((Ok pool)
            {
              (let name (if (strEq mode "startfail")
                (concat (sysEnv "TMPDIR") "/does-not-exist")
                (if (strEq mode "execfail") (concat executable "/does-not-exist") executable)))
              (let pid (workerProcessesStart pool 0 name (lifecycleArgv name) sysEnvp "" mapping))
              (println "pid {pid}")
              (if (strEq mode "startfail")
                {
                  (let once (workerProcessesClose pool))
                  (let twice (workerProcessesClose pool))
                  (let mOnce (workerMappingClose mapping))
                  (let mTwice (workerMappingClose mapping))
                  (if (&& (< pid 0) (&& (== once 0) (&& (== twice 0)
                    (&& (== mOnce 0) (== mTwice 0))))) 0 12)
                }
                (if (<= pid 0) 13
                  (if (|| (strEq mode "recover") (strEq mode "fatal"))
                    (/ 1 (- pid pid))
                    (if (strEq mode "rawexit")
                      { (__syscall1 sysExitNum 73) 0 }
                      (if (strEq mode "external")
                        { (while true { (let _ (sysSleepNanos 10000000)) () }) 0 }
                        (if (strEq mode "abandon") 0
                    {
                      (let killed (if (strEq mode "execfail") 0 (workerProcessesKill pool 0 137)))
                      (let joined (workerProcessesJoin pool 0))
                      (let once (workerProcessesClose pool))
                      (let twice (workerProcessesClose pool))
                      (let mOnce (workerMappingClose mapping))
                      (let mTwice (workerMappingClose mapping))
                      (println "joined {joined}")
                      (if (&& (== killed 0) (&& (== joined (if (strEq mode "execfail") 20 137))
                        (&& (== once 0) (&& (== twice 0)
                        (&& (== mOnce 0) (== mTwice 0)))))) 0 14)
                    }))))))
            }))
      })))

(pub :: workerLifecycleMain Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(pub fn (workerLifecycleMain)
  {
    (let mode (sysArg 1))
    (let executable (sysArg 2))
    (if (strEq mode "recover")
      {
        (let status (__axiom_recover __axiom_arena_mark
          (lambda (unused) (lifecycleBody mode executable))))
        (println "recovered {status}")
        (if (== status 72) 0 15)
      }
      (lifecycleBody mode executable))
  })
'''


WINDOWS_HARNESS = r'''
(import Internal.WorkerProcess)
(import Err)
(extern "worker_lifecycle_test"
  (mappingReset :: (-> Int Int) (symbol "mappingReset"))
  (mappingStat :: (-> Int Int) (symbol "mappingStat"))
  (mappingAdopt :: Int (symbol "mappingAdopt"))
  (mappingSay :: (-> Bool String Int) (symbol "mappingSay")))

(:: mappingError (-> (Result WorkerMapping Error) Int Bool))
(fn (mappingError result code)
  (match result ((Ok _) false) ((Err error) (== (errCode error) code))))

(:: mappingTrap (-> Int Int))
;@axiom:effect(io)
(fn (mappingTrap zero)
  (match (workerMappingNew 4096)
    ((Err _) 1)
    ((Ok mapping) (+ (/ 1 zero) (workerMappingAddress mapping)))))

(:: mappingCloseFailure (-> Int Int Int))
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (mappingCloseFailure mode expected)
  {
    (mappingReset mode)
    (match (workerMappingNew 4096)
      ((Err _) 2)
      ((Ok mapping)
        {
          (let first (workerMappingClose mapping))
          (let again (workerMappingClose mapping))
          (+ (mappingSay (&& (== first expected) (== again 0))
               "Windows cleanup reports its first errno once")
            (mappingSay (&& (== (mappingStat 2) 1) (== (mappingStat 3) 1))
               "Windows cleanup attempts both view and handle"))
        }))
  })

(pub :: workerMappingLifecycleMain Int)
;@axiom:effect(io)
;@axiom:effect(unsafe)
(pub fn (workerMappingLifecycleMain)
  {
    (let mut bad 0)
    (mappingReset 0)
    (match (workerMappingNew 4096)
      ((Err _) (set bad (+ bad 1)))
      ((Ok mapping)
        {
          (set bad (+ bad (mappingSay
            (&& (> (workerMappingAddress mapping) 0)
              (&& (== (workerMappingHandle mapping) 100)
                (&& (== (mappingStat 7) 1) (== (mappingStat 6) 0))))
            "Windows mapping publishes ownership before enabling inheritance")))
          (set bad (+ bad (mappingSay (== (workerMappingClose mapping) 0) "Windows mapping closes")))
          (set bad (+ bad (mappingSay (== (workerMappingClose mapping) 0) "Windows repeated close is inert")))
        }))
    (set bad (+ bad (mappingSay (&& (== (mappingStat 2) 1) (&& (== (mappingStat 3) 1) (== (mappingStat 5) 0)))
      "Windows view and handle each retire exactly once")))
    (mappingReset 1)
    (set bad (+ bad (mappingSay (mappingError (workerMappingNew 4096) 12) "Windows creation failure is an error")))
    (set bad (+ bad (mappingSay (&& (== (mappingStat 1) 0) (== (mappingStat 3) 0)) "Windows failed creation owns no view or handle")))
    (mappingReset 7)
    (set bad (+ bad (mappingSay (mappingError (workerMappingNew 4096) 13)
      "Windows inheritance setup failure preserves its errno")))
    (set bad (+ bad (mappingSay (&& (== (mappingStat 7) 1)
      (&& (== (mappingStat 1) 0) (&& (== (mappingStat 3) 1) (== (mappingStat 5) 0))))
      "Windows inheritance setup failure closes its published handle")))
    (mappingReset 2)
    (set bad (+ bad (mappingSay (mappingError (workerMappingNew 4096) 12) "Windows view failure is an error")))
    (set bad (+ bad (mappingSay (&& (== (mappingStat 3) 1) (== (mappingStat 5) 0)) "Windows view failure closes the new handle")))
    (mappingReset 0)
    (set bad (+ bad (mappingSay (mappingError (workerMappingNew 95) 22) "Windows short mapping is refused")))
    (set bad (+ bad (mappingSay (&& (mappingError (workerMappingOpen "not-a-handle" 4096) 22)
      (&& (mappingError (workerMappingOpen "0" 4096) 22) (mappingError (workerMappingOpen "-1" 4096) 22)))
      "Windows malformed inherited descriptors are refused")))
    (set bad (+ bad (mappingSay (== (mappingStat 0) 0) "Windows invalid parameters allocate no kernel object")))
    (let _ mappingAdopt)
    (match (workerMappingOpen "100" 4096)
      ((Err _) (set bad (+ bad 1)))
      ((Ok mapping) { (let _ (workerMappingClose mapping)) () }))
    (set bad (+ bad (mappingSay (&& (== (mappingStat 2) 1) (&& (== (mappingStat 3) 1)
      (&& (== (mappingStat 5) 0) (== (mappingStat 6) 1))))
      "Windows inherited mapping clears inheritance and retires")))
    (mappingReset 3)
    (let _ mappingAdopt)
    (set bad (+ bad (mappingSay (mappingError (workerMappingOpen "100" 4096) 9)
      "Windows inherited-flag failure is an error")))
    (set bad (+ bad (mappingSay (&& (== (mappingStat 3) 1) (&& (== (mappingStat 5) 0) (== (mappingStat 1) 0)))
      "Windows inherited-flag failure closes the adopted handle")))
    (set bad (+ bad (mappingCloseFailure 4 -13)))
    (set bad (+ bad (mappingCloseFailure 5 -9)))
    (set bad (+ bad (mappingCloseFailure 6 -13)))
    (mappingReset 0)
    (let recovered (__axiom_recover __axiom_arena_mark (lambda (unused) (mappingTrap 0))))
    (set bad (+ bad (mappingSay (== recovered 72) "Windows mapping recovery preserves trap status")))
    (set bad (+ bad (mappingSay (&& (== (mappingStat 2) 1) (&& (== (mappingStat 3) 1) (&& (== (mappingStat 4) 0) (== (mappingStat 5) 0))))
      "Windows recovery retires its view and handle")))
    bad
  })
'''


WINDOWS_MOCK = r'''
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static unsigned char storage[4096];
static int64_t count[8], fault, last_error;
static int view, inherited;
int64_t mappingReset(int64_t mode) {
    memset(count, 0, sizeof count); fault = mode; view = 0; inherited = 0; last_error = 0; return 0;
}
int64_t mappingStat(int64_t index) { return count[index]; }
int64_t mappingAdopt(void) { count[5] = 1; inherited = 1; return 100; }
int64_t mappingSay(int64_t good, int64_t address) {
    const int64_t *header = (const int64_t *)(intptr_t)address;
    printf("%s%.*s\n", good ? "ok   " : "FAIL ", (int)header[0], (const char *)(intptr_t)header[1]);
    fflush(stdout); return good ? 0 : 1;
}
int64_t CreateFileMappingW(int64_t file, int64_t security, int64_t protect,
                          int64_t high, int64_t low, int64_t name) {
    ++count[0];
    if (file != -1 || security || protect != 4 || high || low != 4096 || name) ++count[4];
    if (fault == 1) return 0;
    count[5] = 1; return 100;
}
int64_t SetHandleInformation(int64_t handle, int64_t mask, int64_t flags) {
    if (flags == 0) ++count[6]; else if (flags == 1) ++count[7]; else ++count[4];
    if (handle != 100 || !count[5] || mask != 1 || flags == inherited) ++count[4];
    if (fault == 3 && flags == 0) { last_error = 6; return INT64_C(0x7fff000000000000); }
    if (fault == 7 && flags == 1) { last_error = 5; return INT64_C(0x7fff000000000000); }
    inherited = (int)flags;
    return INT64_C(0x7fff000000000001);
}
int64_t MapViewOfFile(int64_t handle, int64_t access, int64_t high, int64_t low, int64_t bytes) {
    ++count[1];
    if (handle != 100 || !count[5] || access != 6 || high || low || bytes != 4096) ++count[4];
    if (fault == 2) return 0;
    view = 1; return (int64_t)(intptr_t)storage;
}
int64_t UnmapViewOfFile(int64_t address) {
    if (address != (int64_t)(intptr_t)storage || !view) ++count[4];
    ++count[2];
    if (fault == 4 || fault == 6) { last_error = 5; return INT64_C(0x7fff000000000000); }
    view = 0; return INT64_C(0x7fff000000000001);
}
int64_t CloseHandle(int64_t handle) {
    if (handle != 100 || !count[5]) ++count[4];
    ++count[3];
    if (fault == 5 || fault == 6) { last_error = 6; return INT64_C(0x7fff000000000000); }
    count[5] = 0; return INT64_C(0x7fff000000000001);
}
int64_t GetLastError(void) { return INT64_C(0x7fff000000000000) | last_error; }
'''


def windows_mapping_checks(axiom, root, work, base_library):
    library = work / "windows-stdlib"
    shutil.copytree(base_library, library)
    for module in ("WorkerProcess", "WindowsCommands", "WindowsCommandsNative"):
        (library / "Internal" / f"{module}.ax").write_text(
            (root / "stdlib/Internal" / f"{module}.windows.ax").read_text())
    # Select Windows library capabilities while retaining the host's
    # emitted runtime and C ABI for the mocked kernel boundary.
    windows_platform = (root / "stdlib/Sys/Platform.windows.ax").read_text()
    for selected in (library / "Sys").glob("Platform.*.ax"):
        selected.write_text(windows_platform)
    windows_implementation = (root / "stdlib/Internal/Platform.windows.ax").read_text()
    for selected in (library / "Internal").glob("Platform.*.ax"):
        selected.write_text(windows_implementation)
    (library / "WorkerMappingLifecycleHarness.ax").write_text(WINDOWS_HARNESS)
    source = work / "windows-mapping.ax"
    source.write_text("(import WorkerMappingLifecycleHarness)\n(:: main Int)\n"
                      ";@axiom:effect(io)\n(fn (main) workerMappingLifecycleMain)\n")
    mock = work / "windows-mapping.c"
    mock.write_text(WINDOWS_MOCK)
    subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-c", str(mock),
                    "-o", str(work / "windows-mapping-mock.o")], check=True)
    env = dict(os.environ, AXIOM_STDLIB=str(library))
    protocol = library / "Internal/WorkerProcess.ax"
    original = protocol.read_text()
    close = "(wpCloseHandle handle)"
    assert original.count(close) == 1, "mapping close ablation lost its native call"
    for level, ablated in ((0, False), (2, False), (2, True)):
        if ablated:
            protocol.write_text(original.replace(close, "1"))
        tag = f"O{level}" + ("-ablated" if ablated else "")
        ir = work / f"windows-mapping-{tag}.ll"
        emitted = subprocess.run([axiom, "--diagnostic-format=ai", "emit-llvm", str(source),
                                  "-o", str(ir)], env=env, capture_output=True, text=True)
        if emitted.returncode:
            raise AssertionError(emitted.stdout + emitted.stderr)
        if level:
            subprocess.run(["opt", f"-O{level}", str(ir), "-S", "-o", str(ir)], check=True)
        obj = work / f"windows-mapping-{tag}.o"
        subprocess.run(["llc", f"-O{level}", "-filetype=obj", "-relocation-model=pic", str(ir),
                        "-o", str(obj)], check=True)
        binary = work / f"windows-mapping-{tag}"
        entry = ["-e", "_main"] if os.uname().sysname == "Darwin" else []
        subprocess.run(["cc", *entry, str(obj), str(work / "windows-mapping-mock.o"),
                        "-o", str(binary)], check=True)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
        lines = result.stdout.splitlines()
        failures = [line for line in lines if line.startswith("FAIL ")]
        expected = 10 if ablated else 0
        if (result.returncode != expected or len(lines) != 24 or len(failures) != expected
                or any(not line.startswith(("ok   ", "FAIL ")) for line in lines)):
            raise AssertionError(f"Windows mapping mocks {tag}: exit {result.returncode}\n"
                                 f"{result.stdout}{result.stderr}")
        if ablated:
            print("ok   omitting the native handle close fails ten Windows ownership cases")
        else:
            print(f"ok   Windows mapping ownership: 24 host-mocked cases at -O{level}")


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def case(binary, mode, directory):
    transport = directory / mode
    transport.mkdir()
    env = dict(os.environ, TMPDIR=str(transport))
    pid = None
    process = None
    try:
        # Regular files avoid waiting for EOF on pipes inherited by a
        # child whose broken owner outlived the parent. A new process
        # group gives the harness an independent cleanup boundary.
        with (directory / f"{mode}.stdout").open("w+") as output, (directory / f"{mode}.stderr").open("w+") as error:
            process = subprocess.Popen([str(binary), mode, "/bin/sleep"], env=env,
                                       stdout=output, stderr=error, start_new_session=True)
            if mode == "external":
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    output.seek(0)
                    if "pid " in output.read():
                        os.kill(process.pid, signal.SIGKILL)
                        break
                    time.sleep(0.01)
                else:
                    raise AssertionError("external kill probe never observed a child")
            status = process.wait(timeout=10)
            output.seek(0)
            stdout = output.read()
            error.seek(0)
            stderr = error.read()
        lines = stdout.splitlines()
        pids = [int(line[4:]) for line in lines if line.startswith("pid ")]
        if len(pids) != 1:
            raise AssertionError(f"{mode}: no unique launch observation: {stdout}{stderr}")
        pid = pids[0]
        expected = 72 if mode == "fatal" else 73 if mode == "rawexit" else -9 if mode == "external" else 0
        if status != expected:
            raise AssertionError(f"{mode}: expected exit {expected}, got {status}\n"
                                 f"{stdout}{stderr}")
        if mode == "startfail" and pid >= 0:
            raise AssertionError(f"{mode}: missing executable started as pid {pid}")
        if mode != "startfail" and pid <= 0:
            raise AssertionError(f"{mode}: child did not start: {pid}")
        # Cleanup is synchronous: explicit close and recovery must wait
        # for retirement before the parent can return. Allow init to reap
        # the fatal parent's child only on hosts that do that asynchronously.
        deadline = time.monotonic() + 1
        while pid > 0 and alive(pid) and time.monotonic() < deadline:
            time.sleep(0.01)
        if mode in ("rawexit", "external"):
            if not alive(pid):
                raise AssertionError(f"{mode}: no surviving child observed for the termination-limit probe")
            if list(transport.rglob("*")):
                raise AssertionError(f"{mode}: anonymous transport left a filesystem name")
            print(f"limit {mode}: POSIX child survives bypassed cleanup; test process group retired separately")
            return
        failures = []
        if pid > 0 and alive(pid):
            failures.append(f"child {pid} is still alive")
        remaining = list(transport.rglob("*"))
        if remaining:
            failures.append("transport names remain: " + ", ".join(str(path.relative_to(transport)) for path in remaining))
        if failures:
            raise AssertionError(f"{mode}: " + "; ".join(failures))
        print(f"ok   {mode}: child retired and transport names removed")
    finally:
        # A broken cleanup implementation must not leak a test child.
        if process is not None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", required=True)
    parser.add_argument("--stdlib", type=Path, help="validation-only dependency overlay")
    parser.add_argument("--observe-raw-exit", action="store_true",
                        help="record the POSIX raw-exit/SIGKILL limit, outside the passing cleanup contract")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    axiom = str(Path(args.axiom).resolve())
    if os.name != "posix":
        raise SystemExit("worker-lifecycle.py runs POSIX child probes; native Windows job cleanup is checked separately")
    with tempfile.TemporaryDirectory(prefix="axiom-worker-lifecycle-") as temporary:
        work = Path(temporary)
        library = work / "stdlib"
        shutil.copytree(args.stdlib or root / "stdlib", library)
        for name in ("WorkerProcess.ax", "WorkerProcess.windows.ax"):
            shutil.copyfile(root / "stdlib/Internal" / name, library / "Internal" / name)
        (library / "WorkerLifecycleHarness.ax").write_text(HARNESS)
        source = work / "main.ax"
        source.write_text("(import WorkerLifecycleHarness)\n(:: main Int)\n"
                          ";@axiom:effect(io)\n;@axiom:effect(spawn)\n;@axiom:effect(block)\n"
                          "(fn (main) workerLifecycleMain)\n")
        env = dict(os.environ, AXIOM_STDLIB=str(library))
        windows_mapping_checks(axiom, root, work, library)
        for level in (0, 2):
            binary = work / f"probe-O{level}"
            built = subprocess.run([axiom, "--diagnostic-format=ai", "build", "--input", str(source),
                                    "--output", str(binary), "--opt", str(level)],
                                   env=env, text=True, capture_output=True)
            if built.returncode:
                raise SystemExit(built.stdout + built.stderr)
            cases = work / f"cases-O{level}"
            cases.mkdir()
            for mode in ("normal", "startfail", "execfail", "recover", "fatal", "abandon"):
                case(binary, mode, cases)
            if args.observe_raw_exit:
                for mode in ("rawexit", "external"):
                    case(binary, mode, cases)


if __name__ == "__main__":
    main()
