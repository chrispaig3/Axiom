#!/usr/bin/env bash
# The diagnostic corpus, pinned without a second compiler.
#
# WHAT THIS USED TO PIN.  `golden == stage0 == stage1`, byte for byte,
# over tests/diagnostics/*.{ax,axbad}: self-hosting phase 3's acceptance
# criterion. Three-way, deliberately, because comparing the two
# compilers alone cannot see the failure the self-hosting record's risk
# table names first - a stage0 bug baked into stage1, where a wrong
# compiler looks self-consistent because both sides moved together.
#
# WHAT IT PINS NOW.  The Rust compiler is gone, and a differential does
# not fail when its reference disappears: point the same variable at a
# self-hosted binary and every comparison becomes a compiler against
# itself - measured 2026-08-08 at the 52 cases of that day: swept,
# zero differences, exit 0, nothing tested.
# That is the failure this repository names most often, so the arm was
# removed rather than repointed. What remains is
#
#   1. golden == the compiler built from self_host/, byte for byte, for
#      every case. The goldens are checked in, so a change in the
#      compiler's output arrives as a diff to a file in the repository.
#   2. tests/diagnostics/verify-axdl-spans.py: every span every golden
#      claims, checked against THE FIXTURE'S OWN BYTES - the line must
#      exist, the 1-based CHARACTER columns must lie inside it, and a
#      span may not begin or end in the middle of an identifier.
#      (The gate prints the counts it reached, and the verifier's own
#      floors are re-derived against them; both said 52 cases and 109
#      claims until 2026-08-16, when the corpus had reached 126 and
#      418. A number written into a header ages; the printed one does
#      not, which is why this paragraph no longer carries one.)
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
#     carry a floor of distinct codes - a corpus that says one thing
#     proves one thing. That floor lives with the other three in
#     `verify-axdl-spans.py`, which is where it is re-derived; this
#     line said "at least 15" while the number there was 24 and then
#     40, so it now names the owner rather than the value.
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
#   scripts/check-diagnostics.sh 010      # every case whose name starts with 010

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

filter="${1:-}"
bless="${AXIOM_BLESS:-0}"

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

# A RELATIVE stdlib root, overriding the absolute one `gate_init`
# exports. The corpus is the compiler's OUTPUT, checked in, and an AXDL
# line spells the path of every file it names - including, since
# `AX3049` started resolving its call chain, `stdlib/IO.ax` for a hop
# that lives there. Resolved through `$AXIOM_STDLIB` as an absolute
# path, that field reads `/Users/somebody/checkout/stdlib/IO.ax` and
# the golden reproduces on exactly one machine. `stdlib` relative
# resolves through the symlink above - the same file, named the way the
# repository names it. `verify-axdl-spans.py` refuses an absolute path
# outright, so this cannot go wrong quietly.
export AXIOM_STDLIB="stdlib"

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
gate_build_axc axc

# Only the AXDL lines. The trailing "compilation failed due to N
# previous errors" / "OK" is CLI chrome, not AXDL, and no golden
# records it.
axdl_only() { grep -E '^[EWNH] ' || true; }

passed=0
failed=0
cases=0
exit_zero=0
exit_nonzero=0
colorless=0   # runs whose `ai` stderr carried no ANSI escape

# `.axbad` is a case the repository-wide sweeps must not judge. Usually
# that is a file that deliberately does NOT parse - the AX1xxx and
# AX2xxx codes cannot be provoked by a file that does - but it is also
# where a file lands that parses and that `fmt` refuses, which
# `395-sizeof-surplus.axbad` does: `format.ax` and the tree-sitter grammar
# both already encode that `sizeof` takes exactly one type, and the
# checker is what did not. Either way it cannot be spelled `.ax`:
# check-fmt.sh and check-tree-sitter.sh sweep every `*.ax` in the
# repository and require all of them to parse and to format, and they
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

  # AXDL IS COLOURLESS, and this is where that is enforced. The human
  # renderer paints its output; AXDL is the machine surface and must not,
  # because a consumer of these lines is a `grep`, a diff or another
  # program. Checked over the WHOLE stderr rather than over `got`,
  # because `axdl_only` keeps `^[EWNH] ` lines and would silently drop a
  # line whose severity sigil had been pushed rightwards by an escape -
  # the failure would then read as a missing diagnostic somewhere else.
  # The trailer is printed in this format too, and is covered here.
  if LC_ALL=C grep -q $'\x1b' "$work/case.err"; then
    echo "FAIL $name (\`--diagnostic-format=ai\` emitted an ANSI escape; AXDL is the machine surface)"
    failed=$((failed + 1))
    continue
  fi
  colorless=$((colorless + 1))

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

# ---------------------------------------------------------------
# THE CALL CHAIN IS IN THE FIELDS AND NOT ONLY IN THE PROSE.
#
# `AX3049` has named its path since the graph walk landed, and named it
# inside the quoted message, where only a reader could use it: measured
# 2026-09-03, `grep -h AX3049 tests/diagnostics/*.axdl | grep -c ' ^'`
# was 0 across the whole corpus. It is now one `^` field per hop, and
# the HOP-FOR-HOP equality - the k-th field's label is the (k+1)-th hop,
# spelled the same way - is made by `verify-axdl-spans.py` above, which
# is where the AXDL parser lives and which a bless cannot satisfy.
#
# What is made HERE is the population count, in the crudest way there
# is, because the two failures are different. The equality catches a
# chain and a field list that disagree. It says nothing at all if the
# corpus stops carrying chains, or if the compiler stops emitting the
# fields and every golden is re-blessed without them: the comparison
# then holds vacuously over zero lines. So the counts are read off the
# checked-in goldens by grep and floored.
# ---------------------------------------------------------------
echo
echo "--- the call chains, and the related locations beside them ---"
chain_lines="$(grep -hE '^[EW] (AX3049|AX3051|AX3057) ' tests/diagnostics/*.axdl \
                 | grep -c ' -> ' || true)"
chain_fields="$(grep -hE '^[EW] (AX3049|AX3051|AX3057) ' tests/diagnostics/*.axdl \
                 | grep ' -> ' | grep -o ' \^' | grep -c . || true)"
if (( chain_lines < 20 )); then
  echo "FAIL: only $chain_lines golden line(s) carry a resolved \`->\` chain (floor 20)"
  failed=$((failed + 1))
elif (( chain_fields < 46 )); then
  echo "FAIL: those $chain_lines chain line(s) carry only $chain_fields \`^\` field(s) (floor 46) - the path is back in the message and nowhere else"
  failed=$((failed + 1))
else
  echo "ok   $chain_lines chain line(s), $chain_fields related location(s) beside them"
  passed=$((passed + 1))
fi

# The compiler's own source must produce no diagnostics at all. This is
# the constraint that decides whether a check is shippable: a false
# positive here does not merely annoy, it stops the compiler compiling
# itself. It is also this gate's positive control - 256 files the
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

# Floors PER TREE, not one total. A single total only notices the loss
# of tests/selfhost/, which is the largest tree; losing all of stdlib/
# or all of self_host/ left the total above the floor and the sweep
# reported the silence it was looking for.
#
# Re-derived 2026-08-22 against 22/20/59/168 = 269 files. They were
# 19/16/52/150 = 237, derived 2026-08-16 against 256, and before that
# 15/10/30/80 = 135 against a corpus of 165 - which stayed put while
# the corpus grew half again, so tests/selfhost/ could have lost HALF
# its files and still cleared 80. A floor is only a floor while it is
# near the number it guards; re-derive these when the printed count has
# pulled ahead.
sweep_floor() {
  local label="$1" want="$2" got
  got="$(printf '%s\n' $3 | grep -c . || true)"
  if (( got < want )); then
    echo "FAIL the sweep read $got files from $label, floor $want - that tree is missing from the globs"
    failed=$((failed + 1))
  fi
}
sweep_floor "self_host/"      20 "$(ls self_host/*.ax 2>/dev/null)"
sweep_floor "stdlib/"         18 "$(ls stdlib/*.ax stdlib/Sys/*.ax 2>/dev/null)"
sweep_floor "tests/stdlib/"   55 "$(ls tests/stdlib/*.ax 2>/dev/null)"
sweep_floor "tests/selfhost/" 160 "$(ls tests/selfhost/*.ax 2>/dev/null)"

# A floor just under the current 256 refuses outright.
if [[ "$swept" -lt 240 ]]; then
  echo "FAIL sweep read only $swept files (expected ~269): a tree is missing from the globs"
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
(cd "$work" && ./axc --diagnostic-format=ai check "deep.ax" \
   >/dev/null 2>"$work/deep.err"); d1=$?
if [[ "$d1" == 0 ]]; then
  echo "FAIL: ${deep_n}-deep nesting was accepted (exit $d1)"
  failed=$((failed + 1))
elif (( d1 > 128 )); then
  echo "FAIL: died of signal $((d1 - 128)) on ${deep_n}-deep nesting instead of refusing"
  failed=$((failed + 1))
# Refusing is half of it. This used to be a BARE refusal - `parse
# failed` on stderr with exit 2, no code, no span, against stage0's
# AX2005 and exit 1 - and a gate that only asked "did it refuse" is
# what let that sit. Both halves are named now: the code, and the
# status stage0 exits with.
elif ! grep -qE '^E AX2005 .* recursion-limit ' "$work/deep.err"; then
  echo "FAIL: ${deep_n}-deep nesting was refused without AX2005: $(head -1 "$work/deep.err")"
  failed=$((failed + 1))
elif [[ "$d1" != 1 ]]; then
  echo "FAIL: ${deep_n}-deep nesting exited $d1; a diagnosed program is refused with 1"
  failed=$((failed + 1))
else
  echo "ok   refusal: ${deep_n}-deep nesting (AX2005, exit $d1)"
  passed=$((passed + 1))
fi

# The other half of a limit is that just under it still works. A guard
# that refused everything would satisfy every assertion above.
under_n=1022
under_open="$(yes '(+ 1 ' | head -n "$under_n" | tr -d '\n')"
under_close="$(yes ')' | head -n "$under_n" | tr -d '\n')"
printf '(:: main Int)\n(fn (main) %s0%s)\n' "$under_open" "$under_close" > "$work/under.ax"
(cd "$work" && ./axc check "under.ax" >/dev/null 2>"$work/under.err"); d2=$?
if [[ "$d2" != 0 ]]; then
  echo "FAIL: nesting just under the limit was refused (exit $d2): $(head -1 "$work/under.err")"
  failed=$((failed + 1))
else
  echo "ok   nesting just under the limit still parses"
  passed=$((passed + 1))
fi

# ---------------------------------------------------------------
# Floors. Only meaningful on a full run; a name-prefix filter is a
# debugging aid and is expected to read one case.
# ---------------------------------------------------------------
if [[ -z "$filter" ]]; then
  if (( cases < 132 )); then
    echo "FAIL: only $cases corpus cases ran (expected ~139) - the glob stopped matching"
    failed=$((failed + 1))
  fi
  # An exit-status column of all one value distinguishes nothing: it
  # would be satisfied by a compiler that fails on every input, which is
  # the shape a broken driver takes.
  if (( exit_zero == 0 || exit_nonzero == 0 )); then
    echo "FAIL: every corpus case exited the same way ($exit_zero zero, $exit_nonzero non-zero)"
    failed=$((failed + 1))
  fi
  # The colourless assertion is made per case and counted, so that it
  # cannot evaporate the way a check wired to a glob that stopped
  # matching does.
  if (( colorless < 132 )); then
    echo "FAIL: only $colorless run(s) were checked for ANSI escapes (expected ~139)"
    failed=$((failed + 1))
  fi
fi

echo
echo "$passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
