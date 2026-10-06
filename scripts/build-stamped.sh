#!/usr/bin/env bash
# Build a compiler that names the tree it was built from.
#
# `axiom version` prints a version and a build id. The version is a
# promise about an interface. The build id names the source bytes, so
# two builds of different trees at one version can be told apart.
#
# The id has two parts:
#
#   <12 hex>            the first twelve characters of
#                       `gate_seed_source_stamp`, a hash of every `.ax`
#                       byte and path under `self_host/` and `stdlib/`.
#                       This is the identity. It tells trees apart even
#                       when they share a commit and differ only in the
#                       working directory.
#   <commit>[-dirty]    what git says, for a human to look up. `-dirty`
#                       means `self_host/` or `stdlib/` has uncommitted
#                       changes. The part is omitted outside a git
#                       checkout, such as a release tarball.
#
# The hash covers the tree before the stamp is written, so the id names
# source you can check out. An id that covered its own stamp could not
# be computed.
#
# The tree is never modified: `self_host/` is copied to a scratch
# directory and `build.ax` is rewritten there. Editing the tracked file
# would mark every later build `-dirty`, and `check-fmt-selfhost.sh`
# would format the rewrite back into the repository.
#
# Usage:  ./scripts/build-stamped.sh <output-path> [build-id]
#         ./scripts/build-stamped.sh --print-id
#
# The optional second argument overrides the computed id, for a release
# that stamps a tag name. `scripts/check-build-id.sh` uses it to check
# that the stamp reaches the binary.
#
# `--print-id` prints the id without building. The gate uses it to test
# the id's properties (deterministic, moved by one source byte, marks a
# dirty tree) without a ninety-second compiler build for each.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

compute_id() {
  local stamp id commit dirty
  stamp="$(gate_seed_source_stamp "$repo_root")"
  id="${stamp:0:12}"
  if commit="$(git -C "$repo_root" rev-parse --short=12 HEAD 2>/dev/null)"; then
    dirty=""
    if [[ -n "$(git -C "$repo_root" status --porcelain -- self_host stdlib 2>/dev/null)" ]]; then
      dirty="-dirty"
    fi
    id="$id $commit$dirty"
  fi
  printf '%s' "$id"
}

if [[ "${1:-}" == "--print-id" ]]; then
  compute_id
  echo
  exit 0
fi

out="${1:-}"
[[ -n "$out" ]] || { echo "usage: scripts/build-stamped.sh <output-path> [build-id]" >&2; exit 2; }
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac

if [[ -n "${2:-}" ]]; then
  id="$2"
else
  id="$(compute_id)"
fi

# `self_host/build.ax` must hold the literal this replaces: a `sed` that
# matches nothing would silently ship `unstamped`. The formatter puts the
# declaration and its value on two lines, so the guard joins them with
# `N`, as `axv_replace` does for `axiomVersion` in version-sites.sh.
src="$repo_root/self_host/build.ax"
[[ -f "$src" ]] || { echo "FAIL: $src is missing" >&2; exit 1; }
if ! grep -A1 -Fx '(pub fn (axiomBuildId)' "$src" | grep -qFx '  "unstamped")'; then
  echo "FAIL: self_host/build.ax no longer holds the literal this rewrites." >&2
  echo "      Looked for: (pub fn (axiomBuildId) on one line, \`  \"unstamped\")\` on the next" >&2
  exit 1
fi
# The id must not contain `\`, `&` or `"`: `sed`'s replacement syntax
# would eat them, or they would end the Axiom literal.
case "$id" in
  *'\'*|*'&'*|*'"'*)
    echo "FAIL: the build id contains a character that cannot go in the literal: $id" >&2
    exit 1 ;;
esac

tree="$work/self_host"
cp -R "$repo_root/self_host" "$tree"
sed "/(pub fn (axiomBuildId)/{N;s/\"unstamped\")/\"$id\")/;}" \
  "$src" > "$tree/build.ax"

echo "== building a compiler stamped \"$id\" =="
if ! AXIOM_STDLIB="$repo_root/stdlib" "$axiom" build \
       --input "$tree/main.ax" --output "$out" >"$work/build.log" 2>&1; then
  sed 's/^/    /' "$work/build.log" | head -20 >&2
  echo "FAIL: could not build the stamped compiler" >&2
  exit 1
fi

# Ask the binary itself: a stamp that reached the source but not the
# executable is a failure the `sed` guard cannot see.
got="$("$out" version 2>&1 || true)"
if [[ "$got" != *"(build $id)"* ]]; then
  echo "FAIL: the built compiler does not report the stamp." >&2
  echo "      wanted: (build $id)" >&2
  echo "      got:    $got" >&2
  exit 1
fi
printf 'ok   %s\n' "$out"
printf 'ok   %s' "$got"
