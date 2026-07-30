#!/usr/bin/env bash
# Assemble every standard-library case for every supported target from a
# single host, at every optimisation level the driver can emit, and
# reject any object that is not position-independent.
#
# The standard library selects syscall numbers by target (see
# `stdlib/Sys/Platform.*.ax`), and the backend emits target-specific
# inline assembly for every syscall. Both are the kind of thing that
# only fails on the platform in question - unless the IR is assembled
# here, on one machine, for all of them. Running the result still needs
# the real hardware; that is the CI matrix's job.
#
# Two properties of this script were added after it failed to catch a
# real Linux-only link failure, and both are load-bearing:
#
#   1. It assembles at `-O0` as well as `-O2`. The bug was an absolute
#      relocation that the x86 backend only emits at `-O0`; assembling
#      solely at the default `-O2` made the object look clean. `-O0` is
#      not a corner case - it is what `axiom run` uses.
#
#   2. It inspects relocations rather than only checking that `llc`
#      exited zero. An absolute relocation assembles perfectly well and
#      fails later, in the linker, on the machine of whoever is not
#      running this script.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
[[ -x "$axiom" ]] || cargo build --release
export AXIOM_STDLIB="$repo_root/stdlib"

targets=(darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64)

# Optimisation levels the driver actually assembles with. `axiom run`
# and `axiom build` without `--opt` use 0; `--opt 2` is the recommended
# setting for deeply recursive code. A relocation bug that appears at
# only one of them is still a shipped bug.
opt_levels=(0 2)

# Absolute relocations. Any of these in an object destined for a
# PIE-by-default toolchain - which is every current Linux distribution -
# is a link failure waiting to happen, so they are a hard error here
# rather than a surprise in someone else's build.
absolute_relocs='R_X86_64_32S|R_X86_64_32|R_AARCH64_ABS(32|64)'

# `llc` needs the corresponding backend compiled in. A stock LLVM has
# both AArch64 and X86; if one is missing, say so rather than reporting
# it as an Axiom failure.
for arch in AArch64 X86; do
  if ! llc --version | grep -q "$arch"; then
    echo "error: this llc has no $arch backend; cannot verify all targets" >&2
    exit 1
  fi
done

# The relocation check needs a reader. It ships with LLVM, so if `llc`
# was found and this was not, the installation is partial - which is
# worth reporting rather than silently downgrading the gate.
if ! command -v llvm-readobj > /dev/null 2>&1; then
  echo "error: llvm-readobj not found on PATH; it ships with LLVM alongside llc" >&2
  exit 1
fi

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

    for opt in "${opt_levels[@]}"; do
      obj="$work/$name.$target.O$opt.o"
      if ! llc -filetype=obj "-O$opt" -relocation-model=pic "$ir" -o "$obj" \
        > "$work/llc.log" 2>&1; then
        echo "FAIL $name [$target] -O$opt: llc"
        sed 's/^/    /' "$work/llc.log"
        status=1
        continue
      fi

      # Mach-O relocation names differ from ELF's and Darwin is
      # position-independent unconditionally, so the absolute-relocation
      # question only arises for ELF.
      if [[ "$target" == linux-* ]]; then
        # `grep` exits 1 when it matches nothing, which is the passing
        # case here; without the guard `pipefail` would abort the script
        # on every clean object.
        found="$(llvm-readobj -r "$obj" \
          | { grep -oE "$absolute_relocs" || true; } | sort -u | paste -sd, -)"
        if [[ -n "$found" ]]; then
          echo "FAIL $name [$target] -O$opt: absolute relocation(s): $found"
          echo "    object is not position-independent; it cannot be linked PIE"
          status=1
          continue
        fi
      fi

      echo "ok   $name [$target] -O$opt"
    done
  done
done

exit "$status"
