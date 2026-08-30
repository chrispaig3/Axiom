#!/usr/bin/env bash
# A shipped binary names the tree it was built from.
#
# WHAT WAS MISSING. `axiom version` printed `axiom (self-hosted) 0.2.0`
# and nothing else, so two builds of two DIFFERENT trees at one version
# were the same binary to whoever held one. `check-version.sh` has
# named that gap in its own header since it was written: it holds every
# site that STATES the version to `VERSION`, which is a promise about
# an interface, and says nothing about what was built.
#
# WHAT THIS ASSERTS, in the order the claims depend on each other:
#
#   1. An unstamped build says `unstamped` - not a version, not a zero
#      hash, not an empty string. An absent id must read as its own
#      absence or it reads as an answer.
#   2. The id is a FUNCTION OF THE SOURCE: the same tree twice gives
#      the same id, and one changed byte anywhere under `self_host/`
#      or `stdlib/` gives a different one. This is the whole property,
#      and it is checked without building, because it is a property of
#      the id and not of the compiler.
#   3. The id REACHES THE BINARY. One build, one assertion: what
#      `--print-id` says is what `axiom version` reports.
#   4. The banner is still parseable. Three other gates grep a semver
#      out of this line; a build id that broke them would be found by
#      those gates in some other run and blamed on something else.
#   5. Building a stamped compiler does not modify the tree.
#
# The one-byte probe is the negative one and it is not optional: an id
# that never moves passes 1, 3, 4 and 5 while proving nothing at all.
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
# `gate_build_axc` is a plain `axiom build` over `self_host/`, which is
# what a contributor runs and what the bootstrap ladder runs. It must
# NOT be stamped: if it were, `check-bootstrap.sh` would be comparing
# two binaries carrying a value neither source contains.
gate_build_axc axc
plain="$("$axc" version 2>&1)"
if [[ "$plain" == *"(build unstamped)"* ]]; then
  ok "a plain build reports \`(build unstamped)\`"
else
  bad "a plain build reports: $plain"
fi
# And the literal is in the source, spelled the way the stamper looks
# for it. A rename here silently produces `unstamped` releases.
if grep -q '(pub fn (axiomBuildId) "unstamped")' "$repo_root/self_host/build.ax"; then
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
# The hash half must be twelve hex characters. A shorter one would
# collide sooner than anyone would look; a longer one is a change
# somebody should have to mean.
hash_part="${id1%% *}"
if [[ "$hash_part" =~ ^[0-9a-f]{12}$ ]]; then
  ok "its first field is twelve hex characters"
else
  bad "its first field is '$hash_part', not twelve hex characters"
fi

# THE NEGATIVE PROBE. One byte, in a copy, and the id must move. The
# byte is chosen in a file the compiler's own build reads, and the
# change is to a function BODY rather than a comment - though for this
# hash a comment would move it too, and that is deliberate: two trees
# that differ only in a comment are still two trees, and a reader
# holding two binaries wants to know they are not the same source.
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
# ONE build, with an explicit id, because the assertion is that the
# string the stamper chose is the string the binary reports - and an
# explicit id makes that unmistakable, where the computed one could in
# principle match by accident.
marker="probe-$(printf '%s' "$id1" | tr -d ' ' | cut -c1-8)-stamped"
if ./scripts/build-stamped.sh "$work/stamped" "$marker" >"$work/stamp.log" 2>&1; then
  got="$("$work/stamped" version 2>&1)"
  if [[ "$got" == *"(build $marker)"* ]]; then
    ok "a stamped build reports its id: $got"
  else
    bad "a stamped build reports '$got', wanted '(build $marker)'"
  fi
  # ...and the two binaries disagree, which is the sentence this whole
  # gate is about: two builds at one VERSION, distinguishable.
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
# `check-version.sh`'s extractor, run here rather than described, so a
# banner change that breaks it fails in the commit that made it.
if printf '%s' "$plain" | grep -qE 'Axiom [0-9]+\.[0-9]+\.[0-9]+ \(build'; then
  ok "check-version.sh's own pattern still matches the banner"
else
  bad "check-version.sh's pattern no longer matches: $plain"
fi
# The build id must not itself look like a version, or the greps above
# would have two candidates and the answer would depend on order.
if printf '%s' "$id1" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+'; then
  bad "the build id contains something shaped like a semver: $id1"
else
  ok "the build id contains nothing shaped like a semver"
fi

# --------------------------------------------------------------------
echo
echo "== stamping does not modify the tree =="
# --------------------------------------------------------------------
# The rewrite happens in a copy. If it ever happened in place, every
# build after the first would report `-dirty` and
# `check-fmt-selfhost.sh` would format the rewrite into the repository.
if grep -q '(pub fn (axiomBuildId) "unstamped")' "$repo_root/self_host/build.ax"; then
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
