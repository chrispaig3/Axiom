#!/usr/bin/env bash
# Structural coverage of the compiler's object code over its own test
# corpora: the measurement qualification asks for and this repository
# did not have. A MEASUREMENT, not a gate - like
# `measure-memory-baseline.sh`, it reports a number and fails only when
# the instrument itself is broken.
#
#   scripts/measure-coverage.sh [--json PATH] [--quick]
#
# HOW. The compiler under test is rebuilt from `self_host/main.ax`
# through the driver's own pipeline - `emit-llvm`, `opt -O1`, `llc -O1
# -relocation-model=pic`, `cc` - with one pass added after `opt`:
# SanitizerCoverage, one 8-bit counter per basic block with pruning OFF
# (`-sanitizer-coverage-prune-blocks=0`), plus a table of block
# addresses. `scripts/lib/axcov.c` is linked in: at start-up it moves
# the counters' pages onto a file-backed shared mapping, so a run that
# ends in a trap's raw `exit` syscall - which no destructor sees - is
# recorded like one that returns, and a forked `parallel` child's
# blocks land in the same file as its parent's. `scripts/lib/coverage.py`
# ORs the runs and attributes each block to a function by symbol.
#
# THE CORPORA RUN, from the repository root: `check` over every
# tests/diagnostics fixture (the front end and the diagnostics),
# `emit-llvm` over tests/stdlib and tests/selfhost (the back end),
# `emit-llvm self_host/main.ax` (the self-compile), `fmt --check` over
# tests/fmt, `symbols --calls` and `explain` (the tools). `--quick` takes
# every fifth file of each corpus.
#
# THE INSTRUMENT IS CHECKED BEFORE IT IS BELIEVED:
#   1. the instrumented compiler emits byte-identical IR to the plain
#      one on a sample of inputs - the counters changed nothing it does;
#   2. two small programs through the same pipeline: the backtracer is
#      entered in the one that divides by zero and not in the one that
#      does not - hits are recorded, trap paths included, and they are
#      not recorded everywhere;
#   3. every run left a counter file and a metadata file (a run that
#      died before start-up finished would leave one without the other);
#   4. a program branching on its argument count reads its decision as
#      one outcome of two after a run with no argument, and both after a
#      second run with one.
#
# WHAT THE NUMBERS ARE: block coverage of the object code at --opt 1 over
# the inputs run, and decision coverage of the same object code - every
# conditional branch and switch of the instrumented IR, each outcome a
# counter of its own because level 3 splits critical edges first
# (`coverage.py decisions`). Not MC/DC: a decision's conditions are the
# source's, and below the front end nothing keeps them. A block LLVM deleted
# is in neither the numerator nor the denominator. SanitizerCoverage
# does not instrument a function whose entry block ends in
# `unreachable` - the single-block trap exits - so those are reached
# only through their callers' blocks. Blocks are attributed by symbol,
# so code LLVM inlined is counted in the function it was inlined into.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

json=""
quick=0
while (( $# )); do
  case "$1" in
    --json) json="$2"; shift 2 ;;
    --quick) quick=1; shift ;;
    *) echo "usage: $0 [--json PATH] [--quick]" >&2; exit 2 ;;
  esac
done

for t in opt llc cc nm python3; do
  command -v "$t" >/dev/null 2>&1 || { echo "FAIL: $t is not on PATH; the instrument cannot be built"; exit 1; }
done

rt="$repo_root/scripts/lib/axcov.c"
lib="$repo_root/scripts/lib/coverage.py"
export AXIOM_PATH="$repo_root/stdlib"
sancov=(-passes=sancov-module -sanitizer-coverage-level=3 -sanitizer-coverage-prune-blocks=0
        -sanitizer-coverage-inline-8bit-counters -sanitizer-coverage-pc-table)

instrument() {  # instrument <ll> <out>: the driver's pipeline plus the counters
  local ll="$1" out="$2"
  opt -O1 "$ll" -S -o "$out.opt.ll" \
    && opt "${sancov[@]}" "$out.opt.ll" -S -o "$out.cov.ll" \
    && llc "$out.cov.ll" -filetype=obj -o "$out.o" -O1 -relocation-model=pic \
    && cc "$out.o" "$work/axcov.o" -o "$out"
}

failed=0
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

echo "== building the instrumented compiler =="
cc -c -O1 "$rt" -o "$work/axcov.o" || { echo "FAIL: $rt does not compile"; exit 1; }
"$axc" emit-llvm "$repo_root/self_host/main.ax" -o "$work/axc.ll" > "$work/emit.log" 2>&1 \
  || { echo "FAIL: the compiler under test could not emit itself"; tail -3 "$work/emit.log"; exit 1; }
instrument "$work/axc.ll" "$work/axc-cov" > "$work/instr.log" 2>&1 \
  || { echo "FAIL: the instrumented build failed"; tail -5 "$work/instr.log"; exit 1; }
cov="$work/axc-cov"
echo "   $(grep -c '__sancov_gen_' "$work/axc-cov.cov.ll") counter references in the instrumented IR"

echo "== 1. the counters change nothing the compiler does =="
n=0
for f in tests/stdlib/070-vec.ax tests/stdlib/130-booleans.ax tests/embedded/blink.ax self_host/lexer.ax; do
  "$axc" emit-llvm "$repo_root/$f" -o "$work/plain.ll" >/dev/null 2>&1
  "$cov" emit-llvm "$repo_root/$f" -o "$work/instr.ll" >/dev/null 2>&1
  if cmp -s "$work/plain.ll" "$work/instr.ll"; then
    n=$((n + 1))
  else
    bad "the instrumented compiler emits different IR for $f"
  fi
done
echo "   $n of 4 inputs: byte-identical IR"

echo "== 2. the instrument sees hits, trap paths included, and not everywhere =="
printf '(:: main Int)\n(fn (main)\n  (+ 2 3))\n' > "$work/clean.ax"
printf '(:: main Int)\n(fn (main)\n  (/ 10 (- 3 3)))\n' > "$work/trap.ax"
for t in clean trap; do
  "$axc" emit-llvm "$work/$t.ax" -o "$work/$t.ll" >/dev/null 2>&1 && instrument "$work/$t.ll" "$work/$t" > /dev/null 2>&1 \
    || { bad "the control program $t does not build"; continue; }
  mkdir -p "$work/c-$t"
  AXIOM_COV_DIR="$work/c-$t" "$work/$t" > /dev/null 2>&1
  python3 "$lib" merge "$work/c-$t" "$work/c-$t/acc" > /dev/null
done
bt_clean="$(python3 "$lib" entered "$work/c-clean" "$work/c-clean/acc" "$work/clean" __axiom_backtrace 2>/dev/null)"
bt_trap="$(python3 "$lib" entered "$work/c-trap" "$work/c-trap/acc" "$work/trap" __axiom_backtrace 2>/dev/null)"
if [[ "$bt_clean" == 0 && "$bt_trap" == 1 ]]; then
  echo "   the backtracer: entered 1 in the trapping control, 0 in the clean one"
else
  bad "the backtracer reads [$bt_clean] clean and [$bt_trap] trapping; wanted 0 and 1"
fi

# The decision half: a program that branches on its argument count.
# Run with none, its first decision must read one outcome hit and one
# not; run again with an argument, both. A decision report that could
# not see an outcome missed would read 1 1 the first time.
printf '(import IO)\n\n(:: main Int)\n;@axiom:effect(io)\n(fn (main)\n  {\n    (if (> (__argc) 1)\n      (println "an argument")\n      (println "none"))\n    0\n  })\n' > "$work/arg.ax"
if "$axc" emit-llvm "$work/arg.ax" -o "$work/arg.ll" >/dev/null 2>&1 && instrument "$work/arg.ll" "$work/arg" > /dev/null 2>&1; then
  mkdir -p "$work/c-arg"
  AXIOM_COV_DIR="$work/c-arg" "$work/arg" > /dev/null 2>&1
  python3 "$lib" merge "$work/c-arg" "$work/c-arg/acc" > /dev/null
  one="$(python3 "$lib" decisions "$work/c-arg" "$work/c-arg/acc" "$work/arg" "$work/arg.cov.ll" --fn __axiom_user_main | head -1 | awk '{print $4, $5}')"
  AXIOM_COV_DIR="$work/c-arg" "$work/arg" x > /dev/null 2>&1
  python3 "$lib" merge "$work/c-arg" "$work/c-arg/acc" > /dev/null
  both="$(python3 "$lib" decisions "$work/c-arg" "$work/c-arg/acc" "$work/arg" "$work/arg.cov.ll" --fn __axiom_user_main | head -1 | awk '{print $4, $5}')"
  if [[ "$one" == "0 1" && "$both" == "1 1" ]]; then
    echo "   decisions: main's branch read [0 1] with no argument and [1 1] with one"
  else
    bad "main's branch read [$one] with no argument and [$both] after one too; wanted [0 1] then [1 1]"
  fi
else
  bad "the decision control program does not build"
fi

(( failed == 0 )) || { echo "measure-coverage: the instrument is broken ($failed); no number reported"; exit 1; }

echo "== 3. the corpora =="
d="$work/runs"
mkdir -p "$d"
nth() { if (( quick )); then awk 'NR % 5 == 1'; else cat; fi; }
runs=0
# One run of the instrumented compiler. Argument orders are the ones
# the gates already use; `fmt` in particular is spelled `fmt FILE
# --check`, because `fmt` without `--check` rewrites the file in place
# and this loop runs over the repository.
run_one() {  # run_one <mode> <file>
  case "$1" in
    check) "$cov" --diagnostic-format=ai check "$2" ;;
    emit)  "$cov" emit-llvm "$2" -o "$work/out.ll" ;;
    fmt)   "$cov" fmt "$2" --check ;;
    syms)  "$cov" --diagnostic-format=ai symbols --calls "$2" ;;
    explain) "$cov" explain "$2" ;;
  esac
}
corpus() {  # corpus <label> <mode> -- files on stdin
  local label="$1" mode="$2" k=0 f
  while IFS= read -r f; do
    AXIOM_COV_DIR="$d" run_one "$mode" "$f" > /dev/null 2>&1 < /dev/null
    k=$((k + 1))
  done
  runs=$((runs + k))
  local merged; merged="$(python3 "$lib" merge "$d" "$d/acc")"
  echo "   $label: $k runs ($merged)"
  case "$merged" in *" 0 unfinished") ;; *) bad "$label: a run left a counter file with no metadata" ;; esac
  case "$merged" in "$k runs merged"*) ;; *) bad "$label: $k runs made, but [$merged]" ;; esac
}
cd "$repo_root"
before="$(git status --porcelain | LC_ALL=C sort)"
corpus "check tests/diagnostics" check < <(git ls-files 'tests/diagnostics/*.ax' | nth)
corpus "emit-llvm tests/stdlib + tests/selfhost" emit < <(git ls-files 'tests/stdlib/*.ax' 'tests/selfhost/*.ax' | nth)
corpus "emit-llvm self_host/main.ax" emit < <(echo self_host/main.ax)
corpus "fmt --check tests/fmt" fmt < <(git ls-files 'tests/fmt/*.ax' | nth)
corpus "symbols --calls" syms < <(git ls-files 'tests/stdlib/*.ax' | awk 'NR % 10 == 1')
corpus "explain" explain < <(printf 'AX3049\nAX1001\n')
after="$(git status --porcelain | LC_ALL=C sort)"
[[ "$before" == "$after" ]] || bad "the corpus runs changed the working tree (git status moved)"

echo "== 4. the report =="
python3 "$lib" report "$d" "$d/acc" "$cov" ${json:+--json "$json"}
python3 "$lib" decisions "$d" "$d/acc" "$cov" "$work/axc-cov.cov.ll"
echo
if (( failed > 0 )); then
  echo "measure-coverage: $failed instrument check(s) failed - the number above is not evidence"
  exit 1
fi
echo "measure-coverage: $runs runs; block and decision coverage of the compiler's object code at --opt 1"
