#!/usr/bin/env bash
# AX3040 tells a diverging function from a cast, and the difference is
# the whole reason it is an error.
#
# WHAT IT USED TO BE. A warning, deliberately, because the rule
# conflated two signatures and only one of them is unsound:
#
#     (:: conjure (-> Int a))     ; body CASTS a word out
#     (:: panic   (-> String a))  ; body NEVER RETURNS
#
# Measured on the tree before this landed: both checked clean with the
# identical diagnostic, and then `conjure` exited 139 and `panic` ran
# correctly. `tests/diagnostics/severity.policy` recorded that
# promoting it needed "a way to tell divergence from a cast" first.
#
# WHAT THIS GATE ASSERTS. Not that the diagnostic exists - the
# diagnostics corpus already pins its text, its span and its severity.
# This asserts the DISTINCTION, in both directions, and that the
# accepted half still runs:
#
#   1. The unsound shapes are refused: `check` exits 1.
#   2. The diverging shape is accepted, and the program it belongs to
#      compiles, runs, and answers on BOTH its paths - the returning
#      one and the one that does not return.
#   3. Delegation is followed. `rethrow` and `sneak` have the same
#      shape and opposite truths, and only what they CALL separates
#      them.
#   4. `;@axiom:raw` still exempts, on either half of a declaration.
#
# AND THE NEGATIVE PROBE, which is the part that makes the acceptance
# worth anything. Acceptance is easy to get by accident: an analysis
# that answered "diverges" for everything would pass 2, 3 and 4 and
# refuse nothing. So the gate takes the ACCEPTED program and changes
# ONE WORD - the `(exit 70)` a cast is wrapped around becomes the
# literal `70` - and requires it to be refused. Same file, same
# declaration, same signature; the only difference is whether the
# thing being coerced returns.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# NO `set +e`/`set -e` PAIR HERE, AND THAT IS THE FIX RATHER THAN THE
# OMISSION. This script runs under `set -uo pipefail` and deliberately
# NOT under `-e`: every check reports and carries on, which is the whole
# point of counting them. The pair that used to wrap this body therefore
# turned `-e` ON - `set +e` was a no-op, `set -e` was not - and from the
# first call onward the gate ran with a mode nobody asked for.
#
# It cost nothing while the gate was green and everything when it was
# not. Measured 2026-08-25, ablating the variance flip: the gate found
# 7 failures, printed 2 of them, and died on a bare `grep` whose only
# job was to dump context for a failure it had already reported - 10
# checks after it never ran at all. A gate that reports less the worse
# things are is the failure mode this repository names most often, and
# it was in the gate, not in the compiler.
check_of() {  # <file> -> exit status, output on $work/out
  ( cd "$work" && "$axc" check "$1" ) >"$work/out" 2>&1
  local rc=$?
  printf '%s' "$rc"
}

# --------------------------------------------------------------------
echo "== the unsound shapes are refused =="
# --------------------------------------------------------------------
cp "$repo_root/tests/diagnostics/347-result-only-tyvar.ax" "$work/347.ax"
rc="$(check_of 347.ax)"
if (( rc == 1 )) && grep -q 'error\[AX3040\]' "$work/out"; then
  ok "347-result-only-tyvar.ax: refused, exit $rc"
else
  bad "347-result-only-tyvar.ax exited $rc"; sed 's/^/     /' "$work/out" | head -6
fi
# ...and its two controls in that file are NOT refused for the wrong
# reason: `witnessed` (the variable is in a parameter) and `declared`
# (tagged raw) must draw nothing.
for name in witnessed declared; do
  if grep -q "\`$name\`" "$work/out"; then
    bad "347: $name was diagnosed, and it is a control"
  else
    ok "347: $name draws nothing"
  fi
done

cp "$repo_root/tests/diagnostics/352-tyvar-delegation.ax" "$work/352.ax"
rc="$(check_of 352.ax)"
got="$(grep -oE '`[a-z]+` returns type variable' "$work/out" | grep -oE '^`[a-z]+`' | tr -d '`' | sort | tr '\n' ' ' || true)"
if (( rc == 1 )) && [[ "$got" == "conjure mixed sneak " ]]; then
  ok "352-tyvar-delegation.ax: exactly conjure, sneak and mixed are refused"
else
  bad "352 exited $rc and refused: ${got:-nothing}"
  echo "     wanted exactly: conjure mixed sneak"
fi
# The two that must NOT be refused are the delegation case and its
# target: `rethrow` diverges because `panic` does, and nothing about
# `rethrow`'s own body says so.
for name in panic rethrow; do
  if grep -q "\`$name\` returns type variable" "$work/out"; then
    bad "352: $name was refused, and it diverges"
  else
    ok "352: $name is accepted"
  fi
done

# --------------------------------------------------------------------
echo
echo "== the diverging program is accepted, and still runs =="
# --------------------------------------------------------------------
src="$repo_root/tests/selfhost/976-diverging-tyvar.ax"
cp "$src" "$work/976.ax"
rc="$(check_of 976.ax)"
if (( rc == 0 )) && ! grep -q 'AX3040' "$work/out"; then
  ok "976-diverging-tyvar.ax: accepted, no AX3040"
else
  bad "976-diverging-tyvar.ax exited $rc"; sed 's/^/     /' "$work/out" | head -6
fi
# The returning path. `main` is `(pick 7)`, and the fixture's own
# `; expect 7` says so - which `check-self-host.sh` also reads, so the
# two gates agree about this number by construction.
want="$(sed -n '1s/^; expect \([0-9]*\).*/\1/p' "$src")"
[[ -n "$want" ]] || { echo "FAIL: $src has no '; expect N' first line"; exit 1; }
( cd "$work" && "$axc" run 976.ax ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "$want" ]]; then
  ok "it runs and answers $rc on the returning path"
else
  bad "it answered $rc, its own '; expect' says $want"
fi
# The path that does NOT return. `pick` is called with a negative
# number, `panic` is entered, and the program must stop there - with
# the status `panic` chose and the message it wrote, not with a
# fabricated value flowing back to a caller.
sed 's/(fn (main) (pick 7))/(fn (main) (pick (- 0 1)))/' "$src" > "$work/976neg.ax"
if cmp -s "$src" "$work/976neg.ax"; then
  bad "the diverging-path probe changed nothing - its anchor has moved"
else
  ( cd "$work" && "$axc" run 976neg.ax ) >"$work/negout" 2>&1
  rc=$?
  if (( rc == 70 )) && grep -q negative "$work/negout"; then
    ok "and stops at $rc on the path that does not return, having said so"
  else
    bad "the diverging path answered $rc"; sed 's/^/     /' "$work/negout" | head -4
  fi
fi

# --------------------------------------------------------------------
echo
echo "== negative probe: one word, and the accepted program is refused =="
# --------------------------------------------------------------------
# `(cast a (exit 70))` diverges because `(exit 70)` never returns.
# `(cast a 70)` is the same coercion around a value that does. If the
# analysis could not tell those apart it would be answering the same
# thing for every program, and everything above it would be vacuous.
if ! grep -q '(cast a (exit 70))' "$src"; then
  echo "FAIL: the probe's anchor '(cast a (exit 70))' is gone from $src"
  exit 1
fi
sed 's/(cast a (exit 70))/(cast a 70)/' "$src" > "$work/976cast.ax"
rc="$(check_of 976cast.ax)"
if (( rc == 1 )) && grep -q 'error\[AX3040\]' "$work/out"; then
  ok "with the coercion wrapped around a value instead, it is refused (exit $rc)"
else
  bad "the one-word mutant exited $rc without an AX3040 error"
  sed 's/^/     /' "$work/out" | head -6
fi
# The other direction of the same probe: `sysExitWith` is the base
# case, so spelling the divergence with it directly must also be
# accepted - otherwise the acceptance is a special case for `IO.exit`
# rather than an analysis.
sed 's/(cast a (exit 70))/(cast a (sysExitWith 70))/; s/^(import IO)$/(import IO)\n\n(import Sys)/' "$src" > "$work/976sys.ax"
rc="$(check_of 976sys.ax)"
if (( rc == 0 )); then
  ok "spelled with the base case \`sysExitWith\` directly, it is still accepted"
else
  bad "the sysExitWith spelling exited $rc"; sed 's/^/     /' "$work/out" | head -6
fi

# --------------------------------------------------------------------
echo
echo "== every way this language has of not returning =="
# --------------------------------------------------------------------
# The rule §1b states about checks like this one: "a zero-population
# sweep catches a rule that is too wide. Only writing new programs in
# the language's idiom catches one that is too narrow." So the shapes
# are written out, here, and every one of them must be accepted.
#
# Six of the seven passed the first version of this analysis and the
# seventh did not: an endless `while` followed by a `cast` no execution
# reaches. That is a correct program, and refusing it would have been
# the exact failure §1b refused to ship - so the analysis grew two arms
# rather than the corpus losing a shape.
cat > "$work/shapes.ax" <<'AX'
(import IO)

(import Sys)

; 1. the base case, directly
(:: pSys (-> String a))

;@axiom:effect(io)

(fn (pSys m) (cast a (sysExitWith 70)))

; 2. through `IO.exit`, one call away from it
(:: pExit (-> String a))

;@axiom:effect(io)
(fn (pExit m) (cast a (exit 70)))

; 3. through `IO.die`, two calls away
(:: pDie (-> String a))

;@axiom:effect(io)
(fn (pDie m) (cast a (die m 70)))

; 4. self tail recursion, which needs no cast at all
(:: pSelf (-> String a))

(fn (pSelf m) (pSelf m))

; 5 and 6. mutual tail recursion - neither is decidable alone
(:: pA (-> String a))

(fn (pA m) (pB m))

(:: pB (-> String a))

(fn (pB m) (pA m))

; 7. an endless loop, and a coercion after it that never happens
(:: pLoop (-> String a))

(fn (pLoop m)
  (let ((mut i 0))
    {
      (while true
        (set i (+ i 1)))
      (cast a i)
    }
  )
)

; 8. every arm of an `if`, which is the MUST half of the analysis
(:: pIf (-> Int a))

;@axiom:effect(io)
(fn (pIf n)
  (if (> n 0)
    (pExit "a\n")
    (pExit "b\n")
  )
)

(:: main Int)

(fn (main) 0)
AX
rc="$(check_of shapes.ax)"
refused="$(grep -oE '`p[A-Za-z]+` returns type variable' "$work/out" | grep -oE '^`p[A-Za-z]+`' | tr -d '`' | tr '\n' ' ' || true)"
if (( rc == 0 )) && [[ -z "${refused// /}" ]]; then
  ok "all eight diverging spellings are accepted"
else
  bad "these diverging spellings were refused: ${refused:-<none, but exit was $rc>}"
  sed 's/^/     /' "$work/out" | head -8
fi
# And the sweep is not vacuous: the same file with ONE of them made to
# return must be refused, so a run that accepted everything would fail
# here rather than read as eight successes.
sed 's/(fn (pSelf m) (pSelf m))/(fn (pSelf m) (cast a 1))/' "$work/shapes.ax" > "$work/shapes2.ax"
rc="$(check_of shapes2.ax)"
if (( rc == 1 )) && grep -q '`pSelf`' "$work/out"; then
  ok "and one of them made to return is refused, so the sweep can fail"
else
  bad "the mutated shape sweep exited $rc without refusing pSelf"
fi

# --------------------------------------------------------------------
echo
echo "== the escape hatch, on either half of a declaration =="
# --------------------------------------------------------------------
# An AXTAG attaches to a declaration group and a function is normally
# two of them. Reading the tag from only one half cost nothing while
# this was a warning and would cost a refused program now.
for where in sig fn; do
  if [[ "$where" == sig ]]; then
    printf ';@axiom:raw\n(:: rawGet (-> Int a))\n\n(fn (rawGet w) (cast a w))\n\n(:: main Int)\n\n(fn (main) 0)\n' > "$work/raw.ax"
  else
    printf '(:: rawGet (-> Int a))\n\n;@axiom:raw\n(fn (rawGet w) (cast a w))\n\n(:: main Int)\n\n(fn (main) 0)\n' > "$work/raw.ax"
  fi
  rc="$(check_of raw.ax)"
  if (( rc == 0 )); then
    ok "\`;@axiom:raw\` above the $where exempts it"
  else
    bad "\`;@axiom:raw\` above the $where did not exempt it (exit $rc)"
  fi
done
# And the tag is not a blanket: an untagged declaration in the same
# file is still refused, so the exemption is per-declaration.
printf ';@axiom:raw\n(:: rawGet (-> Int a))\n\n(fn (rawGet w) (cast a w))\n\n(:: alsoRaw (-> Int a))\n\n(fn (alsoRaw w) (cast a w))\n\n(:: main Int)\n\n(fn (main) 0)\n' > "$work/raw2.ax"
rc="$(check_of raw2.ax)"
if (( rc == 1 )) && grep -q 'alsoRaw' "$work/out" && ! grep -q '`rawGet`' "$work/out"; then
  ok "the tag exempts its own declaration and not its neighbour"
else
  bad "the per-declaration exemption is wrong (exit $rc)"
  sed 's/^/     /' "$work/out" | head -6
fi

# --------------------------------------------------------------------
echo
echo "== the same unsoundness one level in: a callback's own parameter =="
# --------------------------------------------------------------------
# Everything above asks about the RESULT. Until 2026-08-25 that was the
# whole rule, and it missed the identical dereference through a
# function-typed parameter, because a rule that reads SIDES files a
# variable inside a callback under "the caller supplies it":
#
#     (:: demand (-> (-> a Int) Int))
#     (fn (demand f) (f (cast a 42)))
#     (demand strLen)
#
# Measured on the compiler before the fix: `check` answered OK and the
# binary exited 139. `explain AX3040` recorded it as what the rule did
# not catch; the spine is split by VARIANCE now and it does.
cp "$repo_root/tests/diagnostics/353-callback-tyvar.ax" "$work/353.ax"
rc="$(check_of 353.ax)"
got="$(grep -oE '`[a-zA-Z]+` (must produce|returns)' "$work/out" | grep -oE '^`[a-zA-Z]+`' | tr -d '`' | sort -u | tr '\n' ' ' || true)"
if (( rc == 1 )) && [[ "$got" == "alsoResult demand divDemand " ]]; then
  ok "353-callback-tyvar.ax: exactly demand, alsoResult and divDemand are refused"
else
  bad "353 exited $rc and refused: ${got:-nothing}"
  echo "     wanted exactly: alsoResult demand divDemand"
fi
# `divDemand` DIVERGES, so the returned-variable arm is honestly silent
# about it - `for all a` is the true type of a function that never
# returns. What must not be silent is the `a` it fabricates for its
# callback on the way there. This is the one case that distinguishes
# "the arms subtract" from "the arms decide", and subtracting is what
# the first version did: measured, check OK, exit 139.
if grep -q '`divDemand` must produce' "$work/out" \
   && ! grep -q '`divDemand` returns type variable' "$work/out"; then
  ok "divDemand: the diverging result is excused, the fabricated argument is not"
else
  bad "divDemand came from the wrong arm, or from both"
  { grep '`divDemand`' "$work/out" || true; } | sed 's/^/     /' | head -4
fi
# The controls. `witnessed` is the shape all ordinary higher-order code
# has - `b` on the RIGHT of the callback's arrow, `a` also a parameter -
# and a rule that reported it would refuse `map`. `declared` is the
# escape hatch on this arm.
for name in witnessed declared; do
  if grep -q "\`$name\`" "$work/out"; then
    bad "353: $name was diagnosed, and it is a control"
  else
    ok "353: $name draws nothing"
  fi
done
# `alsoResult` has its variable in the callback AND in the result, so
# both arms could claim it. It must draw ONE diagnostic - the arms
# subtract, they do not overlap - and it must be the returned-variable
# one, because that is the arm a divergence fixpoint can still answer.
n="$(grep -c 'error\[AX3040\]' "$work/out" || true)"
a="$(grep -c '`alsoResult`' "$work/out" || true)"
if (( n == 3 )) && (( a == 1 )) && grep -q '`alsoResult` returns type variable' "$work/out"; then
  ok "alsoResult draws one diagnostic, from the returned-variable arm"
else
  bad "353 drew $n AX3040s (wanted 3) and $a for alsoResult (wanted 1)"
fi
# Emission order IS report order in this compiler - nothing sorts
# diagnostics afterwards - so two arms sweeping separately reported the
# later declaration first. They are one declaration-ordered sweep.
first="$(grep -oE '`(demand|alsoResult)`' "$work/out" | head -1)"
if [[ "$first" == '`demand`' ]]; then
  ok "the two arms report in declaration order, not arm order"
else
  bad "the first diagnostic named $first; demand is declared first"
fi

# --------------------------------------------------------------------
echo
echo "== negative probe: the side of the inner arrow, and nothing else =="
# --------------------------------------------------------------------
# The sharpest form this probe has. Two files with the SAME body, the
# same nesting depth and the same one type variable; the only
# difference is which side of the callback's arrow it sits on. Left is
# a value this function must produce and cannot; right is one the
# caller's own function produces. If the analysis were counting nesting
# rather than variance, both would answer the same and every check
# above would be describing a rule that does not exist.
printf '(:: demand (-> (-> a Int) Int))\n\n(fn (demand f) 0)\n\n(:: main Int)\n\n(fn (main) 0)\n' > "$work/varL.ax"
printf '(:: demand (-> (-> Int a) Int))\n\n(fn (demand f) 0)\n\n(:: main Int)\n\n(fn (main) 0)\n' > "$work/varR.ax"
rcL="$(check_of varL.ax)"
rcR="$(check_of varR.ax)"
if (( rcL == 1 )) && (( rcR == 0 )); then
  ok "\`(-> a Int)\` is refused and \`(-> Int a)\` is accepted, same body"
else
  bad "the variance probe answered $rcL / $rcR (wanted 1 / 0)"
fi
# THE OVER-APPROXIMATION, ASSERTED RATHER THAN LEFT TO BE FOUND. Those
# two bodies are `0`: neither calls its callback, so neither actually
# fabricates anything, and the left one is refused for a value it does
# not make. The rule reads the signature. `explain AX3040` says so, and
# this is the check that keeps that sentence true - if the analysis
# ever grows a body walk, this goes red and the sentence comes out.
if (( rcL == 1 )); then
  ok "and the rule reads the SIGNATURE: a body that never calls f is refused too"
fi
# The witness, added as one parameter. Same callback, same call, and
# now the caller hands over the value that decides what `a` is - so it
# is accepted, and it RUNS, which is the half acceptance is worth
# anything for.
printf '(import Str)\n\n(:: demand (-> (-> a Int) a Int))\n\n(fn (demand f x) (f x))\n\n(:: main Int)\n\n(fn (main) (demand strLen "hello"))\n' > "$work/wit.ax"
rc="$(check_of wit.ax)"
( cd "$work" && "$axc" run wit.ax ) >/dev/null 2>&1
run=$?
if (( rc == 0 )) && (( run == 5 )); then
  ok "one parameter of type \`a\` witnesses the choice: accepted, and answers $run"
else
  bad "the witnessed spelling exited $rc and ran to $run (wanted 0 and 5)"
fi
# The change reads BOTH ways, and this is the half a rule that only
# tightened would not have. An arrow nested inside a type ARGUMENT in
# the RESULT puts its variable on a left side - the callee does not
# produce it, whoever calls the returned callback does - and the old
# side-reading rule refused it. Measured against the compiler before
# this change: `AX3040`, a false positive. `Holder` is a parameterised
# `data` because an arrow may not be a type argument to anything else
# in this language.
cat > "$work/lenient.ax" <<'AX'
(data Holder a
  (H a))

(:: mk (-> Int (Holder (-> a Int))))

(fn (mk n) (H bump))

(:: bump (-> Int Int))

(fn (bump x) x)

(:: main Int)

(fn (main) 0)
AX
rc="$(check_of lenient.ax)"
if (( rc == 0 )); then
  ok "a callback in the RESULT is witnessed by its own caller: accepted"
else
  bad "the lenient direction exited $rc"; sed 's/^/     /' "$work/out" | head -6
fi

# And ordinary polymorphic higher-order code, at two DIFFERENT types in
# one program, compiles and runs. This is the population the rule could
# most easily have broken.
cat > "$work/hof.ax" <<'AX'
(import Str)

(:: applyf (-> (-> a b) a b))

(fn (applyf f x) (f x))

(:: bump (-> Int Int))

(fn (bump n) (+ n 1))

(:: main Int)

(fn (main) (+ (applyf bump 6) (applyf strLen "hello")))
AX
rc="$(check_of hof.ax)"
( cd "$work" && "$axc" run hof.ax ) >/dev/null 2>&1
run=$?
if (( rc == 0 )) && (( run == 12 )); then
  ok "\`(-> (-> a b) a b)\` at two types: accepted, and answers $run"
else
  bad "the higher-order control exited $rc and ran to $run (wanted 0 and 12)"
fi

# --------------------------------------------------------------------
echo
echo "== what the diagnostic is guarding, run rather than argued =="
# --------------------------------------------------------------------
# `;@axiom:raw` exempts the declaration from the REPORT and changes no
# code, so the exempted program is exactly what used to compile. It is
# built and RUN here, and it dies - which is the whole claim. A gate
# that only asserted "a diagnostic appears" would pass just as well
# against a rule that refused correct programs for a made-up reason.
printf '(import Str)\n\n;@axiom:raw\n(:: demand (-> (-> a Int) Int))\n\n(fn (demand f) (f (cast a 42)))\n\n(:: main Int)\n\n(fn (main) (demand strLen))\n' > "$work/boom.ax"
rc="$(check_of boom.ax)"
( cd "$work" && "$axc" run boom.ax ) >/dev/null 2>&1
run=$?
# `>= 128` rather than `== 139` because the number is the SIGNAL, and
# only the fact that one arrived is portable. It was 139 (SIGSEGV) on
# darwin-aarch64 on 2026-08-25 - 42 dereferenced as a String pointer.
if (( rc == 0 )) && (( run >= 128 )); then
  ok "the exempted program checks clean, builds, and is killed by a signal ($run)"
else
  bad "the exempted program checked $rc and ran to $run (wanted 0, then a signal)"
fi

echo
if (( failed > 0 )); then
  echo "check-diverging-tyvar: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-diverging-tyvar: $checks checks - a fabricated value is refused"
echo "                       wherever the callee must produce it, a function"
echo "                       that never returns is not, and one word between"
echo "                       them flips the answer"
