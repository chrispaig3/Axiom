#!/usr/bin/env bash
# Where a compile spends its time, stage by stage.
#
# It answers which side of the process boundary the time is on. Work
# inside the Axiom process (lex, parse, resolve, expand, check, emit) and
# work outside it (`opt`, `llc`, `cc`) need different fixes. The outside
# work can already run in parallel with standard-library primitives.
# Splitting code generation into several LLVM modules is the largest
# compiler change available and the only one that risks the
# byte-identical fixpoint. Wait until this table shows the toolchain is
# where the time goes.
#
# Method, shared with `bench-datastructures.sh`:
#
#   - Each stage is timed as a whole process doing the real work, since
#     that is what a user waits for.
#   - The figure is the best of REPS hyperfine runs (`--runs REPS
#     --warmup 0`). Interference only slows a run, so the minimum is the
#     closest estimate of the cost.
#   - Process startup is timed separately, with the same binary doing
#     nothing, and subtracted. At these durations `execve` and dynamic
#     linking are a real fraction of the total.
#
# The stages overlap. `emit-llvm` repeats everything `check` does, so the
# difference between them is printed as its own row: lowering and the
# write. `check` returns before any IR exists (the `doEmit` test in
# `compileFile`, `self_host/main.ax`). That matters because `axiom lsp`
# runs `check` on every keystroke.
#
# It prints a table and never fails on a threshold: a wall-clock bound on
# a shared runner is a flaky test.
#
# The ablation: run again with `--opt 0`. The `opt` and `llc` rows must
# move and the `check` row must not. If every row moves together, the
# script is measuring process startup, not compilation.
#
# Usage:
#   scripts/bench-compile.sh                 # the compiler itself
#   scripts/bench-compile.sh --opt 0         # the ablation
#   scripts/bench-compile.sh --input F.ax    # some other program
#   REPS=3 scripts/bench-compile.sh          # fewer runs

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

REPS="${REPS:-5}"
opt=1
input="self_host/main.ax"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --opt)   opt="${2:-1}"; shift 2 ;;
    --input) input="${2:-}"; shift 2 ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
done
[[ -f "$input" ]] || { echo "no such input: $input" >&2; exit 2; }

for t in opt llc cc "${HYPERFINE:-hyperfine}"; do
  command -v "$t" >/dev/null 2>&1 || { echo "FAIL: $t is not on PATH; this script measures it" >&2; exit 1; }
done

# Best-of-REPS wall clock in seconds: the minimum of hyperfine's per-run
# times. It matches `bench-datastructures.sh`, so the two profiles compare.
time_best() {
  HF_BIN="${HYPERFINE:-hyperfine}" python3 - "$REPS" "$@" <<'PY'
import json, os, shlex, subprocess, sys, tempfile
reps = int(sys.argv[1])
cmd = shlex.join(sys.argv[2:])
with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
    path = f.name
subprocess.run([os.environ["HF_BIN"], "--warmup", "0", "--runs", str(reps),
                "--style", "none", "--export-json", path, cmd],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
print(f"{min(json.load(open(path))['results'][0]['times']):.6f}")
os.unlink(path)
PY
}

sub() { python3 -c "print(f'{max($1 - $2, 1e-6):.4f}')"; }
pct() { python3 -c "print(f'{100.0 * $1 / $2:5.1f}')"; }

echo "measuring $input at --opt $opt, best of $REPS runs..."

# Startup baselines: each tool loading and linking, then doing nothing.
ax_startup="$(time_best "$axiom" version)"
opt_startup="$(time_best opt --version)"
llc_startup="$(time_best llc --version)"
cc_startup="$(time_best cc --version)"

# The IR the toolchain stages consume, produced once up front.
"$axiom" emit-llvm "$input" -o "$work/m.ll" >/dev/null 2>&1 \
  || { echo "FAIL: could not emit IR for $input" >&2; exit 1; }
ir_lines="$(wc -l < "$work/m.ll" | tr -d ' ')"
ir_bytes="$(wc -c < "$work/m.ll" | tr -d ' ')"

opt "-O$opt" "$work/m.ll" -S -o "$work/m.opt.ll" >/dev/null 2>&1 \
  || { echo "FAIL: opt rejected the emitted IR" >&2; exit 1; }
llc "$work/m.opt.ll" -filetype=obj -o "$work/m.o" "-O$opt" -relocation-model=pic >/dev/null 2>&1 \
  || { echo "FAIL: llc rejected the optimised IR" >&2; exit 1; }

raw_check="$(time_best "$axiom" check "$input")"
raw_emit="$(time_best "$axiom" emit-llvm "$input" -o "$work/t.ll")"
raw_opt="$(time_best opt "-O$opt" "$work/m.ll" -S -o "$work/t.opt.ll")"
raw_llc="$(time_best llc "$work/m.opt.ll" -filetype=obj -o "$work/t.o" "-O$opt" -relocation-model=pic)"
raw_cc="$(time_best cc "$work/m.o" -o "$work/t.exe")"
raw_build="$(time_best "$axiom" build --input "$input" --output "$work/t.full" --opt "$opt")"

t_check="$(sub "$raw_check" "$ax_startup")"
t_emit="$(sub "$raw_emit"  "$ax_startup")"
t_opt="$(sub  "$raw_opt"   "$opt_startup")"
t_llc="$(sub  "$raw_llc"   "$llc_startup")"
t_cc="$(sub   "$raw_cc"    "$cc_startup")"
t_build="$(sub "$raw_build" "$ax_startup")"
t_lower="$(sub "$t_emit" "$t_check")"

# The two sides of the process boundary.
in_proc="$t_emit"
external="$(python3 -c "print(f'{$t_opt + $t_llc + $t_cc:.4f}')")"
total="$(python3 -c "print(f'{$in_proc + $external:.4f}')")"

echo
printf '%-34s %9s %8s\n' stage seconds "% of total"
printf '%s\n' "-------------------------------------------------------"
printf '%-34s %9s %7s%%\n' "check (lex, parse, expand, typecheck)" "$t_check" "$(pct "$t_check" "$total")"
printf '%-34s %9s %7s%%\n' "  + serialise and write the IR"  "$t_lower" "$(pct "$t_lower" "$total")"
printf '%-34s %9s %7s%%\n' "= in the axiom process"          "$in_proc" "$(pct "$in_proc" "$total")"
printf '%s\n' "-------------------------------------------------------"
printf '%-34s %9s %7s%%\n' "opt -O$opt"                      "$t_opt" "$(pct "$t_opt" "$total")"
printf '%-34s %9s %7s%%\n' "llc -O$opt"                      "$t_llc" "$(pct "$t_llc" "$total")"
printf '%-34s %9s %7s%%\n' "cc (link)"                       "$t_cc"  "$(pct "$t_cc"  "$total")"
printf '%-34s %9s %7s%%\n' "= external toolchain"            "$external" "$(pct "$external" "$total")"
printf '%s\n' "-------------------------------------------------------"
printf '%-34s %9s\n' "sum of stages" "$total"
printf '%-34s %9s\n' "axiom build, measured end to end" "$t_build"

echo
printf 'input          %s (%s lines of IR, %s bytes)\n' "$input" "$ir_lines" "$ir_bytes"
printf 'startup        axiom %ss, opt %ss, llc %ss, cc %ss (subtracted)\n' \
       "$(python3 -c "print(f'{$ax_startup:.4f}')")" \
       "$(python3 -c "print(f'{$opt_startup:.4f}')")" \
       "$(python3 -c "print(f'{$llc_startup:.4f}')")" \
       "$(python3 -c "print(f'{$cc_startup:.4f}')")"
printf 'host           %s %s\n' "$(uname -s)" "$(uname -m)"

# `axiom build` should land near the sum. A large gap means a stage this
# table does not name is doing real work.
gap="$(python3 -c "
s, b = $total, $t_build
print('the sum and the end-to-end build agree' if abs(b - s) <= 0.35 * max(b, s)
      else f'NOTE: end-to-end build differs from the sum of stages by {abs(b-s):.4f}s - a stage above is missing or double-counted')
")"
printf '%s\n' "$gap"

echo
echo "ablation: re-run with '--opt 0'. The opt and llc rows must move and"
echo "the check row must not. If every row moves together, this is"
echo "measuring process startup rather than compilation."
