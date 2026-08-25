#!/usr/bin/env bash
# `axiom test`: the runner, the assertions, and the isolation that is
# the only reason a runner is more than a convention.
#
# WHAT THIS GATE IS ABOUT. A test runner's characteristic defect is a
# test that does not run and is not reported - a skipped test reads
# exactly like a passing one, which is this repository's name for a
# check that cannot fail. So the assertions here are, in order of how
# much they matter:
#
#   1. A failing test FAILS. Nothing else in this file is worth
#      anything if a mutated assertion still exits 0, so that is the
#      negative probe and it runs against every passing fixture.
#   2. Every test declared is a test reported. The report is compared
#      against a list derived from the fixture's own bytes by `grep`,
#      which is a source outside the compiler - the same argument
#      `check-backtrace.sh` makes for checking its frame names against
#      `nm`.
#   3. One failure ends ONE test. `mixed-tests.ax` fails in the three
#      ways an Axiom program can stop without returning, and the test
#      declared AFTER all three still reports `ok`.
#   4. A file with no test is a failure, and a `test`-named function
#      that takes parameters is refused by name.
#
# WHY THE FIXTURES ARE COPIED INTO $work. `axiom test` writes its
# generated driver beside the file under test, because that is where
# the file's own imports resolve from. Running the gate against
# `tests/testrunner/` directly would therefore write into the
# repository - briefly, and removed on every path out, but a gate that
# writes into the tree is a gate that can leave something in it. The
# copy also makes the last assertion possible: after every run, the
# working copy must hold exactly the files it started with.
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
# Every `assertEq` in the passing suite, one at a time, with its
# expected value replaced by one that cannot be right. Each mutant
# must exit 1 AND name the test it broke - exiting 1 for some other
# reason would pass a weaker check.
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

# The claim the golden encodes, restated so a re-blessed golden cannot
# quietly lose it: the LAST test still ran.
if printf '%s\n' "$mixed" | grep -qx "ok   testTheLastOneStillRuns"; then
  ok "the test declared after all three failures still ran"
else
  bad "the test after the failures did not run - isolation is broken"
fi
# And the line the failed assertion must NOT have reached.
if printf '%s\n' "$mixed" | grep -q "unreachable"; then
  bad "execution continued past a failed assertion"
else
  ok "nothing ran after the failed assertion inside its own test"
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
# The refusal must not be a silent skip: the OTHER test in that file
# must not have run either.
if printf '%s\n' "$arout" | grep -q '^ok '; then
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
echo "== nothing is left behind =="
# --------------------------------------------------------------------
# The generated driver and the built executable are both scratch, and
# both are unlinked on every path out - including the ones where the
# build failed and where the file was refused. Every run above has
# happened by now, so what is on disk here is the residue of all of
# them.
residue="$(find "$work" \( -name '.axiom-test.*' -o -name 'axiom_test_output.*' -o -name '*.ll' -o -name '*.o' \) -print)"
if [[ -z "$residue" ]]; then
  ok "no generated driver, executable or intermediate survives a run"
else
  bad "a run left files behind:"; printf '%s\n' "$residue" | sed 's/^/     /'
fi
# And the fixtures themselves are untouched.
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
