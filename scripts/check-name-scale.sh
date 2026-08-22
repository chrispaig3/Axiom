#!/usr/bin/env bash
#
# A module's PRIVATE declarations must cost no more to resolve than its
# public ones.
#
# WHY THIS EXISTS, and it is the whole story. `8942644` indexed
# `findFnEnt`, which had been three linear scans of a ~1,600-entry table
# per name reference: `check self_host/main.ax` 0.89s -> 0.17s. Its own
# note (docs/self-hosting.md 32.4) recorded what was left linear on
# purpose - `findFnEntVisibleExact`/`Suffix`, "which only run when a
# program declares something private", and then the sentence this gate
# exists because of:
#
#     the count of those in this repository is zero
#
# It was zero for FOUR HOURS. `3b6d485`, the same afternoon, made the
# standard library private by default - 151 names, 288 declarations - so
# every program in the repository, and every program that imports it,
# started taking the un-indexed branch. The index was dead for eight
# days and the number that would have shown it was never taken, because
# 32.4 also decided - explicitly, with reasons - that this change would
# ship with no speed gate of its own. Every correctness gate stayed
# green throughout, as they should have: the answers were right, they
# were just arrived at by scanning.
#
# So the lesson is not "add a benchmark". It is that a fast path guarded
# by a claim about the CORPUS ("nothing here is private") needs a gate
# that re-asks the claim, because the corpus is what changes.
#
# WHAT IT ASSERTS. Two generated modules of identical size and shape,
# differing only in whether the helper half is `pub`, must check in
# about the same time - the private one no more than BOUND times the
# public one. Resolving a private name goes through the visibility
# filter and a public one does not; if the filter is indexed the two are
# the same work, and if it is a table scan the private side degrades
# with the program.
#
# WHY A RATIO BETWEEN TWO PROGRAMS, rather than the obvious shapes:
#
#   * NOT a wall-clock bound. A second on a shared runner is a flaky
#     test - the same call `bench-datastructures.sh` and
#     `bench-compile.sh` both make.
#
#   * NOT a doubling ratio, and this was MEASURED rather than assumed.
#     Per-doubling exponents on this corpus are ~4x on BOTH sides of the
#     fix (indexed 3.7/3.9, un-indexed 4.2/4.7), because `mangleHasIn`
#     (self_host/namespace.ax) is a linear scan of `bares` and is still
#     quadratic in the declaration count - 55.7% of a check at N=8000.
#     A doubling gate would therefore have passed on the broken code.
#     That defect is real, is recorded in docs/self-hosting.md, and is
#     not this gate's subject; a ratio between two programs of the SAME
#     size charges it to both sides, where it cancels.
#
# NEGATIVE CHECK, which is this repository's rule for a new test. Built
# from HEAD~ and from HEAD by the same parent compiler, at N=4000:
#
#     un-indexed   private 1.26s   public 0.60s   ratio 2.10   FAILS
#     indexed      private 0.37s   public 0.60s   ratio 0.62   passes
#
# The indexed ratio is BELOW one, which is not a rounding artefact: a
# private declaration takes `mangleRecordSelf` and a public one takes
# `mangleRecord`, which does one more `mangleHasIn` scan. That is why
# the bound is 1.20 rather than something tighter - it is placed above
# the un-indexed side's failure and well above the indexed side's
# reading, not shaved to the current number, which is how a floor
# expires (see the doubling-ratio note above for the other way).
#
# AND IT CHECKS THE WORK WAS DONE. Both runs must print `OK` and exit 0.
# A compiler that dies early is a very fast compiler and would pass any
# ratio; this repository has been fooled by exactly that three times.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

N="${N:-4000}"
BOUND="${BOUND:-1.20}"
REPS="${REPS:-3}"
# Below this the two numbers being divided are timer resolution and the
# ratio reports whatever it likes. Raise N rather than lowering this.
FLOOR="0.10"

ln -s "$repo_root/stdlib" "$work/stdlib"

# Two modules, same size, same call graph. In `Priv` the helper half is
# module-private and every public wrapper calls one; in `Publ` the same
# helpers are exported. The wrappers are identical in both.
gen() { # gen <file> <helper-vis>
  local out="$1" vis="$2" i
  : > "$out"
  for (( i = 0; i < N; i++ )); do
    printf '%s:: h%d (-> Int Int))\n%sfn (h%d n) (+ n %d))\n' "$vis" "$i" "$vis" "$i" "$i" >> "$out"
  done
  for (( i = 0; i < N; i++ )); do
    printf '(pub :: p%d (-> Int Int))\n(pub fn (p%d n) (h%d n))\n' "$i" "$i" "$i" >> "$out"
  done
}
gen "$work/Priv.ax" '('
gen "$work/Publ.ax" '(pub '
printf '(import Priv)\n(:: main Int)\n(fn (main) (p0 42))\n' > "$work/mpriv.ax"
printf '(import Publ)\n(:: main Int)\n(fn (main) (p0 42))\n' > "$work/mpubl.ax"

# Best of REPS. The distribution is one-sided - interference only ever
# makes a run slower - so the minimum is the closest estimate of the
# cost itself, which is `bench-datastructures.sh`'s methodology.
best_of() { # best_of <entry>
  local entry="$1" i best="" t out rc
  for (( i = 0; i < REPS; i++ )); do
    local s e
    s=$(python3 -c 'import time;print(time.monotonic())')
    out="$( cd "$work" && "$axiom" check "$entry" 2>&1 )"; rc=$?
    e=$(python3 -c 'import time;print(time.monotonic())')
    if (( rc != 0 )); then
      echo "FAIL: \`check $entry\` exited $rc - this gate measured a failure, not a compile" >&2
      echo "$out" | tail -5 >&2
      exit 1
    fi
    if [[ "$out" != *OK* ]]; then
      echo "FAIL: \`check $entry\` exited 0 without printing OK, so it did no work" >&2
      exit 1
    fi
    t=$(python3 -c "print($e - $s)")
    if [[ -z "$best" ]] || (( $(python3 -c "print(1 if $t < $best else 0)") )); then best="$t"; fi
  done
  printf '%s' "$best"
}

tp="$(best_of mpriv.ax)" || exit 1
tq="$(best_of mpubl.ax)" || exit 1

read -r ratio under_floor <<<"$(python3 -c "
p, q = $tp, $tq
print('%.2f' % (p / q), 1 if (p < $FLOOR or q < $FLOOR) else 0)")"

printf 'check-name-scale: N=%s  private %.2fs  public %.2fs  ratio %s (bound %s)\n' \
  "$N" "$tp" "$tq" "$ratio" "$BOUND"

if (( under_floor )); then
  echo "FAIL: one of those is under ${FLOOR}s, so the ratio is between two" >&2
  echo "      timer-resolution numbers and asserts nothing. Re-run with a" >&2
  echo "      larger N=." >&2
  exit 1
fi

if (( $(python3 -c "print(1 if $ratio >= $BOUND else 0)") )); then
  echo "FAIL: resolving a module's PRIVATE names now costs ${ratio}x what its" >&2
  echo "      public ones cost. Some lookup on the visibility path has gone" >&2
  echo "      back to scanning the function table - see \`findFnEnt\` and the" >&2
  echo "      index sections in self_host/typecheck.ax, and the note at the" >&2
  echo "      top of this file for how that happened the first time." >&2
  exit 1
fi

echo "check-name-scale: gate passed"
