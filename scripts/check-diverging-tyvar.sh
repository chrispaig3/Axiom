#!/usr/bin/env bash
# AX3040 tells a diverging function from a cast, and that difference is
# what lets it be an error:
#
#     (:: conjure (-> Int a))     ; body casts a word out: unsound
#     (:: panic   (-> String a))  ; body never returns: sound
#
# The diagnostics corpus pins the text, span and severity. This gate
# checks the distinction in both directions, and that the accepted half
# still runs:
#
#   1. The unsound shapes are refused: `check` exits 1.
#   2. The diverging shape is accepted, and its program compiles, runs
#      and answers on both paths: the one that returns and the one that
#      does not.
#   3. Delegation is followed. `rethrow` and `sneak` have the same shape
#      and opposite answers; only what they call separates them.
#   4. `;@axiom:raw` still exempts, on either half of a declaration.
#
# Acceptance is easy to get by accident: an analysis that answered
# "diverges" for everything would pass 2, 3 and 4. So the negative probe
# changes one word of the accepted program, turning the `(exit 70)` a
# cast wraps into the literal `70`, and requires a refusal.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# The script runs under `set -uo pipefail` without `-e`, so every check
# reports and the run carries on. Never wrap a body in `set +e`/`set -e`:
# the `set -e` turns `-e` on, and the first context-dumping `grep` that
# finds nothing then kills the gate before it reports the rest.
check_of() {  # <file> -> exit status, output on $work/out
  ( cd "$work" && "$axc" check "$1" ) >"$work/out" 2>&1
  local rc=$?
  printf '%s' "$rc"
}

# --------------------------------------------------------------------
echo "== the unsound shapes are refused =="
# --------------------------------------------------------------------
cp "$repo_root/tests/diagnostics/1118-no-loop-early-exit.ax" "$work/early-exit.ax"
rc="$(check_of early-exit.ax)"
if (( rc == 1 )) && [[ "$(grep -c 'error\[AX3001\]' "$work/out" || true)" == 4 ]] \
   && grep -q 'undefined variable `break`' "$work/out" \
   && grep -q 'undefined variable `continue`' "$work/out"; then
  ok "break and continue are undefined ordinary names in while and for"
else
  bad "the no-early-exit grammar pin changed (exit $rc)"
  sed 's/^/     /' "$work/out" | head -8
fi
if grep -q 'AX3073\|AX3040' "$work/out"; then
  bad "a constant-true loop's unreachable cast was charged"
else
  ok "constant-true loops still waive unreachable forging casts"
fi

cp "$repo_root/tests/diagnostics/347-result-only-tyvar.ax" "$work/347.ax"
rc="$(check_of 347.ax)"
if (( rc == 1 )) && grep -q 'error\[AX3040\]' "$work/out"; then
  ok "347-result-only-tyvar.ax: refused, exit $rc"
else
  bad "347-result-only-tyvar.ax exited $rc"; sed 's/^/     /' "$work/out" | head -6
fi
# Its two controls must draw nothing: `witnessed` (the variable is in a
# parameter) and `declared` (tagged raw).
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
# The two that must not be refused are the delegation case and its
# target: `rethrow` diverges because `panic` does, though nothing in
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
# The returning path: `main` is `(pick 7)`. The expected status comes
# from the fixture's `; expect` line, which `check-self-host.sh` also
# reads, so the two gates cannot disagree about it.
want="$(sed -n '1s/^; expect \([0-9]*\).*/\1/p' "$src")"
[[ -n "$want" ]] || { echo "FAIL: $src has no '; expect N' first line"; exit 1; }
( cd "$work" && "$axc" run 976.ax ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "$want" ]]; then
  ok "it runs and answers $rc on the returning path"
else
  bad "it answered $rc, its own '; expect' says $want"
fi
# The path that does not return. `pick` gets a negative number and
# enters `panic`, and the program must stop there with the status and
# message `panic` chose, not with a fabricated value.
# `main` spans two lines, so the sed joins them before substituting.
# The `;}` keeps BSD sed happy where GNU accepts either.
sed '/(fn (main)$/{N;s/(pick 7)/(pick (- 0 1))/;}' "$src" > "$work/976neg.ax"
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
# `(cast a 70)` is the same coercion around a value that does. An
# analysis that could not tell them apart would answer the same for
# every program, and every check above would be vacuous.
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
# The other direction: `sysExitWith` is the base case, so a divergence
# spelled with it directly must also be accepted. Otherwise acceptance
# would be a special case for `IO.exit`, not an analysis.
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
# A zero-population sweep catches a rule that is too wide. Only new
# programs written in the language's idiom catch one that is too narrow.
# So every way of not returning is written out here, and each must be
# accepted. Shape 7, an endless `while` followed by a `cast` no
# execution reaches, is a correct program too. When a shape here is
# refused, fix the analysis; never drop the shape.
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
;@axiom:effect(unsafe)

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
# The sweep can fail: with one shape made to return, the same file must
# be refused, so a run that accepted everything cannot read as success.
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
# An AXTAG attaches to a declaration group, and a function is normally
# two groups: its signature and its `fn`. A tag on either half must
# exempt it, or a tagged program is refused.
for where in sig fn; do
  if [[ "$where" == sig ]]; then
    printf ';@axiom:raw\n(:: rawGet (-> Int a))\n;@axiom:effect(unsafe)\n(fn (rawGet w) (cast a w))\n\n(:: main Int)\n\n(fn (main) 0)\n' > "$work/raw.ax"
  else
    printf '(:: rawGet (-> Int a))\n\n;@axiom:raw\n;@axiom:effect(unsafe)\n(fn (rawGet w) (cast a w))\n\n(:: main Int)\n\n(fn (main) 0)\n' > "$work/raw.ax"
  fi
  rc="$(check_of raw.ax)"
  if (( rc == 0 )); then
    ok "\`;@axiom:raw\` above the $where exempts it"
  else
    bad "\`;@axiom:raw\` above the $where did not exempt it (exit $rc)"
  fi
done
# The tag is not a blanket: an untagged declaration in the same file is
# still refused, so the exemption is per declaration.
printf ';@axiom:raw\n(:: rawGet (-> Int a))\n;@axiom:effect(unsafe)\n(fn (rawGet w) (cast a w))\n\n(:: alsoRaw (-> Int a))\n;@axiom:effect(unsafe)\n(fn (alsoRaw w) (cast a w))\n\n(:: main Int)\n\n(fn (main) 0)\n' > "$work/raw2.ax"
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
# Everything above asks about the result. The same fabrication can
# happen through a function-typed parameter, where the callee must make
# the `a` it hands its callback:
#
#     (:: demand (-> (-> a Int) Int))
#     (fn (demand f) (f (cast a 42)))
#     (demand strLen)
#
# A rule that asks only whether the variable sits in a parameter files
# this under "the caller supplies it", and the binary exits 139. So the
# spine is split by variance.
cp "$repo_root/tests/diagnostics/353-callback-tyvar.ax" "$work/353.ax"
rc="$(check_of 353.ax)"
got="$(grep -oE '`[a-zA-Z]+` (must produce|returns)' "$work/out" | grep -oE '^`[a-zA-Z]+`' | tr -d '`' | sort -u | tr '\n' ' ' || true)"
if (( rc == 1 )) && [[ "$got" == "alsoResult demand divDemand " ]]; then
  ok "353-callback-tyvar.ax: exactly demand, alsoResult and divDemand are refused"
else
  bad "353 exited $rc and refused: ${got:-nothing}"
  echo "     wanted exactly: alsoResult demand divDemand"
fi
# `divDemand` diverges, so the returned-variable arm is rightly silent:
# `forall a` is the true type of a function that never returns. The `a`
# it fabricates for its callback on the way must still be refused.
# Divergence excuses the result only; letting it excuse the callback
# arm too accepts this program, and its binary exits 139.
if grep -q '`divDemand` must produce' "$work/out" \
   && ! grep -q '`divDemand` returns type variable' "$work/out"; then
  ok "divDemand: the diverging result is excused, the fabricated argument is not"
else
  bad "divDemand came from the wrong arm, or from both"
  { grep '`divDemand`' "$work/out" || true; } | sed 's/^/     /' | head -4
fi
# The controls. `witnessed` is the shape of ordinary higher-order code
# (`b` on the right of the callback's arrow, `a` also a parameter), and
# a rule that reported it would refuse `map`. `declared` is the escape
# hatch on this arm.
for name in witnessed declared; do
  if grep -q "\`$name\`" "$work/out"; then
    bad "353: $name was diagnosed, and it is a control"
  else
    ok "353: $name draws nothing"
  fi
done
# `alsoResult` has its variable in the callback and in the result, so
# both arms could claim it. It must draw one diagnostic, from the
# returned-variable arm, because that is the arm a divergence fixpoint
# can still answer.
n="$(grep -c 'error\[AX3040\]' "$work/out" || true)"
a="$(grep 'AX3040' "$work/out" | grep -c '`alsoResult`' || true)"
if (( n == 3 )) && (( a == 1 )) && grep -q '`alsoResult` returns type variable' "$work/out"; then
  ok "alsoResult draws one diagnostic, from the returned-variable arm"
else
  bad "353 drew $n AX3040s (wanted 3) and $a for alsoResult (wanted 1)"
fi
# Emission order is report order: nothing sorts diagnostics afterwards.
# The two arms are one declaration-ordered sweep, so `demand`, declared
# first, must be reported first.
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
# Two files with the same body, nesting depth and type variable; only
# the side of the callback's arrow differs. On the left it is a value
# this function must produce and cannot; on the right, one the caller's
# function produces. An analysis counting nesting instead of variance
# would answer both the same.
printf '(:: demand (-> (-> a Int) Int))\n\n(fn (demand f) 0)\n\n(:: main Int)\n\n(fn (main) 0)\n' > "$work/varL.ax"
printf '(:: demand (-> (-> Int a) Int))\n\n(fn (demand f) 0)\n\n(:: main Int)\n\n(fn (main) 0)\n' > "$work/varR.ax"
rcL="$(check_of varL.ax)"
rcR="$(check_of varR.ax)"
if (( rcL == 1 )) && (( rcR == 0 )); then
  ok "\`(-> a Int)\` is refused and \`(-> Int a)\` is accepted, same body"
else
  bad "the variance probe answered $rcL / $rcR (wanted 1 / 0)"
fi
# The known over-approximation. Both bodies are `0` and never call the
# callback, yet the left one is refused, because the rule reads the
# signature. `explain AX3040` says so. If the analysis grows a body walk,
# this check goes red and that sentence must change.
if (( rcL == 1 )); then
  ok "and the rule reads the SIGNATURE: a body that never calls f is refused too"
fi
# The witness: one more parameter, of type `a`. The caller now hands
# over the value that decides what `a` is, so it is accepted, and it
# must also run.
printf '(import Str)\n\n(:: demand (-> (-> a Int) a Int))\n\n(fn (demand f x) (f x))\n\n(:: main Int)\n\n(fn (main) (demand strLen "hello"))\n' > "$work/wit.ax"
rc="$(check_of wit.ax)"
( cd "$work" && "$axc" run wit.ax ) >/dev/null 2>&1
run=$?
if (( rc == 0 )) && (( run == 5 )); then
  ok "one parameter of type \`a\` witnesses the choice: accepted, and answers $run"
else
  bad "the witnessed spelling exited $rc and ran to $run (wanted 0 and 5)"
fi
# Variance also relaxes the rule. An arrow nested in a type argument of
# the result puts its variable on a left side: whoever calls the
# returned callback produces it, not the callee. A rule that reads only
# sides refuses this correct program. `Holder` is a parameterised `data`
# because an arrow can be a type argument to nothing else.
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

# Ordinary polymorphic higher-order code, at two different types in one
# program, compiles and runs. This is the population the rule could most
# easily break.
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
# `;@axiom:raw` exempts a declaration from the report and changes no
# code, so this program is what the rule guards against: it checks
# clean, builds, and dies. A gate that only asserted "a diagnostic
# appears" would pass just as well against a rule that refused correct
# programs.
printf '(import Str)\n\n;@axiom:raw\n(:: demand (-> (-> a Int) Int))\n;@axiom:effect(unsafe)\n(fn (demand f) (f (cast a 42)))\n\n(:: main Int)\n\n(fn (main) (demand strLen))\n' > "$work/boom.ax"
rc="$(check_of boom.ax)"
( cd "$work" && "$axc" run boom.ax ) >/dev/null 2>&1
run=$?
# `>= 128`, not `== 139`: only the arrival of a signal is portable, not
# its number. On darwin-aarch64 it is SIGSEGV (139), 42 dereferenced as
# a String pointer.
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
