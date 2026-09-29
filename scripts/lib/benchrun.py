#!/usr/bin/env python3
"""Interleaved whole-process timing for `scripts/bench-concurrency.sh`.

    benchrun.py --reps N SPEC

SPEC names one command per line, tab-separated: a label, a regular
expression every run's stdout must match in full, and the command
(split with shlex). The harness runs the commands ROUND-ROBIN, one
repetition of each in turn, N rounds - so a background load that lands
on one stretch of time lands on every command alike instead of on one
command's whole block - and stops on the first run whose output does
not match: a figure for work that was not done is worth nothing.

It prints one line per label, tab-separated:

    label  best_wall_s  median_wall_s  best_self  median_self  max_rss_kib

`wall` is the whole process, start-up included (time.perf_counter
around the run). `self` is the program's own reading, the last
whitespace-separated field of its output, when that field is a number
(the conc-bench modes print their own microseconds there). `max_rss`
comes from one more run of each command under `/usr/bin/time -l` (or
`-v`): the kernel's `ru_maxrss` for the process and, on Darwin, the
largest of the children it reaped - the largest single process, not
their sum.
"""
import os
import platform
import re
import shlex
import statistics
import subprocess
import sys
import time


def rss_kib(cmd):
    darwin = platform.system() == "Darwin"
    flag = "-l" if darwin or platform.system() == "FreeBSD" else "-v"
    p = subprocess.run(["/usr/bin/time", flag] + cmd, capture_output=True, text=True)
    for line in p.stderr.splitlines():
        if "maximum resident set size" in line:
            n = int(line.split()[0])
            return n // 1024 if darwin else n
        if "Maximum resident set size" in line:
            return int(line.split(":")[1])
    return -1


def main(argv):
    reps = int(argv[argv.index("--reps") + 1])
    spec = argv[-1]
    rows = []
    with open(spec) as f:
        for ln in f:
            if not ln.strip() or ln.startswith("#"):
                continue
            label, want, cmd = ln.rstrip("\n").split("\t")
            rows.append((label, re.compile(want), shlex.split(cmd)))
    wall = {r[0]: [] for r in rows}
    selft = {r[0]: [] for r in rows}
    for _ in range(reps):
        for label, want, cmd in rows:
            t0 = time.perf_counter()
            p = subprocess.run(cmd, capture_output=True, text=True)
            dt = time.perf_counter() - t0
            out = p.stdout.strip()
            if p.returncode != 0 or not want.fullmatch(out):
                print("WRONG %s: exit %d, output %r, wanted /%s/" % (label, p.returncode, out[:200], want.pattern))
                return 1
            wall[label].append(dt)
            last = out.split()[-1] if out else ""
            if re.fullmatch(r"-?[0-9]+", last):
                selft[label].append(int(last))
    for label, want, cmd in rows:
        w = wall[label]
        s = selft[label]
        print("\t".join([label, "%.6f" % min(w), "%.6f" % statistics.median(w),
                         str(min(s)) if s else "-", str(int(statistics.median(s))) if s else "-",
                         str(rss_kib(cmd))]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
