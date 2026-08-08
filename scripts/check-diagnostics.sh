#!/usr/bin/env bash
# The diagnostic corpus, pinned without a second compiler.
#
# WHAT THIS USED TO PIN.  `golden == stage0 == stage1`, byte for byte,
# over tests/diagnostics/*.{ax,axbad}: self-hosting phase 3's acceptance
# criterion. Three-way, deliberately, because comparing the two
# compilers alone cannot see the failure docs/self-hosting.md's risk
# table names first - a stage0 bug baked into stage1, where a wrong
# compiler looks self-consistent because both sides moved together.
#
# WHAT IT PINS NOW.  The Rust compiler is gone, and a differential does
# not fail when its reference disappears: point the same variable at a
# self-hosted binary and every comparison becomes a compiler against
# itself - 52 cases swept, zero differences, exit 0, nothing tested.
# That is the failure this repository names most often, so the arm was
# removed rather than repointed. What remains is
#
#   1. golden == the compiler built from self_host/, byte for byte, for
#      all 52 cases. The goldens are checked in, so a change in the
#      compiler's output arrives as a diff to a file in the repository.
#   2. tests/diagnostics/verify-axdl-spans.py: every span every golden
#      claims, checked against THE FIXTURE'S OWN BYTES - the line must
#      exist, the 1-based CHARACTER columns must lie inside it, and a
#      span may not begin or end in the middle of an identifier. 109
#      claims over the corpus today, 87 of them additionally anchored
#      (the source slice spells exactly the name the message quotes).
#   3. The per-case exit status, against an invariant read off the
#      golden's own severity column rather than off a second compiler:
#      a golden carrying an `E` line means the run must fail, a golden
#      carrying only `W` means it must succeed. The goldens hold AXDL
#      only, so nothing else in this gate looks at the exit status at
#      all.
#   4. The sweep, the floors and the refusal cases, unchanged in
#      substance - they were already single-sided or exit-status-only.
#
# WHY (2) IS ADEQUATE.  A checked-in golden alone is not: if the
# compiler emits a wrong column and someone regenerates the golden from
# it, the gate goes green forever. The span verifier cannot be satisfied
# that way, because it does not ask a compiler anything. Either
# tests/diagnostics/010-duplicate-fn.ax has a line 3 whose characters 6
# through 9 spell `main` or it does not, and that is decided by a file
# this repository also contains.
#
# Drilled at introduction rather than assumed, by building a compiler
# with `diag.ax`'s `colOf` seeded at 2 instead of 1 - every column one
# too high - and blessing the whole corpus from it:
#   * against the checked-in goldens, 52 of 52 cases differ
#   * blessing is REFUSED: the verifier runs before the bless returns
#   * with the wrong compiler's own freshly blessed goldens in place,
#     all 52 comparisons pass, the sweep passes, the refusal cases pass,
#     and the gate still exits 1 - 100 of the 109 claims are wrong and
#     the anchored count falls from 87 to 2 against a floor of 75. Every
#     span still lands inside its line; what fails is that `main` at
#     3:7-11 covers `ain)`, which begins in the middle of a name.
#   * hand-editing one golden to the BYTE columns a non-decoding lexer
#     would report (070's 3:22-26 -> 3:24-28) is caught the same way:
#     the span covers `sh) `, which ends on whitespace.
#
# It is also the one thing here that the old differential could not do.
# stage0 and stage1 agreeing on a column said the two agreed; this says
# the column is CORRECT. And unlike a golden it does not churn - the
# position is recomputed from the source on every run, so editing a
# fixture and re-blessing its golden leaves the check just as sharp.
#
# Blessing runs it too, and refuses the bless if it fails, so a wrong
# span cannot be written into the corpus in the first place:
#   AXIOM_BLESS=1 scripts/check-diagnostics.sh          # all cases
#   AXIOM_BLESS=1 scripts/check-diagnostics.sh 010      # one case
#
# PROVENANCE.  No golden was newly materialized for this conversion; all
# 52 were already checked in. Measured 2026-08-08, while both compilers
# still existed: the Rust compiler, the compiler built from self_host/
# by the installed self-hosted binary, and the checked-in goldens agree
# on all 52 cases byte for byte, and the span verifier passes on those
# same goldens with 0 of 109 claims wrong. That is the last moment there
# were two compilers to compare, and this is the record of it.
#
# Three failure modes guarded explicitly, because all three look like
# success:
#
#   * Vacuous agreement. A corpus case that stops producing a diagnostic
#     - a fixture typo, a check accidentally removed - emits nothing,
#     and empty == empty is agreement by silence. Every golden must be
#     non-empty and carry at least one AXDL line, every fixture must
#     have a golden and every golden a fixture, and the corpus must
#     carry at least 15 distinct codes: a corpus that says one thing
#     proves one thing.
#
#   * False positives on the compiler's own source. A checker that
#     rejects self_host/, stdlib/ or the stdlib test corpus is worse
#     than no checker, and no corpus case would notice, so the sweep
#     runs the compiler over every file in all four trees and requires
#     silence. tests/stdlib/ is in that list because it is the only
#     place effects and the builtin `Option` appear - a checker that
#     rejected every effect program passed a sweep without it.
#     tests/selfhost/ is in it because it is the largest body of
#     programs written to be compiled by the self-hosted compiler, and
#     it was missing when type checking landed: `150-struct.ax` passed
#     `__load64` a struct handle, which the Rust compiler has always
#     rejected (every primitive is `Int`-typed) and the self-hosted one
#     accepted only because it did not yet check types. The sweep read
#     three trees and reported clean; check-self-host.sh caught it
#     instead. A checker's silence has to be swept over every tree of
#     correct programs, not most of them.
#
#   * A sweep that reads nothing. Silence is what the sweep reports on
#     success, so a renamed tree or a glob that stops matching takes its
#     files out of it invisibly - which is how tests/selfhost/ went
#     unswept while the sweep said "clean". The count is printed and a
#     floor well under it refuses outright.
#
# Usage:
#   scripts/check-diagnostics.sh          # every case
#   scripts/check-diagnostics.sh 010      # one case, by name prefix

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/.axiom-bin/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "no compiler at $axiom - building one from the committed seed" >&2
  "$repo_root/scripts/bootstrap-from-seed.sh" --install "$repo_root/.axiom-bin" >&2 \
    || { echo "FAIL: could not bootstrap a compiler" >&2; exit 1; }
fi

export AXIOM_STDLIB="$repo_root/stdlib"

filter="${1:-}"
bless="${AXIOM_BLESS:-0}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The compiler resolves `(import Foo)` against `self_host/` and
# `stdlib/` relative to its working directory, so both have to be
# reachable from wherever it runs - and the cases run from `$work` so
# that the filename it prints is a bare `NAME.ax`. The filename is
# echoed verbatim into every AXDL line and into every golden.
ln -s "$repo_root/stdlib" "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"
# The sweep below runs from `$work` and names its inputs by
# repo-relative path, so `tests/` has to be reachable from here too.
# Without this the sweep read nothing, reported nothing, and passed -
# the exact vacuous success the rest of this script exists to refuse.
ln -s "$repo_root/tests" "$work/tests"

# Helper MODULES for cases that need more than one file. They live in a
# subdirectory so the per-case glob below cannot mistake one for a case
# needing a golden, and they are copied flat because a module name is
# its filename stem: `tests/diagnostics/mods/AmbA.ax` is `(import
# AmbA)`. AX3014 is the reason - a name is only ambiguous when two
# IMPORTED modules define it, which one file cannot express.
cp "$repo_root"/tests/diagnostics/mods/*.ax "$work/" 2>/dev/null || true

# The compiler under test is the one built FROM SOURCE by `$axiom`, not
# `$axiom` itself: this gate exists to test self_host/, and `$axiom` may
# be an older seed-descended binary that predates the change being
# tested.
if ! "$axiom" build --input self_host/main.ax --output "$work/axc" >"$work/build.log" 2>&1; then
  echo "FAIL: could not build the compiler under test" >&2
  tail -20 "$work/build.log" >&2
  exit 1
fi

# Only the AXDL lines. The trailing "compilation failed due to N
# previous errors" / "OK" is CLI chrome, not AXDL, and no golden
# records it.
axdl_only() { grep -E '^[EWNH] ' || true; }

passed=0
failed=0
cases=0
exit_zero=0
exit_nonzero=0

# `.axbad` is a case that deliberately does NOT parse - the AX1xxx and
# AX2xxx codes cannot be provoked by a file that does. It cannot be
# spelled `.ax`: check-fmt.sh and check-tree-sitter.sh sweep every
# `*.ax` in the repository and require all of them to parse, and they
# are right to. The extension is the LSP gate's, for the same reason.
# Both kinds are copied into the work directory AS `.ax`, so the
# diagnostic names the file the way every other case does.
for case_file in tests/diagnostics/*.ax tests/diagnostics/*.axbad; do
  [[ -e "$case_file" ]] || continue
  base="$(basename "$case_file")"
  name="${base%.ax}"
  name="${name%.axbad}"
  if [[ -n "$filter" && "$name" != "$filter"* ]]; then
    continue
  fi
  golden="tests/diagnostics/$name.axdl"

  cp "$case_file" "$work/$name.ax"

  (cd "$work" && ./axc --diagnostic-format=ai "$name.ax" >/dev/null 2>"$work/case.err")
  status=$?
  got="$(axdl_only < "$work/case.err")"

  if [[ "$bless" == 1 ]]; then
    printf '%s\n' "$got" > "$repo_root/$golden"
    echo "blessed $name"
    continue
  fi

  cases=$((cases + 1))

  if [[ ! -s "$golden" ]]; then
    echo "FAIL $name (no golden at $golden, or it is empty; run with AXIOM_BLESS=1)"
    failed=$((failed + 1))
    continue
  fi

  # Agreement by silence is not agreement.
  if ! grep -qE '^[EWNH] ' "$golden"; then
    echo "FAIL $name (golden has no AXDL line - a case that diagnoses nothing proves nothing)"
    failed=$((failed + 1))
    continue
  fi

  want="$(cat "$golden")"

  if [[ "$got" != "$want" ]]; then
    echo "FAIL $name (output differs from the golden)"
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi

  # The exit status, against an invariant read off the golden rather
  # than off a second compiler. The goldens carry AXDL and nothing else,
  # so without this a compiler that printed `E AX3006 ...` and then
  # exited 0 - reporting an error and compiling the program anyway -
  # would pass every other check here.
  if grep -qE '^E ' "$golden"; then
    if [[ "$status" == 0 ]]; then
      echo "FAIL $name (golden carries an error, the run exited 0)"
      failed=$((failed + 1))
      continue
    fi
  elif [[ "$status" != 0 ]]; then
    echo "FAIL $name (golden carries only warnings, the run exited $status)"
    failed=$((failed + 1))
    continue
  fi
  if (( status > 128 )); then
    echo "FAIL $name (died of signal $((status - 128)) - a crash is not a diagnosis)"
    failed=$((failed + 1))
    continue
  fi
  if [[ "$status" == 0 ]]; then exit_zero=$((exit_zero + 1)); else exit_nonzero=$((exit_nonzero + 1)); fi

  echo "ok   $name"
  passed=$((passed + 1))
done

# Every fixture needs a golden and every golden a fixture. A golden left
# behind by a deleted fixture is never read and never fails; a fixture
# whose golden was deleted would, before this, have been reported once
# and then quietly blessed back into existence.
if [[ -z "$filter" && "$bless" != 1 ]]; then
  for g in tests/diagnostics/*.axdl; do
    stem="$(basename "$g" .axdl)"
    if [[ ! -e "tests/diagnostics/$stem.ax" && ! -e "tests/diagnostics/$stem.axbad" ]]; then
      echo "FAIL: $g has no fixture - it is a golden nothing generates"
      failed=$((failed + 1))
    fi
  done
fi

if [[ "$bless" == 1 ]]; then
  echo
  echo "--- the blessed goldens' spans, against the fixtures' own bytes ---"
  if ! python3 tests/diagnostics/verify-axdl-spans.py tests/diagnostics; then
    echo "FAIL: refusing the bless - a golden claims a span the fixture does not have"
    exit 1
  fi
  echo "goldens regenerated; review the diff before committing"
  exit 0
fi

# ---------------------------------------------------------------
# The half a re-bless cannot satisfy.
# ---------------------------------------------------------------
echo
echo "--- every golden's spans, against the fixtures' own bytes ---"
if ! python3 tests/diagnostics/verify-axdl-spans.py tests/diagnostics; then
  echo "FAIL: a golden claims a span its fixture does not have"
  failed=$((failed + 1))
fi

# The compiler's own source must produce no diagnostics at all. This is
# the constraint that decides whether a check is shippable: a false
# positive here does not merely annoy, it stops the compiler compiling
# itself. It is also this gate's positive control - 165 files the
# compiler must ACCEPT, which is what stops the refusal cases below
# being satisfied by a compiler that refuses everything.
echo
echo "--- the compiler finds nothing to report in self_host/, stdlib/, tests/stdlib/, tests/selfhost/ ---"
selfclean=0
swept=0
for src in self_host/*.ax stdlib/*.ax stdlib/Sys/*.ax tests/stdlib/*.ax \
           tests/selfhost/*.ax; do
  [[ -e "$src" ]] || continue
  swept=$((swept + 1))
  # `--diagnostic-format=ai` is load-bearing now that the compiler
  # defaults to human: `axdl_only` keeps only `^[EWNH] ` lines, so a
  # human-rendered warning on a clean-exit file would pass BOTH checks -
  # grep-empty and exit 0 - and this section would go blind to exactly
  # the class of report it exists to refuse.
  out="$(cd "$work" && ./axc --diagnostic-format=ai "$src" 2>"$work/sweep.err" >/dev/null; echo "$?")"
  diags="$(axdl_only < "$work/sweep.err")"
  if [[ -n "$diags" ]]; then
    echo "FAIL $src (a diagnostic on the compiler's own source)"
    printf '%s\n' "$diags" | sed 's/^/    /'
    failed=$((failed + 1))
    selfclean=1
  elif [[ "$out" != 0 && "$src" != tests/stdlib/* ]]; then
    # Silence plus a non-zero exit is not cleanliness, it is the
    # compiler falling over before it could check anything - which would
    # let this whole section report success while testing nothing.
    #
    # Exempted for tests/stdlib/, and only there: those cases exercise
    # the whole language rather than the subset the self-hosted compiler
    # accepts, so a couple of them still fail to PARSE (qualified module
    # references, struct variants). They are swept anyway because they
    # are the only programs in the repository that use the effect system
    # and the builtin `Option` - and a checker that rejected every
    # effect program was invisible to a sweep that covered only
    # self_host/ and stdlib/, which is exactly what happened.
    echo "FAIL $src (exited $out with no diagnostic: it did not get far enough to check)"
    sed 's/^/    /' "$work/sweep.err" | head -3
    failed=$((failed + 1))
    selfclean=1
  fi
done

# The sweep's own pipeline, negative-tested: run the sweep's exact
# invocation shape on a file KNOWN to produce a diagnostic, and require
# the AXDL filter to see it. This is the one place the human-default
# flip could fail silently - `axdl_only` keeps only `^[EWNH] ` lines and
# the exit-status backstop exempts tests/stdlib/, so a sweep invocation
# that lost its `--diagnostic-format=ai` flag would render human, match
# nothing, and report the compiler's own source clean without checking
# it.
cp "$repo_root/tests/diagnostics/330-axtag-mismatch.ax" "$work/flipneg.ax"
(cd "$work" && ./axc --diagnostic-format=ai "flipneg.ax" 2>"$work/flipneg.err" >/dev/null)
if [[ -z "$(axdl_only < "$work/flipneg.err")" ]]; then
  echo "FAIL: the sweep pipeline is blind - a known-warning file produced no AXDL through it"
  failed=$((failed + 1))
fi

# ---------------------------------------------------------------
# SEVERITY, against a list no compiler writes.
#
# Every other fact this gate checks comes out of the compiler under
# test - the goldens are its output, and the span verifier reads the
# fixtures but takes the compiler's word for what SEVERITY a code has.
# That word and the exit status are the same field: `countErrorDiags`
# and `sevSigil` both read `(memGetWord d 0)`. So "the golden says E,
# therefore this exits non-zero" is a theorem about the compiler's
# source and not a test of it.
#
# Measured, not theorised: flipping one `SEV_ERROR` to `SEV_WARNING` in
# typecheck.ax and re-blessing produced a compiler that exits 0 on a
# type-incorrect program and emits a call through an `inttoptr` of an
# integer - and this gate passed, 55 checks, 0 failed, every span
# verified.
#
# tests/diagnostics/severity.policy is the one artifact here that is
# hand-maintained. A code absent from it must never render as `W`.
# ---------------------------------------------------------------
policy="tests/diagnostics/severity.policy"
[[ -f "$policy" ]] || { echo "FAIL: $policy is missing - severity would be unchecked"; exit 1; }
warn_ok="$(grep -oE '^AX[0-9]{4}' "$policy" | sort -u)"
if [[ -z "$warn_ok" ]]; then
  echo "FAIL: $policy lists no codes; a policy that permits nothing is indistinguishable from one nobody wrote"
  failed=$((failed + 1))
fi
bad_sev=0
while read -r code; do
  [[ -n "$code" ]] || continue
  if ! printf '%s\n' "$warn_ok" | grep -qx "$code"; then
    echo "FAIL severity: $code renders as a WARNING in a golden but is not in $policy"
    grep -l "^W $code " tests/diagnostics/*.axdl | sed 's/^/     /'
    bad_sev=$((bad_sev + 1))
  fi
done < <(grep -ohE '^W (AX[0-9]{4})' tests/diagnostics/*.axdl | awk '{print $2}' | sort -u)
if (( bad_sev > 0 )); then
  failed=$((failed + bad_sev))
else
  # And the other direction, which is the one the drill exercised: a
  # code the policy does NOT list must appear as `E` wherever it
  # appears at all. Demoting it to `W` and re-blessing is exactly what
  # this refuses.
  demotable="$(grep -ohE '^[EW] AX[0-9]{4}' tests/diagnostics/*.axdl | sort -u \
               | awk '{print $2}' | sort | uniq -d | tr '\n' ' ')"
  if [[ -n "${demotable// /}" ]]; then
    for c in $demotable; do
      printf '%s\n' "$warn_ok" | grep -qx "$c" || {
        echo "FAIL severity: $c appears as both E and W, and is not in $policy"
        failed=$((failed + 1)); }
    done
  fi
  echo "ok   severity: every code not in $policy renders as an error ($(printf '%s\n' "$warn_ok" | grep -c .) permitted warning code(s))"
fi

# Floors PER TREE, not one total. A single total of 100 against ~165
# files only notices the loss of tests/selfhost/, which is the largest
# tree; losing all of stdlib/ or all of self_host/ left the total above
# the floor and the sweep reported the silence it was looking for.
sweep_floor() {
  local label="$1" want="$2" got
  got="$(printf '%s\n' $3 | grep -c . || true)"
  if (( got < want )); then
    echo "FAIL the sweep read $got files from $label, floor $want - that tree is missing from the globs"
    failed=$((failed + 1))
  fi
}
sweep_floor "self_host/"      15 "$(ls self_host/*.ax 2>/dev/null)"
sweep_floor "stdlib/"         10 "$(ls stdlib/*.ax stdlib/Sys/*.ax 2>/dev/null)"
sweep_floor "tests/stdlib/"   30 "$(ls tests/stdlib/*.ax 2>/dev/null)"
sweep_floor "tests/selfhost/" 80 "$(ls tests/selfhost/*.ax 2>/dev/null)"

# A floor well under the current 165 refuses outright.
if [[ "$swept" -lt 100 ]]; then
  echo "FAIL sweep read only $swept files (expected ~165): a tree is missing from the globs"
  failed=$((failed + 1))
elif [[ "$selfclean" == 0 ]]; then
  echo "ok   all $swept files across those four trees are clean"
fi

# ---------------------------------------------------------------
# Refusal cases. Single-sided: each one names a program the compiler
# must not accept, and the sweep above is the positive control that
# keeps "must not accept" from being satisfied by refusing everything.
# ---------------------------------------------------------------

# A bare expression at module scope is a PARSE ERROR. The parser used to
# consume any unknown-headed form as an inert node, so `(+ 1 2)` as a
# whole file checked clean (exit 0, `OK`) while the Rust compiler
# refused it with AX2001 - and a typo'd declaration VANISHED with no
# diagnostic. Reintroducing the skip makes this exit 0, and this fails.
printf '(+ 1 2)\n' > "$work/bare-expr.ax"
(cd "$work" && ./axc check "bare-expr.ax" >/dev/null 2>&1); b1=$?
if [[ "$b1" == 0 ]]; then
  echo "FAIL: a bare top-level expression was accepted (exit $b1)"
  failed=$((failed + 1))
elif (( b1 > 128 )); then
  echo "FAIL: died of signal $((b1 - 128)) on a bare top-level expression instead of refusing"
  failed=$((failed + 1))
else
  echo "ok   refusal: a bare top-level expression (exit $b1)"
  passed=$((passed + 1))
fi

# A QUALIFIED reference naming the wrong module.
#
# `Mod::Ctor` was a false AX3001 on a program that compiles and runs,
# because `mangleDecl` rewrites `fn` and `::` declarations to `Mod$name`
# and does not rewrite `data` or `struct` - so the qualified spelling
# was parsed into a name nothing declared.
# `tests/selfhost/900-qualified-ctors.ax` pins the ACCEPTING half by
# running it; this pins the other half, which a fix that simply stripped
# the module part would break: `Nope::Dim` must still be refused when
# `Nope` declares nothing.
cp "$repo_root/tests/selfhost/Qual.ax" "$work/Qual.ax"
printf '(import Qual)\n(:: main Int)\n(fn (main) (match Nope::Dim ((Dim) 1) ((Bright) 2)))\n' \
  > "$work/wrong-module.ax"
(cd "$work" && ./axc check "wrong-module.ax" >/dev/null 2>&1); q1=$?
if [[ "$q1" == 0 ]]; then
  echo "FAIL: a qualified reference to a module that declares nothing was accepted (exit $q1)"
  failed=$((failed + 1))
else
  echo "ok   refusal: \`Nope::Dim\` names a module that declares nothing (exit $q1)"
  passed=$((passed + 1))
fi

# NESTING DEPTH, and the crash it replaces.
#
# There was no depth limit and no counter anywhere. Measured
# 2026-08-08: a 20,000-deep expression that the Rust compiler rejects
# with AX2005 (`nesting is too deep (limit is 1024)`) was ACCEPTED here
# and checked clean, and at 100,000 the compiler died of SIGSEGV.
# Accepting a program the other compiler refused was the worse half of
# that pair: a crash is at least loud, while a silent accept compiles
# something that is not a program.
#
# The depth here is the one that used to CRASH, not merely the one that
# used to be accepted, so this pins both halves. And it has to refuse by
# refusing: a signal death is not a refusal, which is why the status is
# checked against 128 as well as against 0.
deep_n=100000
deep_open="$(yes '(+ 1 ' | head -n "$deep_n" | tr -d '\n')"
deep_close="$(yes ')' | head -n "$deep_n" | tr -d '\n')"
printf '(:: main Int)\n(fn (main) %s0%s)\n' "$deep_open" "$deep_close" > "$work/deep.ax"
(cd "$work" && ./axc check "deep.ax" >/dev/null 2>&1); d1=$?
if [[ "$d1" == 0 ]]; then
  echo "FAIL: ${deep_n}-deep nesting was accepted (exit $d1)"
  failed=$((failed + 1))
elif (( d1 > 128 )); then
  echo "FAIL: died of signal $((d1 - 128)) on ${deep_n}-deep nesting instead of refusing"
  failed=$((failed + 1))
else
  echo "ok   refusal: ${deep_n}-deep nesting (exit $d1)"
  passed=$((passed + 1))
fi

# ---------------------------------------------------------------
# Floors. Only meaningful on a full run; a name-prefix filter is a
# debugging aid and is expected to read one case.
# ---------------------------------------------------------------
if [[ -z "$filter" ]]; then
  if (( cases < 45 )); then
    echo "FAIL: only $cases corpus cases ran (expected ~52) - the glob stopped matching"
    failed=$((failed + 1))
  fi
  # An exit-status column of all one value distinguishes nothing: it
  # would be satisfied by a compiler that fails on every input, which is
  # the shape a broken driver takes.
  if (( exit_zero == 0 || exit_nonzero == 0 )); then
    echo "FAIL: every corpus case exited the same way ($exit_zero zero, $exit_nonzero non-zero)"
    failed=$((failed + 1))
  fi
fi

echo
echo "$passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
