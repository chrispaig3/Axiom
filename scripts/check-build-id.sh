#!/usr/bin/env bash
# A shipped binary names the tree it was built from.
#
# `check-version.sh` holds every site that states the version to
# `VERSION`. This gate checks the build id, which says what was built:
#
#   1. An unstamped build says `unstamped`, so a missing id never reads
#      as a version, a zero hash or an empty string.
#   2. The id is a function of the source: the same tree gives the same
#      id, and one changed byte under `self_host/` or `stdlib/` moves it.
#      This is checked without building, because it is a property of
#      the id, not of the compiler.
#   3. The id reaches the binary: `axiom version` reports the stamp.
#   4. The banner still yields the semver that three other gates grep,
#      so a build id that breaks them fails here and not in their runs.
#   5. Building a stamped compiler does not modify the tree.
#
# The one-byte probe is the negative case. An id that never moves
# passes 1, 3, 4 and 5 while proving nothing.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# --------------------------------------------------------------------
echo "== an unstamped build says so =="
# --------------------------------------------------------------------
# `gate_build_axc` is the plain `axiom build` that contributors and the
# bootstrap ladder run. It must stay unstamped, or `check-bootstrap.sh`
# would compare binaries carrying a value neither source contains.
gate_build_axc axc
plain="$("$axc" version 2>&1)"
if [[ "$plain" == *"(build unstamped)"* ]]; then
  ok "a plain build reports \`(build unstamped)\`"
else
  bad "a plain build reports: $plain"
fi
# The literal must be spelled the way the stamper looks for it, or
# releases silently report `unstamped`. The formatter puts
# `(pub fn (axiomBuildId)` and `"unstamped")` on separate lines, so the
# match spans two lines.
if grep -A1 -Fx '(pub fn (axiomBuildId)' "$repo_root/self_host/build.ax" | grep -qFx '  "unstamped")'; then
  ok "self_host/build.ax holds the literal build-stamped.sh rewrites"
else
  bad "self_host/build.ax no longer holds that literal"
fi

# --------------------------------------------------------------------
echo
echo "== the id is a function of the source =="
# --------------------------------------------------------------------
id1="$(./scripts/build-stamped.sh --print-id)"
id2="$(./scripts/build-stamped.sh --print-id)"
if [[ -n "$id1" ]] && [[ "$id1" == "$id2" ]]; then
  ok "the same tree twice gives the same id ($id1)"
else
  bad "the id is not stable: '$id1' then '$id2'"
fi
# The hash is twelve hex characters. A shorter one collides sooner, and
# a longer one should be a reviewed change.
hash_part="${id1%% *}"
if [[ "$hash_part" =~ ^[0-9a-f]{12}$ ]]; then
  ok "its first field is twelve hex characters"
else
  bad "its first field is '$hash_part', not twelve hex characters"
fi

# The negative probe: append a comment to a source file in a copy, and
# the id must move. Two trees that differ only in a comment are still
# different source.
probe="$work/probe"
mkdir -p "$probe"
cp -R "$repo_root/self_host" "$probe/self_host"
cp -R "$repo_root/stdlib"    "$probe/stdlib"
before="$(gate_seed_source_stamp "$probe")"
if [[ "${before:0:12}" != "$hash_part" ]]; then
  bad "the copy does not hash like the tree - the probe is measuring itself"
else
  ok "the copy hashes like the tree"
fi
victim="$probe/stdlib/Path.ax"
[[ -f "$victim" ]] || { echo "FAIL: $victim is missing"; exit 1; }
printf '\n; one byte, for scripts/check-build-id.sh\n' >> "$victim"
after="$(gate_seed_source_stamp "$probe")"
if [[ "$after" != "$before" ]]; then
  ok "one changed source byte moves the id (${before:0:12} -> ${after:0:12})"
else
  bad "one changed source byte did not move the id - it names nothing"
fi

# --------------------------------------------------------------------
echo
echo "== the id reaches the binary =="
# --------------------------------------------------------------------
# One build with an explicit id, so the reported string can only have
# come from the stamper.
marker="probe-$(printf '%s' "$id1" | tr -d ' ' | cut -c1-8)-stamped"
if ./scripts/build-stamped.sh "$work/stamped" "$marker" >"$work/stamp.log" 2>&1; then
  got="$("$work/stamped" version 2>&1)"
  if [[ "$got" == *"(build $marker)"* ]]; then
    ok "a stamped build reports its id: $got"
  else
    bad "a stamped build reports '$got', wanted '(build $marker)'"
  fi
  # Two builds at one version must be distinguishable.
  if [[ "$got" != "$plain" ]]; then
    ok "the stamped and unstamped binaries report different builds at one version"
  else
    bad "the stamped and unstamped binaries report the same thing"
  fi
else
  bad "build-stamped.sh failed"
  sed 's/^/     /' "$work/stamp.log" | head -20
fi

# --------------------------------------------------------------------
echo
echo "== the banner is still what three other gates parse =="
# --------------------------------------------------------------------
want="$(tr -d '[:space:]' < "$repo_root/VERSION")"
sem="$(printf '%s' "$plain" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
if [[ "$sem" == "$want" ]]; then
  ok "\`axiom version\` still yields the semver $sem to a first-match grep"
else
  bad "\`axiom version\` yields '$sem', VERSION says '$want'"
fi
# The `ax_version` reader `check-version.sh` sources from
# `lib/version-sites.sh`, run here so a banner change that breaks it
# fails in the commit that made it.
if grep -qE 'Axiom [0-9]+\.[0-9]+\.[0-9]+ \(build' <<< "$plain"; then
  ok "check-version.sh's own pattern still matches the banner"
else
  bad "check-version.sh's pattern no longer matches: $plain"
fi
# The build id must not itself look like a version, or the greps above
# would have two candidates and the answer would depend on order.
if grep -qE '[0-9]+\.[0-9]+\.[0-9]+' <<< "$id1"; then
  bad "the build id contains something shaped like a semver: $id1"
else
  ok "the build id contains nothing shaped like a semver"
fi

# --------------------------------------------------------------------
echo
echo "== stamping does not modify the tree =="
# --------------------------------------------------------------------
# The stamper rewrites a copy. An in-place rewrite would mark every
# later build `-dirty`, and `check-fmt-selfhost.sh` would format it into
# the repository.
if grep -A1 -Fx '(pub fn (axiomBuildId)' "$repo_root/self_host/build.ax" | grep -qFx '  "unstamped")'; then
  ok "self_host/build.ax still says \`unstamped\` after a stamped build"
else
  bad "a stamped build rewrote self_host/build.ax in the tree"
fi

echo
if (( failed > 0 )); then
  echo "check-build-id: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-build-id: $checks checks - a shipped binary names its tree, an"
echo "                unstamped one says so, and one changed byte moves the id"
