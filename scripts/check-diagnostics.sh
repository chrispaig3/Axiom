#!/usr/bin/env bash
# Byte-identical AXDL between the two compilers - the acceptance
# criterion docs/self-hosting.md sets for self-hosting phase 3.
#
# THREE-way, not two-way. Comparing stage0 against stage1 alone cannot
# see the failure the risk table in docs/self-hosting.md names first: a
# stage0 bug baked into stage1, where a wrong compiler looks
# self-consistent because both sides moved together. Each case
# therefore carries a checked-in golden, and the gate asserts
#
#     golden == stage0 == stage1
#
# so a change in *either* compiler's output has to be reviewed as a
# diff to a file in the repository rather than silently agreed to.
#
# Regenerate a golden deliberately, never casually:
#   AXIOM_BLESS=1 scripts/check-diagnostics.sh          # all cases
#   AXIOM_BLESS=1 scripts/check-diagnostics.sh 010      # one case
#
# Two failure modes this guards against explicitly, because both look
# like success:
#
#   * Vacuous agreement. stage1 emitted nothing at all before this
#     phase existed, and a corpus case that stops producing a
#     diagnostic (a fixture typo, a check accidentally removed) also
#     emits nothing from stage0. Empty == empty is agreement by
#     silence, so every golden must contain at least one AXDL line.
#
#   * False positives on the compiler's own source. A checker that
#     rejects self_host/, stdlib/ or the stdlib test corpus is worse
#     than no checker, and no corpus case would notice, so the last
#     section runs stage1 over every file in all four trees and
#     requires silence. tests/stdlib/ is in that list because it is
#     the only place effects and the builtin `Option` appear - a
#     checker that rejected every effect program passed a sweep
#     without it. tests/selfhost/ is in it because it is the largest
#     body of programs written to be compiled BY stage1, and it was
#     missing when type checking landed: `150-struct.ax` passed
#     `__load64` a struct handle, which stage0 has always rejected
#     (every primitive is `Int`-typed) and stage1 accepted only
#     because it did not yet check types. The sweep read the three
#     trees and reported clean; check-self-host.sh caught it instead,
#     as a conformance case suddenly failing. A checker's silence has
#     to be swept over every tree of correct programs, not most of
#     them.
#
# Usage:
#   scripts/check-diagnostics.sh          # every case
#   scripts/check-diagnostics.sh 010      # one case, by name prefix

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "building the compiler first (no binary at $axiom)" >&2
  cargo build --release
fi

export AXIOM_STDLIB="$repo_root/stdlib"

filter="${1:-}"
bless="${AXIOM_BLESS:-0}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# stage1 resolves `(import Foo)` against `self_host/` and `stdlib/`
# relative to its working directory, so both have to be reachable from
# wherever it runs - and the cases run from `$work` so that the
# filename each compiler prints is a bare `NAME.ax` for both. The
# filename is echoed verbatim into every AXDL line; invoking one
# compiler with a path and the other with a basename makes every line
# differ for a reason that has nothing to do with diagnostics.
ln -s "$repo_root/stdlib" "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"
# The sweep below runs from `$work` and names its inputs by
# repo-relative path, so `tests/` has to be reachable from here too.
# Without this the sweep read nothing, reported nothing, and passed -
# the exact vacuous success the rest of this script exists to refuse.
ln -s "$repo_root/tests" "$work/tests"

# Helper MODULES for cases that need more than one file. They live in
# a subdirectory so the per-case glob below cannot mistake one for a
# case needing a golden, and they are copied flat because a module
# name is its filename stem: `tests/diagnostics/mods/AmbA.ax` is
# `(import AmbA)`. AX3014 is the reason - a name is only ambiguous
# when two IMPORTED modules define it, which one file cannot express.
cp "$repo_root"/tests/diagnostics/mods/*.ax "$work/" 2>/dev/null || true

if ! "$axiom" build --input self_host/main.ax --output "$work/stage1" >"$work/build.log" 2>&1; then
  echo "FAIL: could not build stage1" >&2
  tail -20 "$work/build.log" >&2
  exit 1
fi

# Only the AXDL lines. The trailing "compilation failed due to N
# previous errors" / "OK" is CLI chrome, not AXDL, and stage1 has no
# reason to reproduce it.
axdl_only() { grep -E '^[EWNH] ' || true; }

passed=0
failed=0

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

  s0="$(cd "$work" && "$axiom" --diagnostic-format=ai check "$name.ax" 2>&1 | axdl_only)"
  s1="$(cd "$work" && ./stage1 --diagnostic-format=ai "$name.ax" 2>&1 >/dev/null | axdl_only)"

  if [[ "$bless" == 1 ]]; then
    printf '%s\n' "$s0" > "$repo_root/$golden"
    echo "blessed $name"
    continue
  fi

  if [[ ! -f "$golden" ]]; then
    echo "FAIL $name (no golden at $golden; run with AXIOM_BLESS=1)"
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

  if [[ "$s0" != "$want" ]]; then
    echo "FAIL $name (stage0 drifted from the golden)"
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$s0") | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi

  if [[ "$s1" != "$want" ]]; then
    echo "FAIL $name (stage1 disagrees)"
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$s1") | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi

  echo "ok   $name"
  passed=$((passed + 1))
done

if [[ "$bless" == 1 ]]; then
  echo "goldens regenerated; review the diff before committing"
  exit 0
fi

# The compiler's own source must produce no diagnostics at all. This is
# the constraint that decides whether a check is shippable: a false
# positive here does not merely annoy, it stops the compiler compiling
# itself.
echo
echo "--- stage1 finds nothing to report in self_host/, stdlib/, tests/stdlib/, tests/selfhost/ ---"
selfclean=0
swept=0
for src in self_host/*.ax stdlib/*.ax stdlib/Sys/*.ax tests/stdlib/*.ax \
           tests/selfhost/*.ax; do
  [[ -e "$src" ]] || continue
  swept=$((swept + 1))
  # `--diagnostic-format=ai` is load-bearing now that stage1 defaults
  # to human: `axdl_only` below keeps only `^[EWNH] ` lines, so a
  # human-rendered warning on a clean-exit file would pass BOTH
  # checks - grep-empty and exit 0 - and this section would go blind
  # to exactly the class of report it exists to refuse.
  out="$(cd "$work" && ./stage1 --diagnostic-format=ai "$src" 2>"$work/sweep.err" >/dev/null; echo "$?")"
  diags="$(axdl_only < "$work/sweep.err")"
  if [[ -n "$diags" ]]; then
    echo "FAIL $src (stage1 reports a diagnostic on the compiler's own source)"
    printf '%s\n' "$diags" | sed 's/^/    /'
    failed=$((failed + 1))
    selfclean=1
  elif [[ "$out" != 0 && "$src" != tests/stdlib/* ]]; then
    # Silence plus a non-zero exit is not cleanliness, it is stage1
    # falling over before it could check anything - which would let
    # this whole section report success while testing nothing.
    #
    # Exempted for tests/stdlib/, and only there: those cases exercise
    # the whole language rather than the subset stage1 compiles, so a
    # couple of them still fail to PARSE under stage1 (qualified
    # module references, struct variants). They are swept anyway
    # because they are the only programs in the repository that use
    # the effect system and the builtin `Option` - and a checker that
    # rejected every effect program was invisible to a sweep that
    # covered only self_host/ and stdlib/, which is exactly what
    # happened.
    echo "FAIL $src (stage1 exited $out with no diagnostic: it did not get far enough to check)"
    sed 's/^/    /' "$work/sweep.err" | head -3
    failed=$((failed + 1))
    selfclean=1
  fi
done
# A third failure that looks like success: the sweep reading fewer
# files than it should. A renamed tree or a glob that stops matching
# takes its files out of the sweep silently, and silence is exactly
# what this section reports on success - which is how tests/selfhost/
# went unswept while the sweep said "clean". The count is printed, and
# Refusal parity for the top-level grammar: a bare expression at
# module scope is a PARSE ERROR in both compilers. stage1's parser
# used to consume any unknown-headed form as an inert node, so
# `(+ 1 2)` as a whole file checked clean (exit 0, `OK`) while
# stage0 refused it with AX2001 - and a typo'd declaration VANISHED
# with no diagnostic. The exit codes still differ (stage0 1,
# stage1 2 - the parse-error path is a recorded open divergence);
# what this pins is that BOTH refuse. Reintroducing the skip makes
# stage1 exit 0 here, and this fails.
printf '(+ 1 2)\n' > "$work/bare-expr.ax"
(cd "$work" && "$axiom" check "bare-expr.ax" >/dev/null 2>&1); b0=$?
(cd "$work" && ./stage1 check "bare-expr.ax" >/dev/null 2>&1); b1=$?
if [[ "$b0" == 0 || "$b1" == 0 ]]; then
  echo "FAIL: a bare top-level expression was accepted (stage0=$b0 stage1=$b1)"
  failed=$((failed + 1))
fi

# Refusal parity for NESTING DEPTH, and the crash it replaces.
#
# stage1 had no depth limit and no counter anywhere. Measured
# 2026-08-08: a 20,000-deep expression that stage0 rejects with AX2005
# (`nesting is too deep (limit is 1024)`) was ACCEPTED by stage1 and
# checked clean, and at 100,000 stage1 died of SIGSEGV where stage0
# went on answering in the ordinary way. Accepting a program the other
# compiler refuses is the worse half of that pair: a crash is at least
# loud, while a silent accept compiles something stage0 says is not a
# program.
#
# The depth here is the one that used to CRASH, not merely the one
# that used to be accepted, so this pins both halves. And stage1 has
# to refuse by refusing: a signal death is not a refusal, which is why
# the status is checked against 128 as well as against 0. Exit codes
# still differ (stage0 1, stage1 2) for the reason the bare-expression
# case above records - the parse-error path is a recorded open
# divergence, and AX2005's code and span arrive with it.
deep_n=100000
deep_open="$(yes '(+ 1 ' | head -n "$deep_n" | tr -d '\n')"
deep_close="$(yes ')' | head -n "$deep_n" | tr -d '\n')"
printf '(:: main Int)\n(fn (main) %s0%s)\n' "$deep_open" "$deep_close" > "$work/deep.ax"
(cd "$work" && "$axiom" check "deep.ax" >/dev/null 2>&1); d0=$?
(cd "$work" && ./stage1 check "deep.ax" >/dev/null 2>&1); d1=$?
if [[ "$d0" == 0 || "$d1" == 0 ]]; then
  echo "FAIL: ${deep_n}-deep nesting was accepted (stage0=$d0 stage1=$d1)"
  failed=$((failed + 1))
elif (( d1 > 128 )); then
  echo "FAIL: stage1 died of signal $((d1 - 128)) on ${deep_n}-deep nesting instead of refusing"
  failed=$((failed + 1))
else
  echo "ok   refusal parity: ${deep_n}-deep nesting refused by both (stage0=$d0 stage1=$d1)"
  passed=$((passed + 1))
fi

# The sweep's own pipeline, negative-tested: run the sweep's exact
# invocation shape on a file KNOWN to produce a diagnostic, and
# require the AXDL filter to see it. This is the one place the
# human-default flip could fail silently - `axdl_only` keeps only
# `^[EWNH] ` lines and the exit-status backstop exempts
# tests/stdlib/, so a sweep invocation that lost its
# `--diagnostic-format=ai` flag would render human, match nothing,
# and report the compiler's own source clean without checking it.
cp "$repo_root/tests/diagnostics/330-axtag-mismatch.ax" "$work/flipneg.ax"
(cd "$work" && ./stage1 --diagnostic-format=ai "flipneg.ax" 2>"$work/flipneg.err" >/dev/null)
if [[ -z "$(axdl_only < "$work/flipneg.err")" ]]; then
  echo "FAIL: the sweep pipeline is blind - a known-warning file produced no AXDL through it"
  failed=$((failed + 1))
fi

# a floor well under the current 163 refuses outright.
if [[ "$swept" -lt 100 ]]; then
  echo "FAIL sweep read only $swept files (expected ~163): a tree is missing from the globs"
  failed=$((failed + 1))
elif [[ "$selfclean" == 0 ]]; then
  echo "ok   all $swept files across those four trees are clean"
fi

echo
echo "$passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
