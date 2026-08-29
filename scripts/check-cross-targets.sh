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
#      solely at `-O2` made the object look clean, and `-O0` is not a
#      corner case: it is what `--opt 0` selects and what the emitter
#      hands `llc` before any optimisation runs.
#
#   2. It inspects relocations rather than only checking that `llc`
#      exited zero. An absolute relocation assembles perfectly well and
#      fails later, in the linker, on the machine of whoever is not
#      running this script.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
# THE COMPILER UNDER TEST, and it used to be `$axiom` - which in CI is
# what `bootstrap-from-seed.sh` builds from the COMMITTED SEED. What
# this gate asserts is that the EMITTER produces assemblable,
# position-independent code for six targets, so the emitter it asks
# has to be the one in the tree. Asking the seed's had a hard
# consequence rather than a philosophical one: a fixture exercising
# anything the seed does not know could not be emitted here at all, and
# the three recovery-point cases arrived and were refused with
# `undefined variable __axiom_recover` against a tree where they build
# and run. In CI this is a cache hit.
gate_build_axc axc

# Every target the tree's compiler knows. The two FreeBSD targets
# (2026-08-29) are here from the commit that taught `targetCode` their
# names - which is BEFORE any seed knows them, so every loop over this
# array must drive `$axc`, the compiler built from this tree, and not
# `$axiom`. The one loop below that needs the SEED's opinion keeps its
# own literal list of the targets the seed can emit.
targets=(darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64 freebsd-x86_64 freebsd-aarch64)

# Optimisation levels the driver actually assembles with. A relocation
# bug that appears at only one of them is still a shipped bug.
#
# 1 is here because it is the DEFAULT (`driver.ax`: `(flagValue "--opt" 1)`,
# and `--help` says "default 1"), and this list read `(0 2)` under a
# comment claiming the default was 0 - so the level every `axiom run`
# and every `axiom build` without a flag actually uses was the one
# level never assembled here. 0 stays because the original failure this
# script exists for - `R_X86_64_32S` against `.bss` - is emitted only
# at -O0; 2 stays as the setting recommended for deeply recursive code.
opt_levels=(0 1 2)

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

      # Mach-O relocation names differ from ELF's and Darwin is
      # position-independent unconditionally, so the absolute-relocation
      # question only arises for ELF - which is Linux AND FreeBSD. A
      # guard that named only `linux-*` would assemble the FreeBSD
      # objects and never look at their relocations, and the
      # `R_X86_64_32S`-against-`.bss` bug this script exists for is
      # exactly as reachable there.
      if [[ "$target" == linux-* || "$target" == freebsd-* ]]; then
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

# Every inline-asm syscall template must declare the condition-flags
# clobber. The Darwin kernel answers through the CARRY FLAG (the
# templates' own `b.cc`/`jnc` read it), and with no `~{cc}` declared,
# LLVM scheduled a countdown loop's `adds` before the `svc` and its
# flag-consuming branch after - an infinite loop, measured 2026-08-07
# at every opt level, on the shape every clock and polling loop has.
# Checked here because this gate already emits IR for every target;
# both compilers' templates are asserted, since the linux-x86_64 one
# had silently drifted (stage1 matched stage0's stale COMMENT, not its
# string).
echo "--- syscall templates declare ~{cc} on every target ---"
ccwork="$(mktemp -d)"
trap 'rm -rf "$ccwork"' EXIT
printf '(import Sys)\n(:: main Int)\n;@axiom:effect(io)\n(fn (main) { (sysWriteFd 1 0 0) 0 })\n' > "$ccwork/cc.ax"
export AXIOM_STDLIB="${AXIOM_STDLIB:-$(pwd)/stdlib}"
# The differential below is between the SEED's templates and the
# tree's, so it needs both compilers and keeps `$axiom` for one side.
# The other side is `$axc`, which is what a build of `self_host/` by
# `$axiom` produces - this used to build it a second time under its own
# name.
#
# THIS LIST IS NOT `${targets[@]}`, and deliberately: one side of the
# differential is `$axiom`, and `$axiom` is the seed's descendant,
# which can only emit the targets the seed knew. A target added to the
# tree lands here only once `scripts/reseed.sh` has minted its seed -
# the FreeBSD pair wait for that - so this literal list lags the array
# above by exactly one reseed, and a run that widened it early would
# fail with "the two compilers emit different syscall templates"
# against an empty `s0.ll`, naming the wrong defect.
cp "$axc" "$ccwork/stage1"
for target in darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64; do
  "$axiom" --target="$target" emit-llvm "$ccwork/cc.ax" -o "$ccwork/s0.ll" >/dev/null 2>&1
  # SYSCALL templates, not every inline-asm site. The emitted runtime
  # also carries `targetFrameAsm` - one instruction reading x29 or
  # %rbp for the backtracer - which makes no syscall, passes no
  # arguments and sets no flags, so `~{cc}` on it would be a clobber
  # for a condition register it cannot touch. Requiring it there would
  # be requiring a false statement.
  #
  # The discriminator is the instruction, which is what this section is
  # about in the first place: `svc` on AArch64, `syscall` on x86-64.
  # It is the same string the template comparison below greps for, so
  # the two halves of this section now agree on what a syscall
  # template IS. Before this they did not, and the frame read - added
  # the day the backtracer landed - was counted as a syscall template
  # missing its clobber on all four targets.
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
  # And the two compilers must emit the SAME template, extracted and
  # compared as strings: the linux-x86_64 drift lived for months
  # because nothing compared them.
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

# ---------------------------------------------------------------
# An object must not record the path it was assembled from.
#
# Every fixpoint comparison in this repository - `stage2 == stage3` in
# check-bootstrap.sh and bootstrap-from-seed.sh, the reproducibility
# gate - compares artifacts built from two files. If the ASSEMBLER
# records where its input came from, those comparisons compare paths,
# and the compiler is not what decides them.
#
# It does, on ELF: `llc` writes the input path into the object as an
# STT_FILE symbol. Mach-O drops it. That asymmetry ran a whole CI
# outage - `bootstrap-from-seed.sh` assembled `stage2.ll` and
# `stage3.ll` in one directory, so every darwin job was green and
# every Linux job failed with "IR matched but their objects differ",
# for six days, with nothing wrong with the compiler.
#
# So this asserts both halves, and the second is why the first is not
# vacuous:
#
#   1. the same module assembled from the same BASENAME in different
#      directories gives byte-identical objects, on every target;
#   2. on ELF the object really does carry that basename, which is the
#      hazard the convention in (1) exists to defuse. If a future LLVM
#      stops recording it, this fails and someone removes the assertion
#      deliberately, rather than (1) quietly becoming a no-op.
# ---------------------------------------------------------------
echo "--- an object does not record the path it was assembled from ---"
pework="$(mktemp -d)"
# Each earlier section replaced this trap with its own, so the ones
# before it were never cleaned; this last one names all three.
trap 'rm -rf "$pework" "$ccwork" "$work"' EXIT
mkdir -p "$pework/d2" "$pework/d3"
printf '(import Sys)\n(:: main Int)\n;@axiom:effect(io)\n(fn (main) { (sysWriteFd 1 0 0) 0 })\n' > "$pework/pe.ax"
# `$axc`, not `$axiom`: the question is about `llc` and the object it
# writes, not about the seed, and only the tree's compiler can emit a
# target the seed predates. This drove `$axiom` until 2026-08-29, which
# would have failed the day the FreeBSD targets joined `targets` with a
# message - "would not compile" - pointing at the wrong thing.
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
  # `cmp` is happiest when both files are empty; two objects llc never
  # wrote are byte-identical.
  size="$(wc -c <"$pework/d2/axc.o" | tr -d ' ')"
  if (( size < 512 )); then
    echo "FAIL [$target]: the probe object is $size bytes - too small to have been assembled"
    status=1
    continue
  fi
  if ! cmp -s "$pework/d2/axc.o" "$pework/d3/axc.o"; then
    echo "FAIL [$target]: two objects from the same basename in different directories differ"
    # `|| true` because `set -e` does NOT spare the body of an `if`, only
    # its condition: `cmp -l` exits 1 on the difference it was asked to
    # print, so without this the gate dies inside the report and never
    # reaches the remaining targets. Found by running the ablation, which
    # is the only thing that executes this branch.
    { cmp -l "$pework/d2/axc.o" "$pework/d3/axc.o" || true; } | head -3 | sed 's/^/    /'
    status=1
    continue
  fi
  # Half two. `grep -a` on the object rather than `strings`, which is
  # binutils and need not be installed; and grepping a FILE rather than
  # a pipeline, because under `pipefail` a non-zero producer makes
  # `if ! producer | grep -q` read as "no match" exactly when there was
  # one.
  case "$target" in
    linux-*|freebsd-*)
      if ! grep -a -q 'axc\.ll' "$pework/d2/axc.o"; then
        echo "FAIL [$target]: this ELF object no longer records its input filename -"
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
# `bootstrap/` holds one `.ll` file per target that has a seed, and
# until this check the CI matrix assembled exactly the three it runs on: there is
# no macos-13 runner, so `bootstrap/axiom-darwin-x86_64.ll` was verified
# by its SHA256 and by nothing else. A SHA256 says the bytes are the
# bytes somebody committed; it does not say `llc` accepts them. A seed
# that had gone stale for that one target would have been committed
# green and found by whoever next tried to bootstrap on an Intel Mac.
#
# `llc` already has every backend here (the loop above required them),
# so this costs one assemble per seed and needs no runner of that kind.
# Each seed carries its own `target triple`, so `-mtriple` is read from
# the file rather than restated.
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
