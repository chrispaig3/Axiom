#!/usr/bin/env bash
# Build a compiler that names the tree it was built from.
#
# `axiom version` prints a version and a BUILD ID. The version is a
# promise about an interface; the build id is a fact about bytes, and
# without it two builds of two different trees at one version are the
# same binary to whoever holds one - the half of the roadmap's P6 that
# `scripts/check-version.sh` has named in its header since it was
# written.
#
# WHAT THE ID IS. Two parts, and the first is the load-bearing one:
#
#   <12 hex>            the first twelve characters of
#                       `gate_seed_source_stamp` - a hash of every
#                       `.ax` byte under `self_host/` and `stdlib/`,
#                       and of their paths. This is what distinguishes
#                       trees, and it distinguishes them even when they
#                       are the same commit with an edit in the working
#                       directory, which a commit hash cannot.
#   <commit>[-dirty]    what git says, when git can say anything. This
#                       is a CONVENIENCE - it turns the hash into
#                       something a human can look up - and it is
#                       explicitly not the identity: `-dirty` is
#                       appended when `self_host/` or `stdlib/` has
#                       uncommitted changes, and the whole part is
#                       omitted outside a git checkout, which is what a
#                       release tarball is.
#
# The hash is taken over the tree AS IT STANDS, before the stamp is
# written - so the id names the source you can check out, not the
# scratch copy this script compiles. That is deliberate: a build id
# that included itself would be uncomputable, and one taken after the
# rewrite would name a tree that exists nowhere.
#
# NOTHING IN THE TREE IS MODIFIED. `self_host/` is copied to a scratch
# directory and `build.ax` is rewritten there. That is not tidiness: a
# script that edits a tracked file to build leaves the tree dirty on
# every run, which would make the `-dirty` suffix above true of every
# build after the first, and `check-fmt-selfhost.sh` would format the
# rewrite back into the repository.
#
# Usage:  ./scripts/build-stamped.sh <output-path> [build-id]
#         ./scripts/build-stamped.sh --print-id
#
# The optional second argument overrides the computed id, for a release
# that wants to stamp a tag name. `scripts/check-build-id.sh` uses it
# to prove the stamp is what reaches the binary.
#
# `--print-id` computes the id and prints it WITHOUT building, so the
# gate can check the id's own properties - that it is deterministic,
# that one changed source byte moves it, that a dirty tree says so -
# without paying a ninety-second compiler build for each. The build
# itself is then one assertion rather than four: that this exact string
# is what the binary reports.
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

# The literal this replaces is declared in `self_host/build.ax` and is
# asserted to be there before anything is copied: a `sed` that matches
# nothing is a build that silently ships `unstamped`, which is the one
# outcome this script exists to prevent.
src="$repo_root/self_host/build.ax"
[[ -f "$src" ]] || { echo "FAIL: $src is missing" >&2; exit 1; }
if ! grep -q '(pub fn (axiomBuildId) "unstamped")' "$src"; then
  echo "FAIL: self_host/build.ax no longer holds the literal this rewrites." >&2
  echo "      Looked for: (pub fn (axiomBuildId) \"unstamped\")" >&2
  exit 1
fi
# ...and the id must not contain a `\`, `&` or `"`, which would either
# be eaten by `sed`'s replacement syntax or end the Axiom literal.
case "$id" in
  *'\'*|*'&'*|*'"'*)
    echo "FAIL: the build id contains a character that cannot go in the literal: $id" >&2
    exit 1 ;;
esac

tree="$work/self_host"
cp -R "$repo_root/self_host" "$tree"
sed "s|(pub fn (axiomBuildId) \"unstamped\")|(pub fn (axiomBuildId) \"$id\")|" \
  "$src" > "$tree/build.ax"

echo "== building a compiler stamped \"$id\" =="
if ! AXIOM_STDLIB="$repo_root/stdlib" "$axiom" build \
       --input "$tree/main.ax" --output "$out" >"$work/build.log" 2>&1; then
  sed 's/^/    /' "$work/build.log" | head -20 >&2
  echo "FAIL: could not build the stamped compiler" >&2
  exit 1
fi

# The claim this script makes is about the BINARY, so it asks the
# binary. A stamp that reached the source and not the executable is
# exactly the failure a `sed` guard cannot see.
got="$("$out" version 2>&1 || true)"
if [[ "$got" != *"(build $id)"* ]]; then
  echo "FAIL: the built compiler does not report the stamp." >&2
  echo "      wanted: (build $id)" >&2
  echo "      got:    $got" >&2
  exit 1
fi
printf 'ok   %s\n' "$out"
printf 'ok   %s' "$got"
