#!/usr/bin/env bash
# Assemble every standard-library case for every supported target from a
# single host, at every optimisation level the driver can emit, and
# reject any object that is not position-independent.
#
# The standard library selects syscall numbers by target (see
# `stdlib/Sys/Platform.*.ax`), and the backend emits target-specific
# inline assembly for every syscall. Both fail only on the platform in
# question unless the IR is assembled here, on one machine, for all of
# them. Running the result still needs the real hardware: that is the
# CI matrix's job.
#
# Two properties matter most:
#
#   1. It assembles at `-O0` as well as higher levels. The x86 backend
#      emits an absolute relocation at `-O0` that `-O2` hides, and `-O0`
#      is what `--opt 0` selects.
#
#   2. It inspects relocations rather than only checking that `llc`
#      exited zero. An absolute relocation assembles cleanly and fails
#      later, in the linker, on someone else's machine.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
# The compiler under test, built from the tree. In CI `$axiom` is the
# committed seed's build, which cannot emit a fixture that uses anything
# the seed does not know.
gate_build_axc axc

# Every target the tree's compiler knows. A target can be named here
# before any seed knows it, so every loop over this array drives `$axc`
# and never `$axiom`. The one loop that needs the seed's opinion keeps
# its own list below.
#
# The Windows targets have no syscall template: their runtime calls
# kernel32. The syscall-template sections below check them from the
# other direction. llc must still accept every case at every level,
# which makes a wrong `dllimport` or a mis-typed kernel32 declare
# visible on a host that cannot run the result.
targets=(darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64 freebsd-x86_64 freebsd-aarch64 windows-x86_64 windows-aarch64)

# Optimisation levels the driver assembles with. A relocation bug that
# appears at only one of them is still a shipped bug.
#
# 1 is the default (`driver.ax`: `(flagValue "--opt" 1)`), so it is the
# level every unflagged `axiom run` and `axiom build` uses. 0 is where
# the x86 backend emits `R_X86_64_32S` against `.bss`, the failure this
# script exists for. 2 is the setting recommended for deeply recursive
# code.
opt_levels=(0 1 2)

# Absolute relocations, split by width and by where they are legal. The
# rule is the same on both architectures: `R_AARCH64_ABS64` and its x86
# counterpart `R_X86_64_64` are treated alike.
#
# *Never legal, anywhere.* A 32-bit absolute relocation cannot hold a
# PIE's load address, so no linker can resolve one. This is the class of
# the failure this script exists for: `R_X86_64_32S` against `.bss`,
# emitted from code at `-O0`.
absolute_narrow='R_X86_64_32S|R_X86_64_32|R_AARCH64_ABS32'

# *Never legal in code.* A 64-bit absolute relocation is wide enough to
# hold the address, but text is mapped read-only and shared, so it
# cannot be rewritten at load time.
absolute_wide='R_X86_64_64|R_AARCH64_ABS64'

# In *data* a 64-bit absolute relocation is legal: the static linker
# rewrites each one into an `R_*_RELATIVE` dynamic relocation, which the
# loader applies once. That is what `.data.rel.ro` ("read-only after
# relocation") exists for, and how any language emits a static pointer
# to static data. Axiom needs it for the `{ len, bytes }` header a
# string literal evaluates to. `run-stdlib-tests.sh` runs the same
# header on darwin-aarch64, which is always position-independent.
#
# Sections whose relocations apply to instructions. `llvm-readobj`
# reports these as `.rela.text`, plus any `.rela.text.*` from function
# sections.
code_section_re='^\.rela\.text'

# Classify one object's relocations. Reads `llvm-readobj -r` output on
# stdin and prints one `RELOC in SECTION` line per violation, nothing at
# all for a clean object. It is a function so that `--self-test` below
# can drive it with known input.
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

# Prove the classifier still rejects what it must and accepts only what
# it should. Run as `scripts/check-cross-targets.sh --self-test`. The
# full run does it first, so a rule loosened by accident fails here
# rather than quietly passing every object.
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

  # The failure this script exists for: a 32-bit absolute relocation
  # emitted from code at -O0, against the allocator's `.bss` cursor.
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

  # A static pointer to static data is legal, and both architectures
  # must agree on it.
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

# `llc` needs both backends compiled in, as a stock LLVM has. If one is
# missing, say so rather than reporting it as an Axiom failure.
for arch in AArch64 X86; do
  if ! llc --version | grep -q "$arch"; then
    echo "error: this llc has no $arch backend; cannot verify all targets" >&2
    exit 1
  fi
done

# The relocation check needs `llvm-readobj`. It ships with LLVM, so a
# missing one means a partial install: report it rather than weaken the
# gate.
if ! command -v llvm-readobj > /dev/null 2>&1; then
  echo "error: llvm-readobj not found on PATH; it ships with LLVM alongside llc" >&2
  exit 1
fi

status=0

for case_file in tests/stdlib/*.ax; do
  name="$(basename "$case_file" .ax)"
  for target in "${targets[@]}"; do
    ir="$work/$name.$target.ll"
    if ! "$axc" --target="$target" emit-llvm "$case_file" -o "$ir" > "$work/emit.log" 2>&1; then
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

      # The absolute-relocation question arises only for ELF, which is
      # Linux and FreeBSD alike. Mach-O names its relocations differently
      # and Darwin is always position-independent. On COFF, x86-64 code
      # is RIP-relative, arm64 code addresses through `adrp`/`add` pairs,
      # and a 64-bit absolute in data is rewritten by the loader through
      # the base-relocation table, as `.data.rel.ro` is on ELF.
      if [[ "$target" == linux-* || "$target" == freebsd-* ]]; then
        # Relocations are judged against the section they apply to, so
        # `llvm-readobj`'s output is walked with the current section in
        # hand rather than flattened with `grep -o`. A narrow absolute
        # relocation is rejected wherever it appears, a wide one only in
        # code.
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

# Every inline-asm syscall template must declare the condition-flags
# clobber `~{cc}`. The Darwin kernel answers through the carry flag (the
# templates' own `b.cc`/`jnc` read it). Without the clobber, LLVM can
# schedule a countdown loop's `adds` before the `svc` and its
# flag-consuming branch after it: an infinite loop at every opt level,
# in the shape every clock and polling loop has. Both compilers'
# templates are checked, and compared with each other, because they can
# drift apart silently. The six syscall targets are looped below; the
# two Windows targets, which have no template, follow the loop.
echo "--- syscall templates declare ~{cc} on every target ---"
ccwork="$(mktemp -d)"
trap 'rm -rf "$ccwork"' EXIT
printf '(import Sys)\n(:: main Int)\n;@axiom:effect(io)\n;@axiom:effect(unsafe)\n(fn (main) { (sysWriteFd 1 0 0) 0 })\n' > "$ccwork/cc.ax"
export AXIOM_STDLIB="${AXIOM_STDLIB:-$(pwd)/stdlib}"
# The differential below compares the seed's templates (`$axiom`) with
# the tree's (`$axc`).
#
# This list is not `${targets[@]}`. `$axiom` descends from the seed and
# can emit only the targets the seed knew, so a new target joins this
# list once `scripts/reseed.sh` has minted its seed. Adding it earlier
# fails with "the two compilers emit different syscall templates"
# against an empty `s0.ll`, which names the wrong defect.
cp "$axc" "$ccwork/stage1"
for target in darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64 freebsd-x86_64 freebsd-aarch64; do
  "$axiom" --target="$target" emit-llvm "$ccwork/cc.ax" -o "$ccwork/s0.ll" >/dev/null 2>&1
  # Syscall templates only, not every inline-asm site. The runtime also
  # carries `targetFrameAsm`, one instruction reading x29 or %rbp for
  # the backtracer. It makes no syscall and sets no flags, so `~{cc}` on
  # it would be false. The discriminator is the instruction: `svc` on
  # AArch64, `syscall` on x86-64, the same strings the template
  # comparison below greps for.
  syscall_asm() { grep 'asm sideeffect' "$1" | grep -E '"[^"]*(svc|syscall)[^"]*"'; }
  asms="$(syscall_asm "$ccwork/s0.ll" | grep -c . || true)"
  bare="$(syscall_asm "$ccwork/s0.ll" | grep -vc '~{cc}' || true)"
  if [[ "$asms" -lt 1 ]]; then
    echo "FAIL [$target]: the probe emitted no inline-asm syscall at all (the assertion checked nothing)"
    status=1
  elif [[ "$bare" -gt 0 ]]; then
    echo "FAIL [$target]: $bare inline-asm syscall template(s) lack the ~{cc} clobber"
    status=1
  else
    echo "ok   [$target] $asms syscall template(s) all clobber cc"
  fi
  # And the two compilers must emit the same template, extracted and
  # compared as strings.
  if [[ -x "$ccwork/stage1" ]]; then
    "$ccwork/stage1" --target="$target" emit-llvm "$ccwork/cc.ax" -o "$ccwork/s1.ll" >/dev/null 2>&1
    t0="$(grep -o '"[^"]*svc[^"]*"\|"[^"]*syscall[^"]*"' "$ccwork/s0.ll" | sort -u)"
    t1="$(grep -o '"[^"]*svc[^"]*"\|"[^"]*syscall[^"]*"' "$ccwork/s1.ll" | sort -u)"
    if [[ "$t0" != "$t1" ]]; then
      echo "FAIL [$target]: the two compilers emit different syscall templates"
      # Same `set -e` hazard as the section below: `diff` exits 1 on the
      # difference it is being asked to show.
      { diff <(printf '%s\n' "$t0") <(printf '%s\n' "$t1") || true; } | head -4 | sed 's/^/    /'
      status=1
    fi
  fi
done

# The Windows targets have no syscall ABI: their runtime reaches
# kernel32 by call, so they emit no syscall template and the loop above
# would fail them for the wrong reason. They are checked with a control
# instead, because "no syscall" is also what a broken branch, an empty
# file or a mistyped grep produces:
#
#   * zero `svc`/`syscall` templates in the Windows IR of the probe;
#   * at least one in the IR of the same probe for the Linux target of
#     the same architecture, from the same compiler, through the same
#     `syscall_asm`;
#   * at least three calls to VirtualAlloc, WriteFile or ExitProcess.
#
# The architecture matters on arm64: a Windows target falling through
# `targetSyscallAsm`'s chain would land on an `svc` template, and only
# an `svc`-reading control shows the grep can see one. Only the tree's
# compiler is asked, since the seed refuses these targets' names.
for pair in windows-x86_64:linux-x86_64 windows-aarch64:linux-aarch64; do
  wt="${pair%%:*}"; lt="${pair##*:}"
  if "$ccwork/stage1" --target="$wt" emit-llvm "$ccwork/cc.ax" -o "$ccwork/win.ll" >/dev/null 2>&1 \
     && "$ccwork/stage1" --target="$lt" emit-llvm "$ccwork/cc.ax" -o "$ccwork/lin.ll" >/dev/null 2>&1; then
    win_asms="$(syscall_asm "$ccwork/win.ll" | grep -c . || true)"
    lin_asms="$(syscall_asm "$ccwork/lin.ll" | grep -c . || true)"
    win_k32="$(grep -cE 'call i64 @(VirtualAlloc|WriteFile|ExitProcess)\(' "$ccwork/win.ll" || true)"
    if [[ "$lin_asms" -lt 1 ]]; then
      echo "FAIL [$wt]: the control emitted no syscall template on $lt, so a zero on Windows would mean nothing"
      status=1
    elif [[ "$win_asms" -ne 0 ]]; then
      echo "FAIL [$wt]: $win_asms syscall template(s) in the Windows IR - a target with no syscall ABI emitted one"
      syscall_asm "$ccwork/win.ll" | head -3 | cut -c1-100 | sed 's/^/    /'
      status=1
    elif [[ "$win_k32" -lt 3 ]]; then
      echo "FAIL [$wt]: only $win_k32 kernel32 call(s) in the Windows IR; the runtime's map/write/exit doors are not all there"
      status=1
    else
      echo "ok   [$wt] 0 syscall templates ($lt control: $lin_asms), $win_k32 kernel32 calls in their place"
    fi
  else
    echo "FAIL [$wt]: the syscall-template probe would not emit"
    status=1
  fi
done

# ---------------------------------------------------------------
# An object must not record the path it was assembled from.
#
# Every fixpoint comparison in this repository (`stage2 == stage3` in
# check-bootstrap.sh and bootstrap-from-seed.sh, the reproducibility
# gate) compares objects built from two files. If the assembler records
# where its input came from, those comparisons compare paths instead of
# what the compiler emitted.
#
# On ELF and COFF, `llc` writes the input filename into the object (an
# STT_FILE symbol on ELF, a `.file` symbol on COFF); Mach-O drops it.
# Fixpoint builds therefore assemble files with the same basename in
# different directories. Breaking that fails on ELF and COFF hosts but
# not on Darwin, as "IR matched but their objects differ", with nothing
# wrong in the compiler.
#
# This asserts both halves, and the second keeps the first from being
# vacuous:
#
#   1. the same module assembled from the same basename in different
#      directories gives byte-identical objects, on every target;
#   2. on ELF and COFF the object really does carry that basename. If a
#      future LLVM stops recording it, this fails, and someone removes
#      the assertion knowingly rather than (1) quietly becoming a no-op.
#
# The tree's compiler emits the probe: the seed does not know every
# target, and the subject here is what llc writes.
# ---------------------------------------------------------------
echo "--- an object does not record the path it was assembled from ---"
pework="$(mktemp -d)"
# Each `trap` replaces the one before, so this last one names all three
# directories.
trap 'rm -rf "$pework" "$ccwork" "$work"' EXIT
mkdir -p "$pework/d2" "$pework/d3"
printf '(import Sys)\n(:: main Int)\n;@axiom:effect(io)\n;@axiom:effect(unsafe)\n(fn (main) { (sysWriteFd 1 0 0) 0 })\n' > "$pework/pe.ax"
for target in "${targets[@]}"; do
  if ! "$axc" --target="$target" emit-llvm "$pework/pe.ax" -o "$pework/pe.ll" >/dev/null 2>&1; then
    echo "FAIL [$target]: the path-independence probe would not compile"
    status=1
    continue
  fi
  cp "$pework/pe.ll" "$pework/d2/axc.ll"
  cp "$pework/pe.ll" "$pework/d3/axc.ll"
  llc -filetype=obj -relocation-model=pic "$pework/d2/axc.ll" -o "$pework/d2/axc.o" 2>/dev/null
  llc -filetype=obj -relocation-model=pic "$pework/d3/axc.ll" -o "$pework/d3/axc.o" 2>/dev/null
  # Two objects llc never wrote are byte-identical too, so check the
  # size first.
  size="$(wc -c <"$pework/d2/axc.o" | tr -d ' ')"
  if (( size < 512 )); then
    echo "FAIL [$target]: the probe object is $size bytes - too small to have been assembled"
    status=1
    continue
  fi
  if ! cmp -s "$pework/d2/axc.o" "$pework/d3/axc.o"; then
    echo "FAIL [$target]: two objects from the same basename in different directories differ"
    # `|| true` because `set -e` exempts an `if` condition but not its
    # body: `cmp -l` exits 1 on the difference it prints, so without
    # this the gate would die mid-report and skip the remaining targets.
    # Only an ablation reaches this branch.
    { cmp -l "$pework/d2/axc.o" "$pework/d3/axc.o" || true; } | head -3 | sed 's/^/    /'
    status=1
    continue
  fi
  # Half two. `grep -a` on the object rather than `strings`, which is
  # binutils and may be missing. It greps a file, not a pipeline: under
  # `pipefail`, `grep -q` exiting at its first match can fail the
  # producer, so `if ! producer | grep -q` reads as "no match" exactly
  # when there was one.
  case "$target" in
    linux-*|freebsd-*|windows-*)
      if ! grep -a -q 'axc\.ll' "$pework/d2/axc.o"; then
        echo "FAIL [$target]: this ELF or COFF object no longer records its input filename -"
        echo "     the same-basename convention above is now protecting against nothing."
        echo "     Re-measure, then delete this half deliberately if it is truly gone."
        status=1
      else
        echo "ok   [$target] object records its input name (axc.ll), and same-basename builds still agree ($size bytes)"
      fi ;;
    *)
      echo "ok   [$target] same-basename builds agree ($size bytes; Mach-O records no input name)" ;;
  esac
done

# ---------------------------------------------------------------
# The committed seeds assemble.
#
# `bootstrap/` holds one `.ll` file per target that has a seed, and the
# CI matrix runs on only some of those targets. A SHA256 says the bytes
# are the ones committed, not that `llc` accepts them, so a seed no
# runner assembles (such as `bootstrap/axiom-darwin-x86_64.ll`) could
# go stale unnoticed.
#
# `llc` already has every backend here (the loop above required them),
# so this costs one assemble per seed and needs no runner of that kind.
# Each seed carries its own `target triple`, so llc needs no `-mtriple`.
# ---------------------------------------------------------------
echo "== the committed seeds assemble =="
for seed in "$repo_root"/bootstrap/axiom-*.ll; do
  [[ -f "$seed" ]] || continue
  name="$(basename "$seed" .ll)"
  triple="$(grep -m1 'target triple' "$seed" | sed 's/.*"\(.*\)"/\1/')"
  if [[ -z "$triple" ]]; then
    echo "FAIL [$name]: the seed declares no target triple"
    status=1
    continue
  fi
  if ! llc -filetype=obj -relocation-model=pic "$seed" -o "$work/$name.o" \
       >"$work/$name.llc.log" 2>&1; then
    echo "FAIL [$name]: llc rejects the committed seed ($triple)"
    sed 's/^/    /' "$work/$name.llc.log" | head -5
    status=1
  else
    echo "ok   [$name] the committed seed assembles for $triple"
  fi
done

exit "$status"
