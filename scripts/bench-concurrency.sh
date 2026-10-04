#!/usr/bin/env bash
# What the concurrency primitives cost on this machine: spawn and join
# in both lowerings, a task's round trip and its answer's copy, the
# mutex with and without contention, a channel's throughput and its
# uncontended send and receive, and the spread of a task's latency.
# Then, in a second half: how a CPU-bound workload scales, what false
# sharing costs, how small a piece of work a binding pays for, the
# latency distribution of a task and of a channel hand-off, what a
# byte of a task's answer costs, and the peak memory of each.
# `docs/status.md` quotes the figures.
#
#   scripts/bench-concurrency.sh            # REPS runs of each, best and median
#   REPS=9 REPS2=7 OPT=2 scripts/bench-concurrency.sh
#   W_SCALE=500000000 scripts/bench-concurrency.sh   # a shorter scaling run
#
# THE PROGRAM IS tests/litmus/conc-bench.ax. Each mode times its own
# work with the clock `sysTimeoutMicros` reads, so process start-up and
# the build are outside every figure, and checks its own answer: a
# wrong answer prints WRONG, and this script stops rather than report a
# time for work that was not done.
#
# WHAT THE FIGURES ARE. The best of REPS runs is the cost without
# interference, and the median says how much interference there was.
# They are measurements on one machine at one moment, not bounds, and
# the latency percentiles in particular are the scheduler's as much as
# the runtime's. This is not a gate: it asserts nothing but that every
# answer was right, and exits 0 when it was.
#
# THE SECOND HALF'S METHOD (`.claude/skills/performance-engineering`).
# `scripts/lib/benchrun.py` runs every command of a table round-robin,
# one repetition of each in turn, REPS2 rounds, so a background load
# lands on every command alike; it stops at the first run whose output
# is not the sequential program's answer. Scaling is timed as whole
# processes with the start-up of the same binary running `nop`
# subtracted; the other tables use the program's own clock. Every
# speedup divides the same work done in one loop by the parallel time,
# best by best and median by median. Peak RSS is `/usr/bin/time`'s
# `ru_maxrss`: for a forked lowering that is the largest single
# process, parent or child, not their sum, and `taskMap`'s slab is a
# shared mapping each child touches.
#
# MEASURED 2026-09-29 on Apple M1 (4 performance and 4 efficiency
# cores; `sysctl hw.cachelinesize` 128), --opt 2, best of 5 with the
# median in brackets, while other work held the load average near 6.5.
# A second run (best of 7, load 2 rising to 8) agreed on scaling, grain
# and false sharing and moved the latency tails. Width 8 spans both
# core kinds, so it cannot reach 8x.
#
#   scaling, 2e9 terms (1.39 s alone)   width 2      width 4      width 8
#     `parallel`, processes             1.99 (1.69)  3.29 (2.82)  4.28 (3.44)
#     `parallel`, threads               1.98 (1.94)  3.10 (2.91)  3.88 (3.72)
#     parMapWords                       1.98 (1.67)  3.32 (2.70)  3.97 (3.45)
#   grain, 4 bindings a form, speedup over one loop:
#     work per binding  7 us: processes 0.06, threads 0.29
#                      68 us: processes 0.46, threads 1.21
#                     684 us: processes 1.45, threads 1.93
#   false sharing, ns per atomic add, 4 bindings:
#     stride 8 (one line) 19.6 processes, 18.6 threads; stride 64 2.6, 3.4;
#     stride 128 1.9, 1.9; stride 256 2.0, 1.9
#   spawn and join per binding: processes 129 us (138), threads 28.5 (29.6)
#   a task's answer: 94 us fixed, then 0.16 to 0.19 ns a byte to 1 MiB
#   latency, us, p50 / p99 / max: a one-task pool 167 / 372 / 1247, the
#     same pool in a --threads build 805 / 1663 / 19393 (its fork goes
#     through libSystem there, MM-PAR-7); a channel round trip between
#     two bindings 7 / 22 / 301 processes, 6 / 29 / 236 threads
#   peak RSS: 1.7 to 2.1 MiB for every scaling, grain and spawn run;
#     a pool of 8 answering 64 B, 64 KiB, 1 MiB: 2.2, 28 and 62 MiB,
#     most of it the slab the children touch
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
# The compiler `gate_init` resolved ($AXIOM, $AXIOM_AXC, or the installed
# one), as `bench-par.sh` uses it: a measurement builds no compiler of its
# own, and so is not one of the gates `check-gate-lib.sh` counts.
axc="$axiom"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

REPS="${REPS:-7}"
opt="${OPT:-2}"
prog="$repo_root/tests/litmus/conc-bench.ax"

for lowering in processes threads; do
  flags=(); [[ "$lowering" == threads ]] && flags=(--threads)
  (cd "$repo_root" && "$axc" build ${flags[@]+"${flags[@]}"} --opt "$opt" --input "$prog" --output "$work/cb-$lowering") \
    > "$work/cb-$lowering.build" 2>&1 || { echo "error: conc-bench did not build ($lowering):"; sed 's/^/  /' "$work/cb-$lowering.build" | head -8; exit 1; }
done

# run <lowering> <mode args...>: REPS runs; prints "best median" of the
# microseconds field, or stops on a wrong answer.
run() {
  local lowering="$1"; shift
  local r out us=()
  for ((r = 0; r < REPS; r++)); do
    out="$(gate_timeout 300 "$work/cb-$lowering" "$@" 2>&1)" || { echo "error: conc-bench $* ($lowering) failed: $out" >&2; exit 1; }
    case "$out" in *WRONG*) echo "error: conc-bench $* ($lowering) answered wrong: $out" >&2; exit 1 ;; esac
    us+=("$(printf '%s\n' "$out" | awk '{print $NF}')")
  done
  printf '%s\n' "${us[@]}" | sort -n | awk '{a[NR]=$1} END {print a[1], a[int((NR+1)/2)]}'
}

per() {  # per <microseconds> <count> <unit scale> -> the cost of one, in the unit
  awk -v t="$1" -v n="$2" -v k="$3" 'BEGIN { printf "%.2f", t * k / n }'
}

echo "== concurrency costs: best and median of $REPS runs, --opt $opt, $(uname -sm) =="
echo

N_SPAWN=400
for lowering in processes threads; do
  read -r best med < <(run "$lowering" spawn "$N_SPAWN")
  echo "spawn+join, $lowering: $(per "$best" $((N_SPAWN * 2)) 1) us per binding (median $(per "$med" $((N_SPAWN * 2)) 1))"
done

N_TASKS=2000
for bytes in 64 4096 65536; do
  n=$N_TASKS; (( bytes == 65536 )) && n=400
  read -r best med < <(run processes tasks "$n" 8 "$bytes")
  mbps="$(awk -v t="$best" -v n="$n" -v b="$bytes" 'BEGIN { printf "%.1f", n * b / t }')"
  echo "task round trip, width 8, $bytes-byte answers: $(per "$best" "$n" 1) us per task (median $(per "$med" "$n" 1)); answers at $mbps MB/s"
done

N_MUTEX=200000
for lowering in processes threads; do
  read -r best med < <(run "$lowering" mutex "$N_MUTEX" 1)
  echo "mutex lock+unlock, uncontended, $lowering: $(per "$best" "$N_MUTEX" 1000) ns (median $(per "$med" "$N_MUTEX" 1000))"
  read -r best med < <(run "$lowering" mutex "$N_MUTEX" 4)
  echo "mutex lock+unlock, 4 bindings contending, $lowering: $(per "$best" $((N_MUTEX * 4)) 1000) ns per operation (median $(per "$med" $((N_MUTEX * 4)) 1000))"
done

N_CHAN=200000
for lowering in processes threads; do
  read -r best med < <(run "$lowering" chan "$N_CHAN")
  echo "channel, 1 sender to 1 receiver, capacity 64, $lowering: $(per "$best" "$N_CHAN" 1000) ns per word (median $(per "$med" "$N_CHAN" 1000))"
  read -r best med < <(run "$lowering" chan1 "$N_CHAN")
  echo "channel, uncontended send and receive, $lowering: $(per "$best" "$N_CHAN" 1000) ns per word (median $(per "$med" "$N_CHAN" 1000))"
done

out="$(gate_timeout 300 "$work/cb-processes" latency 500 2>&1)" || { echo "error: latency failed: $out" >&2; exit 1; }
echo "one-task pool round trip, 500 in a row: $(printf '%s' "$out" | sed 's/^latency 500 //') (microseconds)"

# =====================================================================
# THE SECOND HALF: scaling, false sharing, grain and latency, measured
# the way `.claude/skills/performance-engineering/SKILL.md` requires.
# `scripts/lib/benchrun.py` runs every command of a table ROUND-ROBIN,
# one repetition of each in turn for REPS2 rounds, checks each run's
# output against the answer the sequential program gives, and reports
# the best and the median. Whole-process figures have the start-up of
# the same binary running `nop` subtracted; in-process figures are the
# program's own clock around the work alone. Peak RSS is one more run
# of each under /usr/bin/time: the largest single process, which for
# the process lowering is the largest of the parent and its children,
# not their sum.
REPS2="${REPS2:-5}"
W_SCALE="${W_SCALE:-2000000000}"
bench="$repo_root/scripts/lib/benchrun.py"
echo
echo "== load when the second half started: $(uptime | sed 's/.*load averages*: //') =="

# ---- scaling ----------------------------------------------------------
# A pure hash of every i in 0 .. W, summed, split into K contiguous
# ranges: by `parallel` bindings in each lowering, and by `parMapWords`
# (which forks under both builds). Every run must print the sequential
# program's sum.
want="$("$work/cb-processes" work "$W_SCALE" | awk '{print $2}')"
spec="$work/scale.spec"
: > "$spec"
for lowering in processes threads; do
  b="$work/cb-$lowering"
  printf 'nop-%s\t\t%s nop\n' "$lowering" "$b" >> "$spec"
  printf 'seq-%s\twork %s [0-9]+\t%s work %s\n' "$lowering" "$want" "$b" "$W_SCALE" >> "$spec"
  for k in 1 2 4 8; do
    printf 'bind%s-%s\tbind %s [0-9]+\t%s bind %s %s\n' "$k" "$lowering" "$want" "$b" "$k" "$W_SCALE" >> "$spec"
    printf 'pool%s-%s\tpool %s [0-9]+\t%s pool %s %s\n' "$k" "$lowering" "$want" "$b" "$k" "$W_SCALE" >> "$spec"
  done
done
python3 "$bench" --reps "$REPS2" "$spec" > "$work/scale.out" || { cat "$work/scale.out"; exit 1; }
echo
echo "== scaling: $W_SCALE hash terms summed, whole processes, start-up subtracted, best of $REPS2 (median) =="
python3 - "$work/scale.out" <<'PY'
import sys
rows = {}
for ln in open(sys.argv[1]):
    label, best, med, sbest, smed, rss = ln.rstrip("\n").split("\t")
    rows[label] = (float(best), float(med), rss)
for low in ("processes", "threads"):
    nb, nm, _ = rows["nop-" + low]
    sb, sm, srss = rows["seq-" + low]
    sb, sm = sb - nb, sm - nm
    print("%s build: sequential %.3f s (%.3f), peak RSS %s KiB; start-up %.1f ms subtracted" % (low, sb, sm, srss, nb * 1000))
    print("  %-10s %-26s %-26s" % ("width", "parallel bindings", "parMapWords (forks)"))
    for k in (1, 2, 4, 8):
        cells = []
        for kind in ("bind", "pool"):
            b, m, rss = rows["%s%d-%s" % (kind, k, low)]
            b, m = b - nb, m - nm
            cells.append("%.2fx (%.2fx) %s KiB" % (sb / b, sm / m, rss))
        print("  %-10d %-26s %-26s" % (k, cells[0], cells[1]))
PY

# ---- grain ------------------------------------------------------------
# R forms of 4 bindings, each summing W terms, against the same terms in
# one loop, in-process: the smallest piece of work a binding pays for.
spec="$work/grain.spec"
: > "$spec"
for lowering in processes threads; do
  b="$work/cb-$lowering"
  for w in 1000 10000 100000 1000000; do
    r=$(( 20000000 / (4 * w) )); (( r > 2000 )) && r=2000
    s="$("$b" grainseq 4 "$w" "$r" | awk '{print $2}')"
    printf 'seq-%s-%s\tgrainseq %s [0-9]+\t%s grainseq 4 %s %s\n' "$w" "$lowering" "$s" "$b" "$w" "$r" >> "$spec"
    printf 'par-%s-%s\tgrain %s [0-9]+\t%s grain 4 %s %s\n' "$w" "$lowering" "$s" "$b" "$w" "$r" >> "$spec"
  done
done
python3 "$bench" --reps "$REPS2" "$spec" > "$work/grain.out" || { cat "$work/grain.out"; exit 1; }
echo
echo "== grain: 4 bindings per form, each summing W terms; speedup over one loop, best of $REPS2 (median) =="
python3 - "$work/grain.out" <<'PY'
import sys
rows = {}
for ln in open(sys.argv[1]):
    label, best, med, sbest, smed, rss = ln.rstrip("\n").split("\t")
    rows[label] = (int(sbest), int(smed))
print("  %-10s %-12s %-22s %-22s" % ("W terms", "per binding", "processes", "threads"))
for w in (1000, 10000, 100000, 1000000):
    cells = []
    per = None
    for low in ("processes", "threads"):
        sb, sm = rows["seq-%d-%s" % (w, low)]
        pb, pm = rows["par-%d-%s" % (w, low)]
        cells.append("%.2fx (%.2fx)" % (sb / pb, sm / pm))
        r = min(2000, 20000000 // (4 * w))
        per = sb / (r * 4)
    print("  %-10d %-12s %-22s %-22s" % (w, "%.1f us" % per, cells[0], cells[1]))
PY

# ---- false sharing ------------------------------------------------------
# K bindings each add 1 to a word of their own, N times, with an atomic
# read-modify-write; the words are S bytes apart in one page. This host
# is Apple M1, whose cache line is 128 bytes (`sysctl hw.cachelinesize`):
# S 8 puts every word in one line, S 64 two words per line, S 128 and
# 256 one word per line.
spec="$work/fshare.spec"
: > "$spec"
N_FS=2000000
for lowering in processes threads; do
  for k in 2 4 8; do
    for s in 8 64 128 256; do
      printf 'fs-%s-%s-%s\tfshare %s [0-9]+\t%s fshare %s %s %s\n' "$k" "$s" "$lowering" "$((k * N_FS))" "$work/cb-$lowering" "$k" "$s" "$N_FS" >> "$spec"
    done
  done
done
python3 "$bench" --reps "$REPS2" "$spec" > "$work/fshare.out" || { cat "$work/fshare.out"; exit 1; }
echo
echo "== false sharing: ns per atomic increment, $N_FS per binding, best of $REPS2 (median) =="
python3 - "$work/fshare.out" "$N_FS" <<'PY'
import sys
n = int(sys.argv[2])
rows = {}
for ln in open(sys.argv[1]):
    label, best, med, sbest, smed, rss = ln.rstrip("\n").split("\t")
    rows[label] = (int(sbest), int(smed))
for low in ("processes", "threads"):
    print("%s:" % low)
    print("  %-10s %-16s %-16s %-16s %-16s" % ("bindings", "stride 8", "stride 64", "stride 128", "stride 256"))
    for k in (2, 4, 8):
        cells = []
        for s in (8, 64, 128, 256):
            b, m = rows["fs-%d-%d-%s" % (k, s, low)]
            cells.append("%.2f (%.2f)" % (b * 1000.0 / (k * n), m * 1000.0 / (k * n)))
        print("  %-10d %-16s %-16s %-16s %-16s" % tuple([k] + cells))
PY

# ---- latency --------------------------------------------------------------
# A pool of one task, and a word handed to a sibling binding and back on
# two channels, each timed alone. REPS2 runs of N; each percentile is
# reported as the median over the runs, and the worst as the worst.
spec="$work/lat.spec"
: > "$spec"
for lowering in processes threads; do
  printf 'task-%s\tlatency 2000 p50 [0-9]+ p90 [0-9]+ p99 [0-9]+ max [0-9]+\t%s latency 2000\n' "$lowering" "$work/cb-$lowering" >> "$spec"
  printf 'pp-%s\tpingpong 5000 p50 [0-9]+ p90 [0-9]+ p99 [0-9]+ max [0-9]+\t%s pingpong 5000\n' "$lowering" "$work/cb-$lowering" >> "$spec"
done
python3 - "$bench" "$REPS2" "$spec" <<'PY'
import re, shlex, statistics, subprocess, sys
bench, reps, spec = sys.argv[1], int(sys.argv[2]), sys.argv[3]
rows = [ln.rstrip("\n").split("\t") for ln in open(spec) if ln.strip()]
got = {r[0]: [] for r in rows}
for _ in range(reps):
    for label, want, cmd in rows:
        out = subprocess.run(shlex.split(cmd), capture_output=True, text=True).stdout.strip()
        if not re.fullmatch(want, out):
            print("WRONG %s: %r" % (label, out)); sys.exit(1)
        f = out.split()
        got[label].append(dict(zip(f[2::2], map(int, f[3::2]))))
print()
print("== latency, microseconds on the program's clock: median of %d runs per percentile, worst of all runs ==" % reps)
names = {"task": "one-task pool round trip (2,000 in a row)", "pp": "channel round trip between two bindings (5,000)"}
for label, _, _ in rows:
    kind, low = label.split("-")
    g = got[label]
    print("  %-48s %-10s p50 %4d  p90 %4d  p99 %5d  max %6d" % (
        names[kind], low, statistics.median(x["p50"] for x in g), statistics.median(x["p90"] for x in g),
        statistics.median(x["p99"] for x in g), max(x["max"] for x in g)))
PY

# ---- process against thread, and what a byte costs ---------------------
echo
echo "== what crosses: a task's answer through Task's slab, processes only (a thread binding answers a word) =="
# The cost of a byte is the SLOPE: each size's time per task less the
# 64-byte answer's, over the extra bytes, since a task's fixed cost
# (fork, join, the wake) dwarfs 64 bytes.
base=""
for bytes in 64 65536 1048576; do
  n=2000; (( bytes >= 65536 )) && n=400; (( bytes >= 1048576 )) && n=50
  read -r best med < <(run processes tasks "$n" 8 "$bytes")
  per="$(awk -v t="$best" -v n="$n" 'BEGIN { printf "%.3f", t / n }')"
  [[ -z "$base" ]] && base="$per"
  printf '%-8s bytes: %s us per task (median %s), %s, peak RSS %s KiB\n' "$bytes" "$per" \
    "$(awk -v m="$med" -v n="$n" 'BEGIN { printf "%.1f", m / n }')" \
    "$(awk -v p="$per" -v b0="$base" -v b="$bytes" 'BEGIN { if (b > 64) printf "%.3f ns per byte over the 64-byte task", (p - b0) * 1000 / (b - 64); else printf "the fixed cost" }')" \
    "$(max_rss_kb "$work/cb-processes" tasks "$n" 8 "$bytes")"
done
echo "peak RSS of the spawn workload: processes $(max_rss_kb "$work/cb-processes" spawn 400) KiB, threads $(max_rss_kb "$work/cb-threads" spawn 400) KiB"
