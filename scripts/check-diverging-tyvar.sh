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

check_of() {  # <file> -> exit status, output on $work/out
  set +e
  ( cd "$work" && "$axc" check "$1" ) >"$work/out" 2>&1
  local rc=$?
  set -e
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
set +e
( cd "$work" && "$axc" run 976.ax ) >/dev/null 2>&1
rc=$?
set -e
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
  set +e
  ( cd "$work" && "$axc" run 976neg.ax ) >"$work/negout" 2>&1
  rc=$?
  set -e
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

(fn (pSys m) (cast a (sysExitWith 70)))

; 2. through `IO.exit`, one call away from it
(:: pExit (-> String a))

(fn (pExit m) (cast a (exit 70)))

; 3. through `IO.die`, two calls away
(:: pDie (-> String a))

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

echo
if (( failed > 0 )); then
  echo "check-diverging-tyvar: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-diverging-tyvar: $checks checks - a fabricated value is refused, a"
echo "                       function that never returns is not, and one word"
echo "                       between them flips the answer"
