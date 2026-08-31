#!/usr/bin/env bash
# THE SHIPPED-TARGET LIST IS ONE FACT WITH TWO COPIES, and they are on
# opposite sides of the project: `.github/workflows/release.yml` decides
# what gets BUILT and attached, and `scripts/install.sh` decides what a
# user's machine is told when it asks for an archive. If those two
# disagree, exactly one of two things happens, and both are silent:
#
#   a target in the matrix and in the refusal list  - the release
#     builds and uploads an archive that `install.sh` then refuses to
#     fetch. Work done, nobody served.
#
#   a target in neither                             - `install.sh`
#     tries to download an artifact no job produced and the user gets
#     a 404 from `curl`, which reads as "the project is broken" rather
#     than "build it yourself".
#
# The second is the one that actually happened in kind: before
# `darwin-x86_64` was added to the refusal list, a Rosetta host got a
# bare download failure. The refusal exists so a host gets a sentence
# instead of an HTTP status, and this gate exists so the sentence
# cannot drift away from the matrix that makes it necessary.
#
# TWO AXES, NOT ONE. `docs/memory-model.md` is not the reference here;
# README's *Targets* section is. SUPPORTED means a CI leg executes what
# the compiler emits for that target - `check-doc-drift.sh` holds that
# list to `--help` and to `docs/reference.md`. SHIPPED means a release
# carries a prebuilt archive. They are independent, and every
# combination but one is currently real:
#
#   supported + shipped      linux-aarch64, darwin-aarch64
#   supported + unshipped    linux-x86_64   (2026-08-30, see below)
#   unsupported + unshipped  darwin-x86_64, freebsd-x86_64,
#                            freebsd-aarch64
#   unsupported + shipped    forbidden - it is the state that makes an
#                            untested binary look supported, and the
#                            check at the bottom refuses it
#
# WHY linux-x86_64 IS UNSHIPPED, recorded here because it is the one
# entry a reader will assume is a mistake. It was dropped from the
# release on 2026-08-30 for cost, not for doubt: that leg was the
# slowest and the most frequently re-run part of cutting a release, and
# the platform it serves is the one whose users are most likely to have
# a toolchain already. Its CI leg is untouched - `Tests (linux-x86_64)`
# runs the whole battery on every pull request - and if that ever stops
# being true, this gate's supported-set check is what notices.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
# Built rather than borrowed. The accepted-target list is read from the
# compiler's own `--help`, and a gate that falls back to "could not
# read it" whenever no binary happens to be lying around is a gate that
# reports less than it knows - `.axiom-bin/` is empty on a clean
# checkout, which is most of them.
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

release_yml="$repo_root/.github/workflows/release.yml"
installer="$repo_root/scripts/install.sh"
ci_yml="$repo_root/.github/workflows/ci.yml"
readme="$repo_root/README.md"

for f in "$release_yml" "$installer" "$ci_yml" "$readme"; do
  [[ -f "$f" ]] || { echo "FAIL: $f is missing"; exit 1; }
done

# --------------------------------------------------------------------
# The two lists, each read from the file that owns it.
# --------------------------------------------------------------------
# The build matrix. Anchored on `- name: <os>-<arch>` at the matrix
# indent, which is the only place that spelling appears in the file.
shipped="$(sed -n 's/^ *- name: \([a-z0-9_]*-[a-z0-9_]*\) *$/\1/p' "$release_yml" | sort -u)"

# `install.sh`'s refusal list: every target named in a `case` arm that
# calls `build_it`. Read as the arms themselves rather than as one
# regex over the file, so a target mentioned in a COMMENT is not
# counted as refused.
refused="$(awk '
  /^ *(linux|darwin|freebsd)-[a-z0-9_]*(\|[a-z0-9_-]*)*\)$/ {
    line = $0
    sub(/^ *!/, "", line); sub(/\)$/, "", line)
    n = split(line, parts, "|")
    for (i = 1; i <= n; i++) { gsub(/^ +| +$/, "", parts[i]); print parts[i] }
  }
' "$installer" | sort -u)"

echo "== the two lists =="
if [[ -z "$shipped" ]]; then
  bad "release.yml's build matrix yielded no targets - this gate would compare nothing"
else
  ok "release.yml builds: $(printf '%s ' $shipped)"
fi
if [[ -z "$refused" ]]; then
  bad "install.sh's refusal arms yielded no targets - this gate would compare nothing"
else
  ok "install.sh refuses: $(printf '%s ' $refused)"
fi
(( failed == 0 )) || { echo; echo "check-release-targets: $failed failed"; exit 1; }

# --------------------------------------------------------------------
echo
echo "== no target is both built and refused =="
# --------------------------------------------------------------------
both="$(comm -12 <(printf '%s\n' $shipped) <(printf '%s\n' $refused))"
if [[ -n "$both" ]]; then
  bad "built AND refused: $(printf '%s ' $both)"
  echo "     the release would upload an archive install.sh will not fetch"
else
  ok "the built set and the refused set are disjoint"
fi

# --------------------------------------------------------------------
echo
echo "== every target the compiler accepts is in exactly one of them =="
# --------------------------------------------------------------------
# The compiler's own table is the universe, minus `windows-x86_64`:
# hosting the compiler on Windows is a later phase, `install.sh` dies
# on `uname -s` before it ever forms a target string, and README's
# Targets section says so. A Windows entry in either list would be
# describing a host that cannot reach this code.
accepted="$("$axc" --help 2>/dev/null \
  | sed -n 's/.*--target <NAME>[^a-z]*\(.*\)/\1/p' \
  | tr ',' '\n' | tr -d ' `' | grep -E '^[a-z0-9_]+-[a-z0-9_]+$' | sort -u)"

if [[ -z "$accepted" ]]; then
  bad "could not read the accepted-target list from \`--help\`"
  echo "     the compiler under test was built by gate_build_axc, so an empty"
  echo "     read is a changed --help format, not a missing binary - and this"
  echo "     check would otherwise pass by comparing against nothing"
else
  missing=""
  for t in $accepted; do
    [[ "$t" == windows-* ]] && continue
    if ! printf '%s\n' $shipped $refused | grep -qx "$t"; then
      missing="$missing $t"
    fi
  done
  if [[ -n "$missing" ]]; then
    bad "accepted by the compiler and neither built nor refused:$missing"
    echo "     a user on that host gets a 404 from curl instead of a sentence"
  else
    ok "every non-Windows target the compiler accepts is built or refused"
  fi
fi

# --------------------------------------------------------------------
echo
echo "== an unshipped target that IS supported keeps its CI leg =="
# --------------------------------------------------------------------
# The one thing that would make dropping an artifact dishonest: saying
# a target is supported, publishing nothing for it, AND quietly not
# testing it either. For every target that README lists as supported
# and release.yml does not build, `ci.yml` must still run a leg.
readme_supported="$(sed -n '/^### Targets/,/^### /p' "$readme" \
  | tr '\n' ' ' \
  | sed -n 's/.*Supported: \([^.]*\)\..*/\1/p' \
  | tr ',' '\n' | tr -d ' `' | grep -E '^[a-z0-9_]+-[a-z0-9_]+$' | sort -u)"

if [[ -z "$readme_supported" ]]; then
  bad "could not read README's \`Supported:\` list - the check below would pass vacuously"
else
  ok "README lists supported: $(printf '%s ' $readme_supported)"
  # A supported, unshipped target must still be EXECUTED somewhere, or
  # the word "supported" stops meaning anything. There is one standing
  # exception and it is grandfathered IN THE README rather than here:
  # `darwin-x86_64` predates the rule and is executed by no runner,
  # which that section says in as many words. So the test is "has a leg
  # OR is explained", and an unexplained one fails - silence is what
  # this refuses, not the exception itself.
  targets_section="$(sed -n '/^### Targets/,/^## /p' "$readme")"
  gap=""; excused=""
  for t in $readme_supported; do
    if printf '%s\n' $shipped | grep -qx "$t"; then continue; fi
    if grep -q "name: $t" "$ci_yml"; then continue; fi
    if grep -q "$t" <<<"$targets_section" \
       && grep -qiE "executed by no runner|no runner for it" <<<"$targets_section"; then
      excused="$excused $t"
    else
      gap="$gap $t"
    fi
  done
  if [[ -n "$gap" ]]; then
    bad "supported, unshipped, no ci.yml leg, and unexplained:$gap"
    echo "     'supported' means a CI leg executes what the compiler emits"
    echo "     there (README, Targets). Dropping the artifact AND the leg"
    echo "     leaves the word meaning nothing. Say why, or restore one."
  elif [[ -n "$excused" ]]; then
    ok "every supported-but-unshipped target has a ci.yml leg, except$excused, which README explains"
  else
    ok "every supported-but-unshipped target still has a ci.yml leg"
  fi

  # And the forbidden quadrant: shipped but not supported.
  ship_gap=""
  for t in $shipped; do
    printf '%s\n' $readme_supported | grep -qx "$t" || ship_gap="$ship_gap $t"
  done
  if [[ -n "$ship_gap" ]]; then
    bad "built and attached but not in README's supported list:$ship_gap"
    echo "     an untested binary with a release attached to it reads as a"
    echo "     supported platform"
  else
    ok "every shipped target is one README calls supported"
  fi
fi

echo
if (( failed > 0 )); then
  echo "check-release-targets: $failed of $((checks + failed)) failed"
  exit 1
fi
echo "check-release-targets: $checks checks - the release matrix and the"
echo "                       installer's refusal list are disjoint, cover every"
echo "                       target the compiler accepts, and no target is"
echo "                       shipped without being supported or left supported"
echo "                       without a CI leg"
