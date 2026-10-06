#!/usr/bin/env bash
# What the concurrency primitives cost on this machine. The first half
# times spawn and join in both lowerings, a task's round trip and the
# copy of its answer, the mutex with and without contention, a channel's
# throughput and its uncontended send and receive, and the spread of a
# task's latency. The second half times how CPU-bound work scales, what
# false sharing costs, the smallest work a binding pays for, task and
# channel latency, the cost of a byte of a task's answer, and peak
# memory. `docs/memory-model.md` cites it for the cost of an uncontended
# send and receive.
#
#   scripts/bench-concurrency.sh            # REPS runs of each, best and median
#   REPS=9 REPS2=7 OPT=2 scripts/bench-concurrency.sh
#   W_SCALE=500000000 scripts/bench-concurrency.sh   # a shorter scaling run
#
# The program is tests/litmus/conc-bench.ax. Each mode times its own work
# with the clock `sysTimeoutMicros` reads, so start-up and the build stay
# outside every figure. Each mode also checks its own answer: a wrong one
# prints WRONG, and this script stops rather than time work not done.
#
# The best of REPS runs is the cost without interference, and the median
# shows how much interference there was. The figures are measurements on
# one machine, not bounds, and the latency percentiles reflect the
# scheduler as much as the runtime. This is not a gate: it asserts only
# that every answer was right, and exits 0 when it was.
#
# On a machine with four performance and four efficiency cores, width 8
# spans both kinds and can't reach 8x. On Darwin a pool in a `--threads`
# build forks through libSystem (MM-PAR-7), which shows in its latency.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
# Use the compiler `gate_init` resolved ($AXIOM, $AXIOM_AXC or the
# installed one), as `bench-par.sh` does. A measurement builds no compiler
# of its own, so `check-gate-lib.sh` doesn't count it as a gate.
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
# The second half: scaling, false sharing, grain and latency, measured
# as `.claude/skills/performance-engineering/SKILL.md` describes.
# `scripts/lib/benchrun.py` runs every command of a table round-robin,
# one repetition of each per round for REPS2 rounds, so background load
# lands on every command alike. It checks each run's output against the
# sequential program's answer and reports the best and the median.
# Whole-process figures subtract the start-up of the same binary running
# `nop`; in-process figures use the program's own clock. Every speedup
# divides the one-loop time by the parallel time, best by best and median
# by median. Peak RSS is `ru_maxrss` from one more run under
# /usr/bin/time. For the process lowering that is the largest single
# process, parent or child, not their sum, and `taskMap`'s slab is a
# shared mapping each child touches.
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
# read-modify-write; the words are S bytes apart in one page. On Apple M1
# the cache line is 128 bytes (`sysctl hw.cachelinesize`), so S 8 puts
# every word in one line, S 64 two words per line, and S 128 and 256 one
# word per line.
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

# ---- what a byte of a task's answer costs ------------------------------
echo
echo "== what crosses: a task's answer through Task's slab, processes only (a thread binding answers a word) =="
# The cost of a byte is the slope: each size's time per task less the
# 64-byte answer's, over the extra bytes. A task's fixed cost (fork, join,
# the wake) dwarfs 64 bytes.
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
