#!/usr/bin/env bash
# Produce the four rows of the website's benchmark table from the three
# programs beside this script, the way `web/src/data/bench.ts` says they
# were produced: whole-process wall clock, INTERLEAVED (one repetition of
# each binary in turn, so every binary sees the same interference), and
# the BEST of N rather than the mean, because interference only ever
# makes a run slower.
#
# Until 2026-09-04 no script did this. The table's methodology paragraph
# described a procedure that existed only as a description, and the
# figures were re-labelled from one release to the next without being
# re-run - the binary-size row was measured under 0.6.3 and published
# under 0.7.5. A number the site publishes must be something a reader
# can produce by running a command, and this is the command:
#
#   web/bench/run-bench.sh              # uses `axiom` on PATH
#   AXIOM=.axiom-bin/axiom web/bench/run-bench.sh
#   RUN_REPS=20 COMPILE_REPS=15 web/bench/run-bench.sh
#
# It prints the versions it measured with and one line per table cell.
# Transcribe those into bench.ts; the row notes are prose and stay.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
axiom="${AXIOM:-axiom}"
RUN_REPS="${RUN_REPS:-20}"
COMPILE_REPS="${COMPILE_REPS:-15}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "$here"/collatz.ax "$here"/collatz.rs "$here"/collatz.c "$work"/
cd "$work"

for tool in "$axiom" rustc clang nm; do
  command -v "$tool" >/dev/null || { echo "error: $tool is not on PATH" >&2; exit 1; }
done

# The exact commands bench.ts publishes under "so the table can be
# reproduced". Keep the two in step.
build_axiom() { "$axiom" build --input collatz.ax --output out-axiom >/dev/null; }
build_rust()  { rustc -O collatz.rs -o out-rust; }
build_c()     { clang -O2 collatz.c -o out-c; }

echo "== environment =="
echo "machine: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m), $(sw_vers -productName 2>/dev/null || uname -s) $(sw_vers -productVersion 2>/dev/null || uname -r)"
echo "axiom:   $("$axiom" version | head -1)"
echo "rust:    $(rustc --version)"
echo "c:       $(clang --version | head -1 | sed -E 's/.*clang version ([0-9.]+).*/clang \1/')"

# One build of each first, so the answer and the sizes come from binaries
# that exist before any timing starts.
build_axiom; build_rust; build_c
for b in out-axiom out-rust out-c; do
  got="$(./$b)"
  [[ "$got" == "428343467" ]] || { echo "error: $b printed $got, not 428343467 - not the same workload" >&2; exit 1; }
done
echo "answer:  428343467 from all three"

# Interleaved best-of-N over an arbitrary list of commands, in Python for
# a monotonic clock and a subprocess per run (the whole process is what
# a user waits for).
interleave() {
  python3 - "$@" <<'PY'
import subprocess, sys, time, shlex
reps = int(sys.argv[1])
cmds = [shlex.split(c) for c in sys.argv[2:]]
best = [None] * len(cmds)
for _ in range(reps):
    for i, cmd in enumerate(cmds):
        t = time.perf_counter()
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        d = time.perf_counter() - t
        best[i] = d if best[i] is None else min(best[i], d)
print(" ".join(f"{b:.3f}" for b in best))
PY
}

echo "== run time (best of $RUN_REPS, interleaved) =="
read -r ax rs c < <(interleave "$RUN_REPS" "./out-axiom" "./out-rust" "./out-c")
echo "axiom ${ax} s | rust ${rs} s | c ${c} s"

echo "== compile to a native binary (best of $COMPILE_REPS, interleaved) =="
read -r ax rs c < <(interleave "$COMPILE_REPS" \
  "$axiom build --input collatz.ax --output out-axiom" \
  "rustc -O collatz.rs -o out-rust" \
  "clang -O2 collatz.c -o out-c")
echo "axiom ${ax} s | rust ${rs} s | c ${c} s"

echo "== binary size (bytes on disk) =="
echo "axiom $(wc -c < out-axiom | tr -d ' ') | rust $(wc -c < out-rust | tr -d ' ') | c $(wc -c < out-c | tr -d ' ')"

echo "== undefined symbols (nm -u | wc -l) =="
echo "axiom $(nm -u out-axiom | wc -l | tr -d ' ') | rust $(nm -u out-rust | wc -l | tr -d ' ') | c $(nm -u out-c | wc -l | tr -d ' ')"
