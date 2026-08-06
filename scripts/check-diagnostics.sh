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

for case_file in tests/diagnostics/*.ax; do
  name="$(basename "$case_file" .ax)"
  if [[ -n "$filter" && "$name" != "$filter"* ]]; then
    continue
  fi
  golden="tests/diagnostics/$name.axdl"

  cp "$case_file" "$work/$name.ax"

  s0="$(cd "$work" && "$axiom" --diagnostic-format=ai check "$name.ax" 2>&1 | axdl_only)"
  s1="$(cd "$work" && ./stage1 "$name.ax" 2>&1 >/dev/null | axdl_only)"

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
  out="$(cd "$work" && ./stage1 "$src" 2>"$work/sweep.err" >/dev/null; echo "$?")"
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
# a floor well under the current 124 refuses outright.
if [[ "$swept" -lt 100 ]]; then
  echo "FAIL sweep read only $swept files (expected ~124): a tree is missing from the globs"
  failed=$((failed + 1))
elif [[ "$selfclean" == 0 ]]; then
  echo "ok   all $swept files across those four trees are clean"
fi

echo
echo "$passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
