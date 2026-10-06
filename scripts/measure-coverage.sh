#!/usr/bin/env bash
# Structural coverage of the compiler's object code over its own test
# corpora, as qualification asks for. This is a measurement: like
# `measure-memory-baseline.sh`, it reports a number and fails only when
# the instrument itself is broken. `--quick` takes every fifth file.
#
#   scripts/measure-coverage.sh [--json PATH] [--quick]
#
# The compiler is rebuilt through the driver's own pipeline with
# SanitizerCoverage added after `opt`: one 8-bit counter per basic
# block, pruning off, plus a table of block addresses.
# `scripts/lib/axcov.c` moves the counters onto a file-backed shared
# mapping at start-up, so a run ending in a trap's raw `exit` syscall,
# which no destructor sees, is still recorded, and a forked `parallel`
# child shares its parent's file. `scripts/lib/coverage.py` merges runs
# and attributes blocks to functions by symbol.
#
# Before reporting, it checks the instrument: (1) counters leave the
# emitted IR byte-identical; (2) the backtracer is entered in a program
# that divides by zero and not in a clean one; (3) every run leaves
# both a counter and a metadata file, since a run that dies during
# start-up leaves one without the other; (4) a branch on the argument
# count reads one outcome, then both after a second run.
#
# It reports block coverage at --opt 1 and decision coverage of the
# same code. Each branch and switch outcome has its own counter, because
# level 3 splits critical edges first (`coverage.py decisions`).
#
# Limits. This is not MC/DC: a decision's conditions are the source's,
# and nothing below the front end keeps them. A block LLVM deleted is in
# neither numerator nor denominator. SanitizerCoverage skips a function
# whose entry block ends in `unreachable` (the single-block trap exits),
# so those count only through their callers. Inlined code counts in the
# function it was inlined into.
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
# Run with none, its first decision reads one outcome hit and one not;
# run again with an argument, both. A report blind to a missed outcome
# would read 1 1 the first time.
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
# One run of the instrumented compiler, with the argument orders the
# gates use. `fmt` takes `--check`, because without it `fmt` rewrites
# the file in place, and this loop runs over the repository.
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
