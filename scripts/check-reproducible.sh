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

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
# THE COMPILER UNDER TEST. This took `$axiom` - in CI, what
# `bootstrap-from-seed.sh` builds from the committed seed - so it
# asserted that a compiler nobody ships is deterministic. The property
# belongs to the emitter in the tree, which is what the bootstrap
# ladder compares stage against stage. It also had a hard consequence:
# a fixture exercising anything the seed does not know could not be
# emitted here at all.
gate_build_axc axc

status=0

for case_file in tests/stdlib/*.ax; do
  name="$(basename "$case_file" .ax)"
  # Separate processes, not one process twice: per-process hash seeds are
  # the whole point of the check.
  "$axc" emit-llvm "$case_file" -o "$work/$name.a.ll" > /dev/null
  "$axc" emit-llvm "$case_file" -o "$work/$name.b.ll" > /dev/null

  if ! cmp -s "$work/$name.a.ll" "$work/$name.b.ll"; then
    echo "FAIL $name: two runs produced different IR"
    diff "$work/$name.a.ll" "$work/$name.b.ll" | head -40 | sed 's/^/    /' || true
    status=1
    continue
  fi
  echo "ok   $name ($(wc -c < "$work/$name.a.ll" | tr -d ' ') bytes, identical)"
done

exit "$status"
