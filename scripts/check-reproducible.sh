#!/usr/bin/env bash
# Assert that compiling the same source twice produces byte-identical
# LLVM IR.
#
# The bootstrap compares stage N with stage N+1, which means nothing if
# two runs of the same stage can differ. The usual causes are hash-map
# iteration order that varies per process, timestamps and absolute paths.
#
# IR is compared rather than the linked executable because the macOS
# linker embeds a build UUID the compiler does not control.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
# The compiler under test is built from the working tree: the property
# belongs to the emitter the bootstrap ladder compares. A seed-built
# compiler also cannot emit fixtures that use features the seed lacks.
gate_build_axc axc

status=0

# The stdlib cases cover the emitter's everyday shapes. The compiler's
# own entry file covers self-host scale, where a nondeterminism keyed on
# table size would hide from the smaller cases.
for case_file in tests/stdlib/*.ax self_host/main.ax; do
  # `main.ax` would collide with a stdlib case of the same name in
  # `$work`, so its pair is prefixed.
  if [[ "$case_file" == self_host/* ]]; then
    name="selfhost-$(basename "$case_file" .ax)"
  else
    name="$(basename "$case_file" .ax)"
  fi
  # Two separate processes, because per-process hash seeds are what this
  # check is for.
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
