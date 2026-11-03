#!/usr/bin/env python3
"""Run one shard of the CI battery: gates in parallel, serial gates after.

The old workflow ran each shard's gates as consecutive steps, so a
four-core runner executed one gate at a time and a shard's wall time
was the sum of its gates (77 to 194 minutes). `run-gates.sh` already
knew better locally: a parallel pool, with the gates whose verdict
depends on wall time kept serial. This is that shape for CI, with the
two things a workflow step list gave for free kept explicit:

  - every gate still runs through `ci-gate.py`, so a gate whose inputs
    are unchanged since it last passed is reused, not rerun;
  - every gate gets its own log, duration and row in the step summary,
    and the artifact carries the machine-readable results.

  ci-run.py --gates gates.txt [--jobs N] [--timeout SEC]
            [--results results.jsonl] [--logs DIR]

Exit status is 0 only when every gate passed (or was reused). A gate
that exceeds its timeout is killed with its whole process group and
reported as `timeout`, which fails the run like any other failure.
"""
import argparse
import concurrent.futures
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import importlib.util

_spec = importlib.util.spec_from_file_location("ci_plan", ROOT / "scripts" / "ci-plan.py")
ci_plan = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ci_plan)


def run_gate(gate: str, timeout: int, logs: Path) -> dict:
    log = logs / f"{gate}.log"
    started = time.monotonic()
    with open(log, "wb") as out:
        proc = subprocess.Popen(
            [sys.executable, "scripts/ci-gate.py", f"./scripts/{gate}"],
            cwd=ROOT, stdout=out, stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            rc = proc.wait(timeout=timeout)
            status = "passed" if rc == 0 else "failed"
        except subprocess.TimeoutExpired:
            # TERM first, so a gate can still print what it was doing;
            # KILL the whole group if it will not stop.
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
            rc, status = None, "timeout"
    seconds = round(time.monotonic() - started, 1)
    if status == "passed" and log.is_file() and "unchanged inputs; passed in run" in log.read_text(errors="replace"):
        status = "reused"
    print(f"{status:8} {gate} ({seconds}s)", flush=True)
    return {"gate": gate, "status": status, "rc": rc, "seconds": seconds, "log": str(log)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gates", required=True, help="file with one gate script name per line")
    ap.add_argument("--jobs", type=int, default=0, help="parallel gates (default: cores - 1, 2..6)")
    ap.add_argument("--timeout", type=int, default=1800, help="per-gate timeout in seconds")
    ap.add_argument("--results", default="", help="write results JSONL here")
    ap.add_argument("--logs", default="", help="directory for per-gate logs")
    a = ap.parse_args()

    gates = list(dict.fromkeys(
        ln.strip() for ln in Path(a.gates).read_text().splitlines() if ln.strip()))
    if not gates:
        print("ci-run: gate list is empty; refusing to pass vacuously", file=sys.stderr)
        return 2
    missing = [g for g in gates if not (ROOT / "scripts" / g).is_file()]
    if missing:
        print(f"ci-run: planned gates not in the tree: {', '.join(missing)}", file=sys.stderr)
        return 2

    logs = Path(a.logs) if a.logs else ROOT / ".axiom-ci" / "logs"
    logs = logs if logs.is_absolute() else ROOT / logs
    logs.mkdir(parents=True, exist_ok=True)

    serial = ci_plan.serial_gates()
    weights = ci_plan.weights()
    unknown = max(weights.values(), default=float(ci_plan.DEFAULT_WEIGHT))
    parallel = sorted((g for g in gates if g not in serial),
                      key=lambda g: (-weights.get(g, unknown), g))
    serial_first = [g for g in gates if g in serial]

    jobs = a.jobs or min(6, max(2, (os.cpu_count() or 4) - 1))
    results: list[dict] = []
    print(f"ci-run: {len(parallel)} gates, {jobs} at a time; then {len(serial_first)} serial", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = [pool.submit(run_gate, g, a.timeout, logs) for g in parallel]
        for f in concurrent.futures.as_completed(futures):
            results.append(f.result())
    for g in serial_first:
        results.append(run_gate(g, a.timeout, logs))

    results.sort(key=lambda r: r["gate"])
    bad = [r for r in results if r["status"] not in ("passed", "reused")]

    if a.results:
        out = Path(a.results)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text("".join(json.dumps(r) + "\n" for r in results))

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as fh:
            fh.write(f"\n| gate | result | seconds |\n|---|---|---|\n")
            for r in results:
                fh.write(f"| `{r['gate']}` | {r['status']} | {r['seconds']} |\n")

    for r in bad:
        print(f"\n--- {r['gate']}: {r['status']} (last log lines) ---", flush=True)
        tail = Path(r["log"]).read_text(errors="replace").splitlines()[-40:]
        print("\n".join(tail), flush=True)

    reused = sum(1 for r in results if r["status"] == "reused")
    print(f"\nci-run: {len(results) - len(bad)}/{len(results)} passed "
          f"({reused} reused unchanged), {len(bad)} failed", flush=True)
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
