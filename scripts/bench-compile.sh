#!/usr/bin/env bash
# Where a compile actually spends its time.
#
# This project has no compile-time profile and never has. The only
# wall-clock figure anywhere in it is the `strConcat` fix - a self-compile
# went 11.54s to 0.85s when a quadratic concatenation in code generation
# was replaced (docs/self-hosting.md 7). The lesson recorded there is the
# reason this script exists:
#
#   "The self-hosted compiler's dominant cost was not lexing, parsing,
#    checking or lowering. It was the last line of code generation."
#
# Nobody predicted that, and nothing has measured where the time goes
# since. P5's remaining deliverable is a "published performance profile";
# this is it.
#
# WHAT IT DECIDES. Any plan to parallelise the compiler has to know which
# side of the process boundary the time is on. Work inside the Axiom
# process (lex, parse, resolve, expand, check, emit) and work outside it
# (`opt`, `llc`, `cc`) need completely different answers, and the second
# is already parallelisable with primitives the standard library ships
# today. Splitting code generation into several LLVM modules is the
# largest available compiler change and the only one that puts the
# byte-identical fixpoint at risk; it should not be attempted until this
# table says the toolchain is where the time is.
#
# METHODOLOGY, inherited from `bench-datastructures.sh`:
#
#   - Every stage is timed as a WHOLE PROCESS doing the real work, not
#     as an in-process timer, because that is what a user waits for.
#   - Best of REPS runs, not the mean. The distribution is one-sided -
#     interference only ever makes a run slower - so the minimum is the
#     closest estimate of the cost itself.
#   - Process startup is measured separately, with the same binary doing
#     nothing, and subtracted. At these durations `execve` plus dynamic
#     linking is a real fraction of the total, and it is not compilation.
#
# The stages are NOT a partition and the script does not pretend they
# are. `emit-llvm` re-does everything `check` does and then writes the
# result out, so the difference between them is printed as its own row
# rather than left to the reader.
#
# THAT ROW IS LOWERING AND THE WRITE, and this comment said otherwise
# for months. It read: "`compileFile` calls `emitResolved`
# unconditionally (`main.ax:320`) - `doEmit` decides whether the IR is
# WRITTEN, not whether it is generated. So `axiom check` already pays
# for code generation and then throws it away."
#
# It does not. `main.ax:340` reads `(if (== doEmit 0) "" ...
# (emitResolved ...))`, so `check` returns before a byte of IR exists.
# Measured two ways rather than re-read: `check` is 1.32s against
# `emit-llvm` 1.77s on `main.ax`, and eight sampling profiles of `axiom
# check` contain ZERO `codegen$` frames. The cited line number was stale
# as well.
#
# It matters because `check` is what `axiom lsp` runs on every
# keystroke, and the old note priced that keystroke with a code
# generator in it.
#
# This prints a table. It does not fail on a threshold - a wall-clock
# bound on a shared runner is a flaky test, which is the same call
# `bench-datastructures.sh` makes and for the same reason.
#
# THE ABLATION, which is what stops this being a stopwatch pointed at
# nothing: run it again with `--opt 0`. The `opt` and `llc` rows must
# move and the `check` row must not. If every row moves together, the
# script is measuring process startup and not compilation.
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

for t in opt llc cc; do
  command -v "$t" >/dev/null 2>&1 || { echo "FAIL: $t is not on PATH; this script measures it" >&2; exit 1; }
done

# Best-of-REPS wall clock in seconds. Lifted from
# `bench-datastructures.sh:286` so the two profiles are comparable.
time_best() {
  python3 - "$REPS" "$@" <<'PY'
import subprocess, sys, time
reps = int(sys.argv[1]); cmd = sys.argv[2:]
best = None
for _ in range(reps):
    t = time.perf_counter()
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    d = time.perf_counter() - t
    best = d if best is None else min(best, d)
print(f"{best:.6f}")
PY
}

sub() { python3 -c "print(f'{max($1 - $2, 1e-6):.4f}')"; }
pct() { python3 -c "print(f'{100.0 * $1 / $2:5.1f}')"; }

echo "measuring $input at --opt $opt, best of $REPS runs..."

# Startup baselines. Each tool doing as close to nothing as it can while
# still loading and linking.
ax_startup="$(time_best "$axiom" version)"
opt_startup="$(time_best opt --version)"
llc_startup="$(time_best llc --version)"
cc_startup="$(time_best cc --version)"

# The IR the toolchain stages actually consume, produced once up front.
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

# The two sides of the process boundary, which is the whole question.
in_proc="$t_emit"
external="$(python3 -c "print(f'{$t_opt + $t_llc + $t_cc:.4f}')")"
total="$(python3 -c "print(f'{$in_proc + $external:.4f}')")"

echo
printf '%-34s %9s %8s\n' stage seconds "% of total"
printf '%s\n' "-------------------------------------------------------"
printf '%-34s %9s %7s%%\n' "check (incl. codegen, discarded)" "$t_check" "$(pct "$t_check" "$total")"
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

# `axiom build` should be within reach of the sum; a large gap means a
# stage this table does not name is doing real work, which is worth
# knowing rather than rounding away.
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
