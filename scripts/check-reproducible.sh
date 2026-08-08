#!/usr/bin/env bash
# Assert that compiling the same source twice produces byte-identical
# output.
#
# Reproducibility is a prerequisite for trusting a self-hosted compiler:
# the bootstrap compares the output of stage N and stage N+1, and that
# comparison is meaningless if two runs of the *same* stage can differ.
# The usual culprits are iteration over a hash map whose order varies per
# process (Rust's `HashMap` is randomly seeded) and embedded timestamps
# or absolute paths.
#
# LLVM IR is compared rather than the linked executable, because the
# system linker embeds a build UUID on macOS that is outside the
# compiler's control.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/.axiom-bin/axiom}"
if [[ ! -x "$axiom" ]]; then
  # No `cargo` here, and none anywhere in this repository's gates: the
  # Rust compiler this used to build has been deleted. A checkout gets
  # a compiler from the committed seed - `bootstrap/axiom-<target>.ll`
  # through `llc` and `cc` - which is the whole point of that directory
  # existing. Set AXIOM to use one you already have.
  echo "no compiler at $axiom - building one from the committed seed" >&2
  "$repo_root/scripts/bootstrap-from-seed.sh" --install "$repo_root/.axiom-bin" >&2 \
    || { echo "FAIL: could not bootstrap a compiler from bootstrap/" >&2; exit 1; }
fi
export AXIOM_STDLIB="$repo_root/stdlib"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

status=0

for case_file in tests/stdlib/*.ax; do
  name="$(basename "$case_file" .ax)"
  # Separate processes, not one process twice: per-process hash seeds are
  # the whole point of the check.
  "$axiom" emit-llvm "$case_file" -o "$work/$name.a.ll" > /dev/null
  "$axiom" emit-llvm "$case_file" -o "$work/$name.b.ll" > /dev/null

  if ! cmp -s "$work/$name.a.ll" "$work/$name.b.ll"; then
    echo "FAIL $name: two runs produced different IR"
    diff "$work/$name.a.ll" "$work/$name.b.ll" | head -40 | sed 's/^/    /' || true
    status=1
    continue
  fi
  echo "ok   $name ($(wc -c < "$work/$name.a.ll" | tr -d ' ') bytes, identical)"
done

exit "$status"
