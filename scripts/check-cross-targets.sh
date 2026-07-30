#!/usr/bin/env bash
# Assemble every standard-library case for every supported target from a
# single host.
#
# The standard library selects syscall numbers by target (see
# `stdlib/Sys/Platform.*.ax`), and the backend emits target-specific
# inline assembly for every syscall. Both are the kind of thing that
# only fails on the platform in question - unless the IR is assembled
# here, on one machine, for all of them. Running the result still needs
# the real hardware; that is the CI matrix's job.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
[[ -x "$axiom" ]] || cargo build --release
export AXIOM_STDLIB="$repo_root/stdlib"

targets=(darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64)

# `llc` needs the corresponding backend compiled in. A stock LLVM has
# both AArch64 and X86; if one is missing, say so rather than reporting
# it as an Axiom failure.
for arch in AArch64 X86; do
  if ! llc --version | grep -q "$arch"; then
    echo "error: this llc has no $arch backend; cannot verify all targets" >&2
    exit 1
  fi
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

status=0

for case_file in tests/stdlib/*.ax; do
  name="$(basename "$case_file" .ax)"
  for target in "${targets[@]}"; do
    ir="$work/$name.$target.ll"
    if ! "$axiom" --target="$target" emit-llvm "$case_file" -o "$ir" > "$work/emit.log" 2>&1; then
      echo "FAIL $name [$target]: emit-llvm"
      sed 's/^/    /' "$work/emit.log"
      status=1
      continue
    fi
    if ! llc -filetype=obj "$ir" -o "$work/$name.$target.o" > "$work/llc.log" 2>&1; then
      echo "FAIL $name [$target]: llc"
      sed 's/^/    /' "$work/llc.log"
      status=1
      continue
    fi
    echo "ok   $name [$target]"
  done
done

exit "$status"
