#!/usr/bin/env bash
#
# How much STACK the compiler needs to check the largest Axiom program
# there is, as a number, bisected and reported.
#
# WHY THIS EXISTS. This backend eliminates only SELF tail calls, and a
# `let` body is not a tail position (codegen.ax's `tailCallsSelf`), so
# the shape
#
#     (let ((e (vecGet v i))) (if ... e (recur ...)))
#
# costs one real stack frame per loop iteration. `typecheck.ax` is
# written almost entirely in that shape and contains no `while` at all,
# so a dozen of its table walks are one frame per table entry. That has
# produced three separate SIGSEGVs in this repository's history, each
# presenting as a crash in whatever was being compiled rather than in
# the walk: `memCopyFrom` on a few hundred KB, `lookupByIdx` 25 frames
# deep in stage2, and `scanAxtagsFrom` one frame per source byte.
#
# Nothing measured it. The alternative to this gate was converting every
# such walk to a `while` - a large diff across the most
# correctness-critical file in the tree, competing for the same lines as
# real work, to buy headroom nobody had priced. Measured first instead:
# `check self_host/main.ax` needs about 224 KiB against an 8 MiB
# default, which is roughly 36x headroom. The conversions are not
# urgent; knowing when that stops being true is.
#
# So this gate turns the whole frames-per-entry class into ONE number
# that regresses visibly, and costs a handful of sub-second runs.
#
# WHAT IT ASSERTS.
#   * The minimum stack at which `check self_host/main.ax` succeeds,
#     found by bisection, is under a ceiling. Reported either way, so a
#     change that doubles it is visible in the log before it is a
#     failure.
#   * At half that minimum the process must die by SIGNAL - exit 139,
#     not merely non-zero. Without this half the bisection could report
#     any number at all and the ceiling would still pass: a run that
#     failed for an unrelated reason looks identical to one that ran out
#     of stack. This is the repository's standing rule that an assertion
#     about the PROCESS beats one about its output.
#   * The successful run must print `OK`. A compiler that exits 0 having
#     done nothing needs very little stack.
#
# NOT A DIFFERENTIAL, and it does not need to be: the quantity is the
# compiler's own resource use, and the assertion is derived from the
# process's exit status rather than from any output a re-bless could
# rewrite.
#
# THE STATIC HALF OF THE SAME QUESTION is `;@axiom:restrict(no-recursion)`
# (docs/reference.md, AXTAG Keys; scripts/check-restrictions.sh): a
# declaration under it may reach no cycle in the call graph, which is
# the property that makes a region's stack need bounded by its depth
# rather than by its input. This gate measures the compiler's need
# dynamically because the compiler is written in the recursive shape
# above and claims no such restriction; a region that does claim one
# is refused at `check` time with the cycle rendered, and needs no
# measuring.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

# The ceiling is deliberately loose. The measured need on darwin-aarch64
# is ~224 KiB; a ceiling of 1 MiB still catches a regression that makes
# the requirement grow with program size - which is the failure this
# exists for - while leaving room for another platform's frame layout
# and another toolchain's spilling decisions. A tight ceiling here would
# be a gate about the host, not about the compiler.
ceiling_kib=1024
subject="self_host/main.ax"

# Measure a compiler built from the CURRENT sources, not whichever binary
# happens to be installed: the property is about the code in this tree,
# and `$AXIOM` here is only the builder - the same division of labour the
# other `*-selfhost` gates use, and the reason pointing `AXIOM=` at an
# old binary does not ablate any of them.
if ! "$axiom" build --input self_host/main.ax --output "$work/stage1" \
       --opt 1 >"$work/build.log" 2>&1; then
  echo "FAIL: could not build a compiler from self_host/" >&2
  tail -20 "$work/build.log" >&2
  exit 1
fi
axiom="$work/stage1"

# One run at a given stack limit. Answers "ok", "signal", or "other:<rc>".
run_at() {
  local kib="$1" rc out
  out="$( (ulimit -s "$kib" 2>/dev/null || exit 200; "$axiom" check "$subject") 2>"$work/err" )"
  rc=$?
  if [[ "$rc" -eq 200 ]]; then echo "unsettable"; return; fi
  if [[ "$rc" -eq 0 ]]; then
    # Prove the work happened: a silent exit 0 needs no stack at all.
    if [[ "$out" == *OK* ]]; then echo "ok"; else echo "other:0-no-OK"; fi
    return
  fi
  if [[ "$rc" -ge 128 ]]; then echo "signal:$rc"; return; fi
  echo "other:$rc"
}

# Confirm the top of the range works before bisecting downward, so a
# broken compiler reports as broken rather than as needing lots of stack.
top=$((ceiling_kib * 4))
r="$(run_at "$top")"
if [[ "$r" == "unsettable" ]]; then
  echo 'SKIP: this shell cannot set ulimit -s (nothing to measure)'
  exit 0
fi
if [[ "$r" != "ok" ]]; then
  echo "FAIL: check $subject does not succeed even with ${top} KiB of stack: $r" >&2
  cat "$work/err" >&2
  exit 1
fi

# Bisect the smallest multiple of 8 KiB that still succeeds.
lo=8
hi=$top
while (( hi - lo > 8 )); do
  mid=$(( ((lo + hi) / 2 / 8) * 8 ))
  if [[ "$(run_at "$mid")" == "ok" ]]; then hi=$mid; else lo=$mid; fi
done
need=$hi

echo "check $subject needs ${need} KiB of stack (ceiling ${ceiling_kib} KiB)"

if (( need > ceiling_kib )); then
  echo "FAIL: that is over the ceiling. Something now recurses per program" >&2
  echo "      element - see the frames-per-entry note at the top of this file," >&2
  echo '      and prefer a while loop over a let-bound tail call.' >&2
  exit 1
fi

# The other half: at half the requirement it must die by SIGNAL. Without
# this the bisection above could report anything and still pass.
half=$(( need / 2 ))
(( half < 8 )) && half=8
r="$(run_at "$half")"
case "$r" in
  signal:*) echo "and dies by ${r#signal:} at ${half} KiB, as it must" ;;
  ok)
    echo "FAIL: it also succeeded at ${half} KiB, so the ${need} KiB figure is not" >&2
    echo "      a stack requirement and this gate measured nothing" >&2
    exit 1 ;;
  *)
    echo "FAIL: at ${half} KiB it answered '$r' rather than dying by a signal, so" >&2
    echo "      the failure above is not the stack running out" >&2
    exit 1 ;;
esac

echo "check-stack-depth: gate passed"
