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

# Absolute relocations, split by where they are legal.
#
# The distinction is the width, and it is not a nicety - the original
# rule flagged `R_AARCH64_ABS64` everywhere while letting its exact x86
# counterpart `R_X86_64_64` through, so the same construct passed on one
# target and failed on the other.
#
# *Never legal, anywhere.* A 32-bit absolute relocation cannot hold a
# PIE's load address, so no linker can resolve one. This is the class
# that produced the original failure this script exists for:
# `R_X86_64_32S` against `.bss`, emitted from code at `-O0`.
absolute_narrow='R_X86_64_32S|R_X86_64_32|R_AARCH64_ABS32'

# *Never legal in code.* A 64-bit absolute relocation is wide enough to
# hold the address, but text is mapped read-only and shared, so it
# cannot be rewritten at load time.
absolute_wide='R_X86_64_64|R_AARCH64_ABS64'

# In *data* a 64-bit absolute relocation is not a defect, it is the
# mechanism: the static linker rewrites each one into an
# `R_*_RELATIVE` dynamic relocation, which the loader applies once. That
# is what the `.data.rel.ro` section - "read-only after relocation" -
# exists for, and it is how any language emits a static pointer to
# static data. Axiom needs exactly that for the `{ len, bytes }` header
# a string literal evaluates to.
#
# Checked rather than asserted: the same header is emitted on
# darwin-aarch64, which is position-independent unconditionally, and
# `run-stdlib-tests.sh` executes it there on every run.
#
# Sections whose relocations apply to instructions. `llvm-readobj`
# reports these as `.rela.text`, plus any `.rela.text.*` from function
# sections.
code_section_re='^\.rela\.text'

# Classify one object's relocations. Reads `llvm-readobj -r` output on
# stdin and prints one `RELOC in SECTION` line per violation, nothing at
# all for a clean object.
#
# A function rather than an inline pipeline so that `--self-test` below
# can drive it with known input. A gate whose verdict is never itself
# tested is the failure mode this project has already been bitten by.
absolute_violations() {
  awk '
      /^ *Section \([0-9]+\) / { section = $3; next }
      /R_(X86_64|AARCH64)_/ {
        for (i = 1; i <= NF; i++)
          if ($i ~ /^R_(X86_64|AARCH64)_/) { print section, $i; break }
      }
    ' | awk -v narrow="$absolute_narrow" \
           -v wide="$absolute_wide" \
           -v code="$code_section_re" '
      $2 ~ "^(" narrow ")$"            { print $2 " in " $1 }
      $1 ~ code && $2 ~ "^(" wide ")$" { print $2 " in " $1 }
    ' | sort -u
}

# Prove the classifier still rejects what it must, and accepts only what
# it should. Run as `scripts/check-cross-targets.sh --self-test`; the
# full run does it first, so a rule loosened by accident fails here
# rather than by quietly passing every object.
if [[ "${1:-}" == "--self-test" || "${SELF_TEST:-0}" == 1 ]]; then
  self_test_failures=0
  expect() {
    local label="$1" want="$2" input="$3"
    local got
    got="$(printf '%s\n' "$input" | absolute_violations | paste -sd, -)"
    if [[ "$got" != "$want" ]]; then
      echo "SELF-TEST FAIL: $label"
      echo "    expected: '${want}'"
      echo "    got:      '${got}'"
      self_test_failures=$((self_test_failures + 1))
    else
      echo "ok   self-test: $label"
    fi
  }

  # The regression this script was written for: a 32-bit absolute
  # relocation emitted from code at -O0, against the allocator's `.bss`
  # cursor. Must still be caught.
  expect "narrow absolute in code is rejected" \
    "R_X86_64_32S in .rela.text" \
    '  Section (3) .rela.text {
    0x10 R_X86_64_32S .bss 0x0
  }'

  # Narrow is unrepresentable in a PIE wherever it sits, data included.
  expect "narrow absolute in data is rejected" \
    "R_AARCH64_ABS32 in .rela.data.rel.ro" \
    '  Section (6) .rela.data.rel.ro {
    0x8 R_AARCH64_ABS32 .rodata 0x0
  }'

  # Wide absolute in text cannot be fixed up at load time.
  expect "wide absolute in code is rejected" \
    "R_AARCH64_ABS64 in .rela.text" \
    '  Section (3) .rela.text {
    0x10 R_AARCH64_ABS64 .rodata 0x0
  }'

  # The case this rule was relaxed for: a static pointer to static data.
  # Both targets must agree, which is precisely what the old rule got
  # wrong.
  expect "wide absolute in data is accepted (aarch64)" "" \
    '  Section (6) .rela.data.rel.ro {
    0x8 R_AARCH64_ABS64 .rodata.str1.1 0x0
  }'
  expect "wide absolute in data is accepted (x86_64)" "" \
    '  Section (6) .rela.data.rel.ro {
    0x8 R_X86_64_64 .rodata.str1.1 0x0
  }'

  # Ordinary position-independent references stay clean.
  expect "relative and PLT relocations are accepted" "" \
    '  Section (3) .rela.text {
    0xD53 R_X86_64_PC32 .data.rel.ro 0xFFFFFFFFFFFFFFFC
    0xD61 R_X86_64_PLT32 Str$strAlloc 0xFFFFFFFFFFFFFFFC
    0x14 R_AARCH64_ADR_PREL_PG_HI21 .rodata 0x0
  }'

  if [[ $self_test_failures -gt 0 ]]; then
    echo "$self_test_failures self-test failure(s)" >&2
    exit 1
  fi
  echo "self-test passed"
  [[ "${1:-}" == "--self-test" ]] && exit 0
fi

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
        # Relocations are judged against the section they apply to, so
        # `llvm-readobj`'s output is walked with the current section in
        # hand rather than flattened with `grep -o`. `awk` prints
        # `<section> <reloc>` for every entry; the two rules above then
        # decide.
        #
        # A narrow absolute relocation is rejected wherever it appears; a
        # wide one only in code.
        found="$(llvm-readobj -r "$obj" | absolute_violations | paste -sd, -)"
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
