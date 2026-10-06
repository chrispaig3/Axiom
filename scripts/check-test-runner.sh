#!/usr/bin/env bash
# Check `axiom test`: the runner, the assertions and the isolation
# between tests.
#
# A skipped test reads exactly like a passing one. The assertions here,
# most important first:
#
#   1. A failing test fails: every mutated assertion must go red.
#   2. Every test declared is reported, checked against a `grep` of the
#      fixture, a source outside the compiler (as `check-backtrace.sh`
#      checks frames against `nm`).
#   3. One failure ends one test, and the run carries on.
#   4. A file with no test fails, and a `test`-named function that takes
#      parameters is refused by name.
#   5. `;@axiom:expect` flips the verdict and nothing else: a tagged
#      test that fails is `xfail`, and one that passes is `FAIL`.
#   6. `assertFloatNear`'s tolerance is inclusive at the boundary and
#      still catches a real mismatch.
#
# The fixtures are copied into $work because `axiom test` writes its
# generated driver beside the file under test, where the file's imports
# resolve. Running in `tests/testrunner/` would write into the tree. The
# copy also lets the last check confirm the runs left exactly the files
# they started with.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

fixtures="$repo_root/tests/testrunner"
suite="$work/suite"
mkdir -p "$suite"
cp "$fixtures"/*.ax "$suite/"

failed=0
checks=0

# Run `axiom test` from inside $work, so the scratch executable it
# builds lands there too.
axiom_test() {
  ( cd "$work" && "$axc" test "$@" ) 2>&1
}

ok()   { echo "ok   $*"; checks=$((checks + 1)); }
bad()  { echo "FAIL $*"; failed=$((failed + 1)); }

# --------------------------------------------------------------------
echo "== a passing suite passes, and says which tests it ran =="
# --------------------------------------------------------------------
set +e
out="$(axiom_test suite/pass-tests.ax)"; rc=$?
set -e
if (( rc == 0 )); then ok "pass-tests.ax exits 0"; else bad "pass-tests.ax exits $rc, expected 0"; echo "$out" | sed 's/^/     /'; fi

# The second source: the tests a `grep` finds in the fixture's own
# bytes, in declaration order. A runner that reported four of five
# would pass a golden written from its own output and fail here.
declared="$(grep -oE '^\(fn \(test[A-Za-z0-9_]*\)' "$suite/pass-tests.ax" | sed 's/^(fn (//; s/)$//')"
reported="$(printf '%s\n' "$out" | sed -n 's/^ok   //p')"
if [[ "$declared" == "$reported" ]]; then
  ok "every test declared is a test reported ($(printf '%s' "$declared" | grep -c .) of them, in declaration order)"
else
  bad "the report and the source disagree about which tests exist"
  diff <(printf '%s\n' "$declared") <(printf '%s\n' "$reported") | sed 's/^/     /' || true
fi

if printf '%s\n' "$out" | grep -qx "5 test(s), 0 failed"; then
  ok "the summary line counts them"
else
  bad "no '5 test(s), 0 failed' summary"; echo "$out" | sed 's/^/     /'
fi

# --------------------------------------------------------------------
echo
echo "== the negative probe: a mutated assertion must go red =="
# --------------------------------------------------------------------
# Mutate every `assertEq` in the passing suite, one at a time, to an
# expected value that cannot be right. Each mutant must exit 1 and name
# the test it broke: exiting 1 for another reason would pass a weaker
# check.
mutants=0
while IFS=: read -r line _; do
  [[ -z "$line" ]] && continue
  mkdir -p "$work/mutant"
  cp "$suite/pass-tests.ax" "$work/mutant/pass-tests.ax"
  # `assertEq "label" WANT GOT` -> `assertEq "label" 987654321 GOT`
  sed -i.bak "${line}s/\(assertEq \"[^\"]*\" \)[0-9-]*/\1987654321/" "$work/mutant/pass-tests.ax"
  if cmp -s "$suite/pass-tests.ax" "$work/mutant/pass-tests.ax"; then
    bad "the mutation at line $line changed nothing - the probe is not probing"
    continue
  fi
  set +e
  mout="$( ( cd "$work" && "$axc" test mutant/pass-tests.ax ) 2>&1 )"; mrc=$?
  set -e
  if (( mrc == 1 )) && printf '%s\n' "$mout" | grep -q '^FAIL '; then
    mutants=$((mutants + 1))
  else
    bad "the mutant at line $line exited $mrc without a FAIL line"
    printf '%s\n' "$mout" | sed 's/^/     /'
  fi
  rm -rf "$work/mutant"
done < <(grep -n 'assertEq "' "$suite/pass-tests.ax" | grep -oE '^[0-9]+:')
if (( mutants > 0 )); then
  ok "$mutants mutated assertion(s) observed red"
else
  bad "no mutant was observed red - this gate cannot fail"
fi

# --------------------------------------------------------------------
echo
echo "== one failure ends one test, and the run carries on =="
# --------------------------------------------------------------------
# `mixed-tests.ax` fails in the three ways an Axiom program can stop
# without returning, then declares one more test that must still pass.
set +e
mixed="$(axiom_test suite/mixed-tests.ax)"; rc=$?
set -e
if (( rc == 1 )); then ok "mixed-tests.ax exits 1"; else bad "mixed-tests.ax exits $rc, expected 1"; fi

if diff -u "$fixtures/mixed-tests.out" <(printf '%s\n' "$mixed") > "$work/mixed.diff"; then
  ok "its report is the golden, byte for byte"
else
  bad "mixed-tests.ax report differs from tests/testrunner/mixed-tests.out"
  sed 's/^/     /' "$work/mixed.diff"
fi

# Restate the golden's claim so a re-blessed golden cannot lose it: the
# last test still ran.
if printf '%s\n' "$mixed" | grep -qx "ok   testTheLastOneStillRuns"; then
  ok "the test declared after all three failures still ran"
else
  bad "the test after the failures did not run - isolation is broken"
fi
# The line after the failed assertion must not have run.
if printf '%s\n' "$mixed" | grep -q "unreachable"; then
  bad "execution continued past a failed assertion"
else
  ok "nothing ran after the failed assertion inside its own test"
fi

# --------------------------------------------------------------------
echo
echo "== \`;@axiom:expect\` flips the verdict, and only the verdict =="
# --------------------------------------------------------------------
# `xfail-tests.ax`: a tagged test that fails is `xfail` and does not
# count against the run; a tagged test that passes is `FAIL` and does.
# One case tags the `::` signature instead of the `fn`, the half
# `testExpectFail` falls back to.
set +e
xf="$(axiom_test suite/xfail-tests.ax)"; rc=$?
set -e
if (( rc == 1 )); then ok "xfail-tests.ax exits 1"; else bad "xfail-tests.ax exits $rc, expected 1"; fi

if diff -u "$fixtures/xfail-tests.out" <(printf '%s\n' "$xf") > "$work/xfail.diff"; then
  ok "its report is the golden, byte for byte"
else
  bad "xfail-tests.ax report differs from tests/testrunner/xfail-tests.out"
  sed 's/^/     /' "$work/xfail.diff"
fi

# Restate the golden's claims so a re-blessed golden cannot lose them.
if printf '%s\n' "$xf" | grep -qx "xfail testXFailReportsTheFailureAsExpected - a failed assertion, or an unhandled effect (status 71), as expected"; then
  ok "a tagged test that fails is reported xfail, not FAIL"
else
  bad "an expect test that failed was not reported xfail"
fi
if printf '%s\n' "$xf" | grep -qx "xfail testXFailAlsoCatchesADivisionByZero - division by zero (status 72), as expected"; then
  ok "the flip is keyed on the status, not on the Assert effect specifically"
else
  bad "a non-assertion trap under expect was not reported xfail"
fi
if printf '%s\n' "$xf" | grep -qx "FAIL testXFailButItPassesAnyway - expected to fail, but passed"; then
  ok "a tagged test that unexpectedly PASSES is reported FAIL, not xfail"
else
  bad "an expect test that passed was not reported as a failure - the tag can silence a broken test"
fi
if printf '%s\n' "$xf" | grep -qx "xfail testXFailTaggedOnTheSignature - a failed assertion, or an unhandled effect (status 71), as expected"; then
  ok "the tag is also read off the \`::\` signature, not only the \`fn\`"
else
  bad "the tag on the signature half was not honoured"
fi
if printf '%s\n' "$xf" | grep -qx "5 test(s), 1 failed"; then
  ok "the summary counts only the one real failure, not the two expected ones"
else
  bad "the summary miscounted the expected failures"
fi

# --------------------------------------------------------------------
echo
echo "== \`assertFloatNear\` compares within a tolerance, inclusively =="
# --------------------------------------------------------------------
# `float-near-tests.ax` compares within epsilon, exactly at it, and far
# enough outside it to catch a real mismatch. An assertion that always
# passes is worse than none.
set +e
fn_out="$(axiom_test suite/float-near-tests.ax)"; rc=$?
set -e
if (( rc == 1 )); then ok "float-near-tests.ax exits 1"; else bad "float-near-tests.ax exits $rc, expected 1"; fi

if diff -u "$fixtures/float-near-tests.out" <(printf '%s\n' "$fn_out") > "$work/floatnear.diff"; then
  ok "its report is the golden, byte for byte"
else
  bad "float-near-tests.ax report differs from tests/testrunner/float-near-tests.out"
  sed 's/^/     /' "$work/floatnear.diff"
fi
if printf '%s\n' "$fn_out" | grep -qx "ok   testFloatNearAtTheBoundary"; then
  ok "a diff exactly equal to epsilon passes (inclusive), not a surprise failure"
else
  bad "the boundary case did not pass - the comparison is not inclusive"
fi
if printf '%s\n' "$fn_out" | grep -q "^FAIL testFloatNearCatchesARealMismatch"; then
  ok "a diff outside epsilon still fails"
else
  bad "assertFloatNear did not catch a real mismatch"
fi

# --------------------------------------------------------------------
echo
echo "== a file with no test is a failure, not an empty success =="
# --------------------------------------------------------------------
set +e
noout="$(axiom_test suite/no-tests.ax)"; rc=$?
set -e
if (( rc != 0 )) && printf '%s\n' "$noout" | grep -q "declares no test"; then
  ok "no-tests.ax exits $rc and says so"
else
  bad "no-tests.ax exited $rc: $noout"
fi

# --------------------------------------------------------------------
echo
echo "== a \`test\`-named function with parameters is refused by name =="
# --------------------------------------------------------------------
set +e
arout="$(axiom_test suite/arity-tests.ax)"; rc=$?
set -e
if (( rc != 0 )) \
   && printf '%s\n' "$arout" | grep -q 'testFixture' \
   && printf '%s\n' "$arout" | grep -q 'takes 1 parameter'; then
  ok "arity-tests.ax is refused, naming testFixture and its arity"
else
  bad "arity-tests.ax exited $rc without naming the function: $arout"
fi
# A refusal must not be a silent skip: the other test in that file must
# not have run either.
if printf '%s\n' "$arout" | grep -q '^ok '; then
  bad "the file was refused and something still ran"
else
  ok "nothing ran in the refused file"
fi

# --------------------------------------------------------------------
echo
echo "== \`setup\` and \`teardown\` run around every test =="
# --------------------------------------------------------------------
# `setup-tests.ax`: a `setup` hook appends "s" and a `teardown` hook
# appends "t" around two tests that append "1" and "2" to one log. Each
# test asserts the prefix the hooks must have written, so a hook that
# did not run fails an assertion and the golden is evidence.
set +e
hookout="$(axiom_test suite/setup-tests.ax)"; rc=$?
set -e
if (( rc == 0 )); then ok "setup-tests.ax exits 0"; else bad "setup-tests.ax exits $rc, expected 0"; echo "$hookout" | sed 's/^/     /'; fi

if diff -u "$fixtures/setup-tests.out" <(printf '%s\n' "$hookout") > "$work/setup.diff"; then
  ok "its report is the golden, byte for byte"
else
  bad "setup-tests.ax report differs from tests/testrunner/setup-tests.out"
  sed 's/^/     /' "$work/setup.diff"
fi

# Restate the golden's claims so a re-blessed golden cannot lose them.
# Both tests pass in order only if setup ran before the first and
# teardown closed it before the second's setup.
if printf '%s\n' "$hookout" | grep -qx "ok   testFirstSeesSetup" \
   && printf '%s\n' "$hookout" | grep -qx "ok   testSecondSeesTeardown"; then
  ok "both tests passed in declaration order, so both hooks ran per test"
else
  bad "a hook-guarded test did not pass - a hook did not run"
  printf '%s\n' "$hookout" | sed 's/^/     /'
fi

# --------------------------------------------------------------------
echo
echo "== a trapping \`teardown\` fails its test, and only its test =="
# --------------------------------------------------------------------
# `teardown-fails.ax`: one passing test closed by a teardown that
# divides by zero. Teardown runs inside the test's own recovery point,
# so the report is one FAIL at status 72 and the exit is 1.
set +e
tdout="$(axiom_test suite/teardown-fails.ax)"; rc=$?
set -e
if (( rc == 1 )); then ok "teardown-fails.ax exits 1"; else bad "teardown-fails.ax exits $rc, expected 1"; fi

if diff -u "$fixtures/teardown-fails.out" <(printf '%s\n' "$tdout") > "$work/teardown.diff"; then
  ok "its report is the golden, byte for byte"
else
  bad "teardown-fails.ax report differs from tests/testrunner/teardown-fails.out"
  sed 's/^/     /' "$work/teardown.diff"
fi

if printf '%s\n' "$tdout" | grep -qx "FAIL testClosesBadly - division by zero (status 72)"; then
  ok "the teardown's trap is reported on the test it closed, at status 72"
else
  bad "the teardown failure was not reported as its test's failure"
  printf '%s\n' "$tdout" | sed 's/^/     /'
fi

# --------------------------------------------------------------------
echo
echo "== a \`setup\` hook with parameters is refused by name =="
# --------------------------------------------------------------------
# `setup-arity-tests.ax` mirrors `arity-tests.ax` for the hook: a
# `setup` that takes a parameter cannot be run correctly, so the file is
# refused, naming the hook and its arity, and nothing in it runs.
set +e
saout="$(axiom_test suite/setup-arity-tests.ax)"; rc=$?
set -e
if (( rc != 0 )) \
   && printf '%s\n' "$saout" | grep -q 'setup' \
   && printf '%s\n' "$saout" | grep -q 'takes 1 parameter'; then
  ok "setup-arity-tests.ax is refused, naming setup and its arity"
else
  bad "setup-arity-tests.ax exited $rc without naming the hook: $saout"
fi
if printf '%s\n' "$saout" | grep -q '^ok '; then
  bad "the file was refused and something still ran"
else
  ok "nothing ran in the refused file"
fi

# --------------------------------------------------------------------
echo
echo "== --filter narrows the set, and narrows it to the right one =="
# --------------------------------------------------------------------
set +e
fout="$(axiom_test suite/pass-tests.ax --filter Map)"; rc=$?
set -e
if (( rc == 0 )) \
   && printf '%s\n' "$fout" | grep -qx "ok   testMapRoundTrips" \
   && printf '%s\n' "$fout" | grep -qx "1 test(s), 0 failed"; then
  ok "--filter Map runs exactly testMapRoundTrips"
else
  bad "--filter Map: exit $rc"; printf '%s\n' "$fout" | sed 's/^/     /'
fi
# A filter that matches nothing is a failure, for the same reason an
# empty file is: a suite that ran nothing must not exit 0.
set +e
zout="$(axiom_test suite/pass-tests.ax --filter NoSuchThing)"; rc=$?
set -e
if (( rc != 0 )); then ok "a filter matching nothing exits $rc"; else bad "a filter matching nothing exited 0"; fi

# --------------------------------------------------------------------
echo
echo "== a directory runs every .ax file in it, in name order =="
# --------------------------------------------------------------------
dir="$work/dir"
mkdir -p "$dir"
cp "$suite/pass-tests.ax" "$dir/a-pass.ax"
cp "$suite/mixed-tests.ax" "$dir/b-mixed.ax"
set +e
dout="$( ( cd "$work" && "$axc" test dir ) 2>&1 )"; rc=$?
set -e
if (( rc == 1 )) \
   && printf '%s\n' "$dout" | grep -qx "== dir/a-pass.ax ==" \
   && printf '%s\n' "$dout" | grep -qx "== dir/b-mixed.ax ==" \
   && printf '%s\n' "$dout" | grep -qx "2 file(s), 1 with a failing test"; then
  ok "both files ran, a-pass before b-mixed, and the summary counts them"
else
  bad "directory run: exit $rc"; printf '%s\n' "$dout" | sed 's/^/     /'
fi

# --------------------------------------------------------------------
echo
echo '== the Assert tag is load-bearing =='
# --------------------------------------------------------------------
# `stdlib/Test.ax` declares its `Assert` effect under
# `;@axiom:unhandled(trap)`, and only that tag keeps the generated
# runner free of diagnostics. AX3053 reports a custom effect that
# reaches `main` with no handler. The driver wraps every test in a
# lambda inside its `main`, so every assertion reaches `main`
# undischarged, and without the tag every suite draws AX3053.
#
# The tag is checked by removal: a shadow tree with its own `stdlib/`
# (the resolver looks in `<file>/../stdlib/`), the tag deleted from that
# copy alone, and the warning required to appear. The positive control
# runs first: a compiler that reported AX3053 on every suite would pass
# the removal arm and fail the control.
shadow="$work/shadow"
mkdir -p "$shadow/stdlib" "$shadow/suite"
cp -R "$repo_root/stdlib/." "$shadow/stdlib/"
cp "$fixtures/pass-tests.ax" "$shadow/suite/"

# `AXIOM_STDLIB` must name the shadow copy. `gate_init` exports it at the
# repository root and it wins over the path search, so without this
# override both runs read the real `stdlib/Test.ax`, the tag is deleted
# from a copy the compiler never opens, and the control passes for the
# wrong reason.
shadow_test() {
  ( cd "$shadow" && AXIOM_STDLIB="$shadow/stdlib" \
      "$axc" --diagnostic-format=ai test suite/pass-tests.ax ) 2>&1
}

tagged_out="$(shadow_test)"
if printf '%s\n' "$tagged_out" | grep -q 'AX3053'; then
  bad "with the tag in place, the runner still draws AX3053"
  printf '%s\n' "$tagged_out" | grep 'AX3053' | sed 's/^/     /'
else
  ok 'with ;@axiom:unhandled(trap) on Assert, the generated runner is silent'
fi

# Delete the tag line and only it. Count it first, so a renamed tag
# fails here instead of making the removal vacuous.
tagline=';@axiom:unhandled(trap)'
n="$(grep -c -F -x "$tagline" "$shadow/stdlib/Test.ax" || true)"
if [[ "$n" != 1 ]]; then
  bad "stdlib/Test.ax holds $n copies of '$tagline'; this arm expects exactly 1"
else
  grep -v -F -x "$tagline" "$shadow/stdlib/Test.ax" > "$shadow/Test.ax.stripped"
  mv "$shadow/Test.ax.stripped" "$shadow/stdlib/Test.ax"
  stripped_out="$(shadow_test)"
  if printf '%s\n' "$stripped_out" | grep -q 'AX3053.*effect `Assert`'; then
    ok 'with the tag deleted, the same suite draws AX3053 naming Assert'
  else
    bad "the tag was deleted and no AX3053 appeared: the claim is not load-bearing"
    printf '%s\n' "$stripped_out" | head -5 | sed 's/^/     /'
  fi
  # The suite must still run: the warning must not cost the build.
  if printf '%s\n' "$stripped_out" | grep -qx "5 test(s), 0 failed"; then
    ok 'and it is a warning: the suite still built and all 5 tests ran'
  else
    bad "the suite did not run under the warning"
    printf '%s\n' "$stripped_out" | tail -3 | sed 's/^/     /'
  fi
fi

# --------------------------------------------------------------------
echo
echo "== nothing is left behind =="
# --------------------------------------------------------------------
# The generated driver and the built executable are scratch, removed on
# every path out, including a failed build and a refused file. Every run
# above has finished, so anything left here is residue from one of them.
residue="$(find "$work" \( -name '.axiom-test.*' -o -name 'axiom_test_output.*' -o -name '*.ll' -o -name '*.o' \) -print)"
if [[ -z "$residue" ]]; then
  ok "no generated driver, executable or intermediate survives a run"
else
  bad "a run left files behind:"; printf '%s\n' "$residue" | sed 's/^/     /'
fi
# The fixtures themselves must be untouched.
if diff -r -q "$fixtures" "$suite" --exclude='*.out' >/dev/null 2>&1; then
  ok "the fixtures under test are byte-identical to the originals"
else
  bad "a run modified a file under test"
  diff -r -q "$fixtures" "$suite" --exclude='*.out' | sed 's/^/     /' || true
fi

echo
if (( failed > 0 )); then
  echo "check-test-runner: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-test-runner: $checks checks, and $mutants mutant(s) observed red"
