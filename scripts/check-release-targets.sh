#!/usr/bin/env bash
# Checks that the release matrix, the installer and README's *Targets*
# section agree on which targets ship and which are supported.
#
# `.github/workflows/release.yml` decides which archives a release
# builds. `scripts/install.sh` decides which targets it refuses to fetch,
# so a host gets a sentence instead of an HTTP status. If the two
# disagree, the failure is silent:
#
#   built and refused   the release uploads an archive install.sh
#                       never fetches
#   neither             install.sh downloads an artifact no job made,
#                       and the user gets a 404 from curl
#
# Supported and shipped are separate axes. Supported means a CI leg
# executes what the compiler emits for that target (README, Targets).
# `check-doc-drift.sh` holds that list to `--help` and
# `docs/reference.md`. Shipped means a release carries a prebuilt archive.
#
#   supported + shipped      allowed
#   supported + unshipped    needs a Tests leg in ci.yml or a README reason
#   unsupported + unshipped  README's Source-only targets
#   unsupported + shipped    refused: an untested binary looks supported
#
# A source-only target has no archive and no Tests leg, and builds from
# the seed. It needs a `Bootstrap from seed (<target>)` leg in ci.yml, or
# a README sentence naming it that says no runner builds it
# (darwin-x86_64, baremetal-aarch64) or the compiler doesn't run there
# (windows-*).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
# Build the compiler: the accepted-target list comes from its `--help`,
# and `.axiom-bin/` is empty on a clean checkout.
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
# calls `build_it`. Only the arms are read, so a target named in a
# comment doesn't count as refused.
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
# The universe is the compiler's `--help` table, minus Windows. The
# compiler doesn't run there, and `install.sh` exits on `uname -s`
# before it forms a target string.
accepted="$("$axc" --help 2>/dev/null \
  | sed -n '/^TARGETS:/,/^NOTES:/p' \
  | sed -E 's/^ *(Supported|Source-only): *//' \
  | tr ',' '\n' | tr -d ' `.' | grep -E '^[a-z0-9_]+-[a-z0-9_]+$' | sort -u)"

if [[ -z "$accepted" ]]; then
  bad "could not read the accepted-target list from \`--help\`"
  echo "     the compiler under test was built by gate_build_axc, so an empty"
  echo "     read is a changed --help format, not a missing binary - and this"
  echo "     check would otherwise pass by comparing against nothing"
else
  missing=""
  for t in $accepted; do
    [[ "$t" == windows-* ]] && continue
    # Bare-metal images have a board linker, not an installer host.
    # The installer derives an OS from uname and never selects one.
    [[ "$t" == baremetal-* ]] && continue
    # `grep -x` without `-q`. Under `set -o pipefail`, `-q` exits on the
    # first match, printf dies of SIGPIPE (141), and a listed target
    # reads as missing. Reading to EOF leaves the match as the status.
    if ! printf '%s\n' $shipped $refused | grep -x "$t" >/dev/null; then
      missing="$missing $t"
    fi
  done
  if [[ -n "$missing" ]]; then
    bad "accepted by the compiler and neither built nor refused:$missing"
    echo "     a user on that host gets a 404 from curl instead of a sentence"
  else
    ok "every hosted non-Windows target the compiler accepts is built or refused"
  fi
fi

# --------------------------------------------------------------------
echo
echo "== an unshipped target that IS supported keeps its CI leg =="
# --------------------------------------------------------------------
# A target README lists as supported and release.yml doesn't build
# must still have a Tests leg in `ci.yml`.
readme_supported="$(sed -n '/^### Targets/,/^### /p' "$readme" \
  | tr '\n' ' ' \
  | sed -n 's/.*Supported: \([^.]*\)\..*/\1/p' \
  | tr ',' '\n' | tr -d ' `' | grep -E '^[a-z0-9_]+-[a-z0-9_]+$' | sort -u)"

if [[ -z "$readme_supported" ]]; then
  bad "could not read README's \`Supported:\` list - the check below would pass vacuously"
else
  ok "README lists supported: $(printf '%s ' $readme_supported)"
  # A supported, unshipped target passes if it has a leg or if README
  # explains that it is executed by no runner. An unexplained gap fails.
  targets_section="$(sed -n '/^### Targets/,/^## /p' "$readme")"
  # A Tests leg only: a `- name: <t>` row of the `test:` job's matrix,
  # or a job of its own named `Tests (<t>)`. Any `- name: <t>` in the
  # file would also count `Bootstrap from seed (<t>)`, which builds the
  # compiler there and executes nothing it emits.
  test_legs="$( { awk '
      /^  test:/ { on = 1; next }
      on && /^  [a-z]/ { exit }
      on { if (match($0, /^ *- name: [a-z0-9_]+-[a-z0-9_]+ *$/)) { sub(/^ *- name: /, ""); sub(/ *$/, ""); print } }
    ' "$ci_yml"
    sed -n 's/^ *name: Tests (\([a-z0-9_]*-[a-z0-9_]*\)) *$/\1/p' "$ci_yml"; } | sort -u)"
  gap=""; excused=""
  for t in $readme_supported; do
    if printf '%s\n' $shipped | grep -x "$t" >/dev/null; then continue; fi
    if printf '%s\n' $test_legs | grep -x "$t" >/dev/null; then continue; fi
    # The target and the reason must share one sentence. Matching the
    # whole section would excuse every name on its `Supported:` line.
    if tr '\n' ' ' <<<"$targets_section" | sed 's/\. /.\n/g' \
       | grep -F -- "\`$t\`" | grep -qiE "executed by no runner|no runner for it"; then
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

  # No supported target may have an advisory leg. `continue-on-error:
  # true` decides whether a leg can fail the workflow, and promoting a
  # target means removing it.
  adv=""
  for t in $readme_supported; do
    # `index`, not a regex. awk's `-v` processes escapes first, so
    # `\(` in a `-v` pattern becomes a group and the match is vacuous.
    job="$(awk -v want="name: Tests ($t)" '
      index($0, want) { found = 1; next }
      found && index($0, "continue-on-error") { print "advisory"; exit }
      found && /^  [a-z]/ { exit }
    ' "$ci_yml")"
    [[ -n "$job" ]] && adv="$adv $t"
  done
  if [[ -n "$adv" ]]; then
    bad "README calls these supported and their ci.yml leg is continue-on-error:$adv"
    echo "     an advisory leg cannot fail the workflow, so it does not"
    echo "     execute anything the project is held to. Remove the line or"
    echo "     the target from the list."
  else
    ok "no supported target has an advisory (continue-on-error) leg"
  fi

  # And the forbidden quadrant: shipped but not supported.
  ship_gap=""
  for t in $shipped; do
    printf '%s\n' $readme_supported | grep -x "$t" >/dev/null || ship_gap="$ship_gap $t"
  done
  if [[ -n "$ship_gap" ]]; then
    bad "built and attached but not in README's supported list:$ship_gap"
    echo "     an untested binary with a release attached to it reads as a"
    echo "     supported platform"
  else
    ok "every shipped target is one README calls supported"
  fi
fi

# --------------------------------------------------------------------
echo
echo "== a source-only target is built from the seed in CI, and nothing more =="
# --------------------------------------------------------------------
# README's `Source-only:` line names the targets with no archive and no
# Tests leg. Each must be off the supported list and the release matrix.
# CI must build the compiler there from the seed: a `bootstrap-no-rust`
# row `- name: <target>`, or a job named `Bootstrap from seed (<target>)`.
# The exception is a README sentence naming the target that says no
# runner builds it or the compiler doesn't run there. A missing
# `Source-only:` line fails.
targets_section="$(sed -n '/^### Targets/,/^## /p' "$readme")"
source_only="$(sed -n '/^### Targets/,/^## /p' "$readme" \
  | tr '\n' ' ' \
  | sed -n 's/.*Source-only: \([^.]*\)\..*/\1/p' \
  | tr ',' '\n' | tr -d ' `' | grep -E '^[a-z0-9_]+-[a-z0-9_]+$' | sort -u)"
boot_legs="$( { awk '
    /^  bootstrap-no-rust:/ { on = 1; next }
    on && /^  [a-z]/ { exit }
    on { if (match($0, /^ *- name: [a-z0-9_]+-[a-z0-9_]+ *$/)) { sub(/^ *- name: /, ""); sub(/ *$/, ""); print } }
  ' "$ci_yml"
  sed -n 's/^ *name: Bootstrap from seed (\([a-z0-9_]*-[a-z0-9_]*\)) *$/\1/p' "$ci_yml"; } | sort -u)"
if [[ -z "$source_only" ]]; then
  bad "could not read README's \`Source-only:\` line under ### Targets - the checks below would pass vacuously"
elif [[ -z "$boot_legs" ]]; then
  bad "ci.yml's bootstrap-no-rust matrix yielded no targets - no source-only target could have its leg"
else
  ok "README lists source-only: $(printf '%s ' $source_only)"
  for t in $source_only; do
    if printf '%s\n' $readme_supported | grep -x "$t" >/dev/null; then
      bad "$t is on README's Source-only line AND its Supported list"
    elif printf '%s\n' $shipped | grep -x "$t" >/dev/null; then
      bad "$t is source-only and release.yml builds an archive for it"
    elif printf '%s\n' $boot_legs | grep -x "$t" >/dev/null; then
      ok "$t: not supported, not shipped, and bootstrapped from the seed by ci.yml"
    elif tr '\n' ' ' <<<"$targets_section" | sed 's/\. /.\n/g' \
         | grep -F -- "\`$t\`" | grep -qiE "no runner|doesn't run on"; then
      ok "$t: not supported, not shipped, and README says why no CI leg builds it"
    else
      bad "$t is source-only, ci.yml has no Bootstrap from seed ($t) leg, and README doesn't say why - nothing checks the build it promises"
    fi
  done
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
echo "                       without a CI leg, and every source-only target is"
echo "                       bootstrapped from the seed in CI or explained"
