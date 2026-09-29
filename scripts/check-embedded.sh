#!/usr/bin/env bash
# ---------------------------------------------------------------------
# The arena's - and now the trap path's - assumptions about a hosted
# operating system, removed and gated, plus the reference port's
# device leg. docs/embedded-proposal.md 4.1, 4.2, 4.3 and 6, and the
# gate its section 8 names for all four rows.
#
# WHAT THE THREE ITEMS ARE. The emitted allocator asked the kernel for a
# MEGABYTE the first time a program allocated, and `mmap` was the only
# way a chunk could ever arrive. On a Cortex-M4-class part with 192 KiB
# of SRAM the first allocation fails, and there is no `mmap` for it to
# fail in. So:
#
# WHAT THE TWO ITEMS ARE. The emitted allocator asked the kernel for a
# MEGABYTE the first time a program allocated, and `mmap` was the only
# way a chunk could ever arrive. On a Cortex-M4-class part with 192 KiB
# of SRAM the first allocation fails, and there is no `mmap` for it to
# fail in. So:
#
#   4.1  the chunk size is a per-target constant, `targetArenaChunkBytes`,
#        beside the syscall numbers in `self_host/codegen.ax`'s target
#        table - not the literal `1048576` written twice into
#        `emitAllocator`.
#   4.2  the source of pages is a per-target STRATEGY. Zero from
#        `targetArenaStaticBytes` means `mmap` (or `VirtualAlloc`);
#        non-zero means a single statically reserved region that
#        `emitArenaCarve` bumps a cursor through. `emitRuntimeMap`
#        branches on it once, at EMISSION time, so the emitted program
#        contains exactly one of the two and the other costs it nothing,
#        not even a branch.
#   4.3  the trap's write is a per-target STRATEGY. Zero from
#        `targetTrapSilent` means today's `write(2, ...)` (or
#        `WriteFile`); non-zero means no write at all, while the abort,
#        the backtrace walk and the exit with the trap's own status all
#        still run. `emitRuntimeWrite` - the single door the backtrace
#        writer delegates to - branches on it once, at EMISSION time,
#        so a silent program carries a comment where each write was and
#        no branch for one.
#
# THE CONSTRAINT THAT DECIDES WHETHER THIS IS CORRECT is that it is a
# REFACTOR for every supported target and a new capability only for a
# bare-metal one. Every supported target answers 1 MiB and `mmap`, so
# every supported target must emit the bytes it has always emitted -
# `check-mir.sh` asserts `emit-llvm` byte-identity for its own routing
# and would go red if this moved one, which would be the right red.
# A1 pins those bytes per target; A3 recomputes the three figures
# section 2 of the proposal prices the whole port against.
#
# WHY A VARIANT COMPILER, AND WHY THAT IS NOT A DODGE. No supported
# target declares a small chunk or a static arena - that is the whole
# content of "this moves nothing for a hosted target" - so a gate that
# ran only the tree's compiler could assert that the literals had been
# REMOVED and nothing whatever about what replaced them. That is the
# shape of a check that cannot fail. A4/A5/A6 therefore build a second
# compiler from a copy of `self_host/` with two rows of the target table
# changed, which is exactly the edit a bare-metal port makes and nothing
# more:
#
#   * one target that is NOT the host gets a 4 KiB chunk. Its IR must
#     move in exactly the lines that carry the constant, and the targets
#     neither row touches must not move a byte. That is 4.1 stated as a
#     difference rather than as an absence.
#   * the HOST target gets a 256 KiB static arena, so the result can be
#     LINKED AND RUN here. A static arena is not bare-metal-only: it is
#     a `.bss` array and a cursor, which a hosted OS runs perfectly
#     well, and running it is what turns 4.2 from an emission into a
#     fact. A6 runs one program that fits and one that does not, and
#     requires the same answer as the `mmap` arena for the first and
#     status 70 for the second.
#   * A9 builds a THIRD compiler, silent on the host, for the same
#     reason: a no-op trap write runs perfectly well here, and running
#     it is what turns 4.3 from an emission into the statuses it keeps.
#
# WHAT IT ASSERTS.
#   A1  SEVEN TARGETS EMIT TODAY'S ALLOCATOR. Every supported target's
#       IR carries the four chunk lines, and the keep helper carries the
#       two grain lines, with the values they had before 4.1 - 1 MiB and
#       64 KiB.
#   A2  THE SOURCE HAS ONE SPELLING OF IT. `1048576` appears in
#       `codegen.ax` exactly once, in the table. A second spelling is a
#       target that cannot move its own chunk size, which is the defect
#       4.1 exists to remove.
#   A3  THE MEASURED BASELINE, RECOMPUTED. The minimal program imports
#       nothing but the platform's own startup set, makes EXACTLY THREE
#       distinct syscalls, and on the format the proposal measured - a
#       Mach-O - its size is inside the proposal's flash budget. Those
#       are section 2's figures and the port is priced on them. The
#       import set is per FORMAT (a Mach-O imports nothing, an ELF
#       carries crt1's startup hooks), and the file size is per LINKER:
#       the identical program is 16,416 bytes from gcc and ld.bfd and
#       71,168 from clang and lld, so on ELF and PE it is printed and
#       not gated - see the paragraphs at A3 for both lessons, each of
#       which was a red leg first.
#   A4  4.1 - ONE TARGET MOVES AND THE REST DO NOT. Every line that
#       differs is one of the pairs the constant reaches, and the
#       untouched targets are byte-identical.
#   A5  4.2 - THE STATIC TARGET EMITS THE OTHER STRATEGY. Region,
#       cursor, end and carve present; NO `mmap`; three distinct
#       syscalls become two; and the trap names the strategy that ran
#       out. Against a control - the same probe, the same target, the
#       tree's own compiler - which must show the opposite of every one
#       of those, because "the static build has no mmap" means nothing
#       unless the other build has one.
#   A6  4.2 - AND IT RUNS. A program that fits in the region prints what
#       the `mmap` build of the same source prints; a program that does
#       not exits 70 with the arena's sentence, while the `mmap` build
#       of THAT source exits 0 - so the 70 is the region's verdict and
#       not the program's size.
#   A7  THE CEILING FLAG: the same verdicts without a variant compiler.
#       `--heap-ceiling N` on a SUPPORTED target carves N bytes from a
#       `.bss` region instead of the kernel's pages - the 4.2 strategy
#       selected per build rather than per target. The fitting program
#       answers as the `mmap` build does, the overflowing one exits 70
#       with the arena's sentence against a control that exits 0, the
#       emitted IR carries the region at the asked size with the chunk
#       capped by it and no `mmap`, and the flag's own refusals
#       (non-numeric, zero, missing value, `--threads` on a spawning
#       program) each go red when broken.
#   A8  4.3 - EVERY SUPPORTED TARGET WRITES ITS TRAPS. A dividing
#       probe carries one fd-2 write per trap and backtrace line on
#       every target (the error handle's, on Windows), and the silent
#       strategy's default is one row answering 0.
#   A9  4.3 - AND SILENCE TRAPS CORRECTLY. A second variant compiler,
#       silent on the host, suppresses exactly the lines A8 counts and
#       no others; both binaries exit 72, the tree's naming the
#       division on fd 2 and the silent one's fd 2 empty.
#   A10 SECTION 6 - BLINK UNDER QEMU. The fixtures in
#       `tests/embedded/` built for `baremetal-aarch64` and booted
#       under `qemu-system-aarch64 -machine virt`: blink's UART bytes
#       must equal the host build's stdout byte for byte with the
#       same exit status, and the oversized ablation must exit with
#       the status `tests/stdlib/314-out-of-memory.exit` pins against
#       a control that exits 0. Skips loudly when the target has not
#       landed or QEMU is not on PATH, and for no other reason.
#   A11 THE DEVICE PRIMITIVES, COMPILE-ONLY (docs/memory-model.md
#       MM-FFI-8). Each volatile width is its own `load/store volatile
#       iN` at natural alignment; the writes survive `opt -O2` where a
#       control's plain double write does not; `llc` keeps each width;
#       every `__arm_` primitive is its instruction; and AX4008 draws
#       the target line. Needs no QEMU, so it runs on every host.
#   A12 THE EXCEPTION VECTOR TABLE. Every bare-metal executable
#       carries one and `_start` installs it; an unbound vector exits
#       81 with the fault's registers on the UART, `isr(irq)` wires
#       the IRQ slot, AX4008 refuses a binding no target honours.
#       IR-level on every host; `tests/embedded/fault.ax` under QEMU.
#   A13 A PERIODIC WORKLOAD ON THE TIMER'S INTERRUPT.
#       `tests/embedded/periodic.ax`: the restricted profile refuses
#       nothing across the whole program and bounds its stack under a
#       2 KiB budget, on every host; under QEMU, twenty steps run on
#       twenty real timer interrupts through the GICv2 and equal the
#       straight run. Drill: the handler's end-of-interrupt write
#       deleted, and the guest must not finish.
#   A14 A DRIVER WITH INTERRUPT AND DMA OWNERSHIP BOUNDARIES.
#       `tests/embedded/dma.ax` reads fw_cfg's file directory by DMA
#       under an explicit CPU/device ownership protocol and a timer
#       deadline, and the DMA copy must equal the data register's.
#       Drills: a read while the device owns the buffer must trap 80
#       (the contract), and a transfer never started must end at the
#       deadline, not hang.
#
# SKIPS. A12-A14's QEMU legs print SKIP, count as skipped and never as
# ok, and the summary says how many. CI runners have no QEMU, so there
# they skip - which is said, not passed.
#
# ABLATIONS. `AXIOM_ABLATE=<name>` copies `self_host/` to a scratch
# directory, breaks ONE thing in `codegen.ax` there, builds every
# compiler this gate uses from the broken copy, and the gate must FAIL.
# The patch is applied by exact string match by
# `scripts/lib/embedded-patch.py`, which ABORTS if the string is not
# there: an ablation that silently does not apply is a drill proving the
# gate can pass. `--ablations` runs all thirteen and requires each to go red.
#
#   chunk     every target answers 4 KiB                   -> A1
#   literal   `refill:` goes back to the hardcoded 1 MiB   -> A2, A4
#   grain     the grain stops following the chunk          -> A4
#   strategy  `emitRuntimeMap` ignores the static arena    -> A5
#   cursor    the carve never advances its cursor          -> A6
#   oomsig    the carve never answers 0, so exhaustion is
#             never seen                                   -> A6
#   ceiling   the flag is never read, so a ceiling build is a
#             mmap build in disguise                      -> A7
#   trapwrite the silent branch never fires, so a silent
#             target still writes                          -> A9
#   allsilent every target is silent, so the supported
#             targets stop emitting their trap writes      -> A8
#   volatile  both device emitters drop `volatile`         -> A11
#   barrier   `__arm_dmb` lowers to a `nop`                -> A11
#   refusal   every target may run every primitive, so
#             nothing is refused as AX4008                 -> A11
#   vbar      `_start` no longer points VBAR_EL1 at the
#             table, so a fault is a hang again            -> A12
#
# WHAT THIS GATE DOES NOT COVER, said here rather than left to be
# discovered: the board itself. The bare-metal TARGET is in the tree -
# triple, `Sys/Platform.baremetal-aarch64.ax`, linker script - and
# A10 boots it under QEMU, UART bytes, exit status and the 70 all
# asserted - but `qemu-system-aarch64 -machine virt` is an emulator
# and not hardware, and where it is not on PATH the leg skips loudly.
# 4.4 and 4.5 are done under their own gates
# (`check-nostd-subset.sh`, `check-isr.sh`).
#
# Usage:
#   scripts/check-embedded.sh              # the gate
#   scripts/check-embedded.sh --ablations  # the thirteen drills, each red
#   AXIOM_ABLATE=literal scripts/check-embedded.sh
# ---------------------------------------------------------------------

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
# `imports_of` - the undefined-symbol reader that dispatches on the
# object's own magic (MZ, ELF, Mach-O) rather than on the host. A3 uses
# it; see the paragraph there for why the host is the wrong thing to
# dispatch on.
source "$(dirname "${BASH_SOURCE[0]}")/lib/imports.sh"

# WHAT THE PLATFORM'S OWN STARTUP PUTS IN AN EXECUTABLE, and nothing
# else may appear beside it in A3.
#
# Enumerated rather than counted, because "six imports" is satisfied by
# any six and this must fail when the runtime pulls in a seventh - or
# when one of these six is replaced by `malloc`. It is the same shape
# `scripts/platform-allow.windows.txt` takes for the same reason
# (`docs/memory-model.md` MM-FFI-5: enumerate what is permitted, do not
# forbid a list of names somebody has to keep up to date).
#
# The four `_ITM_*`/`__gmon_start__`/`__cxa_finalize` entries are weak
# crt hooks glibc's crt1 references and no allocator can reach; the two
# real ones are `__libc_start_main`, which calls `main`, and `abort`,
# which crt1 references from its own stack-guard path. None is a libc
# function the compiler could emit a call to - `check-freestanding.sh`
# holds that line separately, over the IR, where a call would appear
# before the linker ever ran.
#
# On Mach-O this list matches nothing and A3's count stays 0.
crt_startup='_ITM_deregisterTMCloneTable|_ITM_registerTMCloneTable|__gmon_start__'
crt_startup="$crt_startup"'|__cxa_finalize|__libc_start_main|abort'

# --ablations re-enters this script once per drill, before gate_init, so
# the drills do not share a work directory with each other.
if [[ "${1:-}" == "--ablations" ]]; then
  self="${BASH_SOURCE[0]}"
  red=0
  ran=0
  for ab in chunk literal grain strategy cursor oomsig ceiling trapwrite allsilent \
            volatile barrier refusal vbar; do
    ran=$((ran + 1))
    echo "== ablation: $ab =="
    if AXIOM_ABLATE="$ab" bash "$self" > "/tmp/embedded-ablate-$ab.log" 2>&1; then
      echo "FAIL ablation '$ab' left the gate GREEN - it checks nothing about this."
    elif grep -q '^ *ABORT' "/tmp/embedded-ablate-$ab.log"; then
      # A drill whose patch did not apply exits non-zero and would
      # otherwise be counted as a success - the exact shape of a check
      # that cannot fail, in the code whose job is to prove this one
      # can.
      grep -E '^ *ABORT' "/tmp/embedded-ablate-$ab.log" | head -3 | sed 's/^/     /'
      echo "FAIL ablation '$ab' never applied, so it drilled nothing. Re-anchor it."
    else
      red=$((red + 1))
      grep -E '^(FAIL|ABORT)' "/tmp/embedded-ablate-$ab.log" | head -4 | sed 's/^/     /'
      echo "  ok   red, for the reason above"
    fi
  done
  echo
  if (( red != ran )); then
    echo "check-embedded --ablations: $((ran - red)) of $ran drills did not go red"
    exit 1
  fi
  echo "check-embedded --ablations: $ran of $ran drills went red"
  exit 0
fi

gate_init

failed=0
checks=0
# A SKIP is its own word and its own count, never a pass: A12-A15 skip
# where QEMU is not on PATH - every CI runner today - and the summary
# says how many did, so a green run that booted nothing reads as one.
skipped=0
note() { echo "ok   $1"; }
bad()  { echo "FAIL $1"; failed=$((failed + 1)); }
skip() { echo "SKIP $1"; skipped=$((skipped + 1)); }
abort() { echo "ABORT: $1" >&2; exit 1; }

# ---------------------------------------------------------------------
# The tree under test: the working one, or a scratch copy with one thing
# broken in it. The ablated tree is what BOTH compilers below are built
# from, so a drill is visible on both sides of every comparison.
# ---------------------------------------------------------------------
src_root="$repo_root"
if [[ -n "${AXIOM_ABLATE:-}" ]]; then
  mkdir -p "$work/tree"
  cp -a "$repo_root/self_host" "$work/tree/self_host"
  python3 "$repo_root/scripts/lib/embedded-patch.py" \
    "$AXIOM_ABLATE" "$work/tree/self_host/codegen.ax" || exit 1
  src_root="$work/tree"
  echo "== building the compiler under test from the ABLATED tree =="
  if ! gate_build_tree "$axiom" "$src_root" "$AXIOM_STDLIB" "$work/axc-abl" \
        > "$work/ablbuild.log" 2>&1; then
    # A drill that makes the compiler fail to BUILD is still a non-zero
    # exit, but it is red for the wrong reason and would hide whether
    # the assertion it aims at can fail. Say which it was.
    echo "FAIL the ablated tree does not build a compiler, so this drill breaks the"
    echo "     build rather than the emitter and says nothing about the assertion."
    sed 's/^/    /' "$work/ablbuild.log" | head -12
    exit 1
  fi
  axc="$work/axc-abl"
else
  gate_build_axc axc
fi

# ---------------------------------------------------------------------
# The seven targets, and their codes READ FROM `targetCode` rather than
# restated here. A list this gate typed out itself would go stale beside
# the table it is about, and the variant edit below is written in terms
# of the codes.
# ---------------------------------------------------------------------
targets=(darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64 freebsd-x86_64 freebsd-aarch64 windows-x86_64)

codes_raw="$(python3 - "$src_root/self_host/codegen.ax" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
i = src.index("(pub fn (targetCode name)")
body = src[i:i + 2000]
for name, code in re.findall(r'\(strEq name "([a-z0-9_-]+)"\)\s*\n\s*(\d+)', body):
    print("%s %s" % (name, code))
PY
)"
n_codes=$(printf '%s\n' "$codes_raw" | grep -c . || true)
if (( n_codes != 8 )); then
  abort "read $n_codes target codes out of targetCode, expected 8 - the parse broke,
       and every assertion below is written in terms of those codes."
fi
code_of() { printf '%s\n' "$codes_raw" | awk -v n="$1" '$1==n{print $2}'; }
# The eighth code is the bare-metal port's, and it is pinned here: the
# seven loops below still cover the supported hosted targets only, so a
# bare-metal row that moved a hosted target's bytes would pass them all.
[[ "$(code_of baremetal-aarch64)" == "7" ]] \
  || abort "baremetal-aarch64 is not code 7 in targetCode"

# The host, so that A6 can LINK AND RUN what A5 emits.
case "$(uname -s)" in
  Darwin)  host_os=darwin ;;
  Linux)   host_os=linux ;;
  FreeBSD) host_os=freebsd ;;
  *)       abort "unknown host OS $(uname -s); this gate runs a binary it builds." ;;
esac
case "$(uname -m)" in
  arm64|aarch64) host_arch=aarch64 ;;
  x86_64|amd64)  host_arch=x86_64 ;;
  *)             abort "unknown host arch $(uname -m)" ;;
esac
host_target="$host_os-$host_arch"
host_code="$(code_of "$host_target")"
[[ -n "$host_code" ]] || abort "the host target $host_target is not in targetCode"

# 4.1's witness is a target that is NOT the host, so the two rows the
# variant sets never land on one target and the targets that are left
# really are untouched.
t41=""
for t in "${targets[@]}"; do
  [[ "$t" == "$host_target" ]] && continue
  t41="$t"; break
done
code41="$(code_of "$t41")"
[[ -n "$code41" ]] || abort "no non-host target to use as 4.1's witness"
echo "gate: host is $host_target (code $host_code); 4.1's witness is $t41 (code $code41)"

# ---------------------------------------------------------------------
# The probes. Two are written here and one is a fixture already in the
# tree, because a fixture is a file the `.ax` census counts and these
# two need to exist only while the gate runs.
#
# `min.ax` is section 2's minimal program, verbatim. `165-arena-keep.ax`
# is the case in the corpus that makes the emitter write
# `__axiom_arena_reset_keeping_fn`, which is the arena's SECOND
# allocation path and carries the second copy of the grain - without it
# A1 and A4 would cover one of the two sites.
# ---------------------------------------------------------------------
printf '(:: main Int)\n\n(fn (main) 0)\n' > "$work/min.ax"
keep_probe="$repo_root/tests/stdlib/165-arena-keep.ax"
[[ -f "$keep_probe" ]] || abort "$keep_probe is gone; the second grain site has no probe."

# A program that allocates across many chunks and answers a number that
# depends on every block it allocated: 100 blocks of 512 bytes is 52,800
# bytes, which is fifteen 4 KiB chunks and comfortably inside a 256 KiB
# region. The sum of 1..100 is 5050, and it is wrong if any block was
# handed out twice.
cat > "$work/fit.ax" <<'AX'
(import IO)

(import Mem)

(pub :: chain (-> Int Int Int))

;@axiom:effect(unsafe)
(pub fn (chain n acc)
  (if (<= n 0)
    acc
    (let ((p (memAlloc 512)))
      {
        (memSetWord p 0 n)
        (chain (- n 1) (+ acc (memGetWord p 0)))
      }
    )
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println (chain 100 0))
    0
  }
)
AX
# The same program asking for 2,000 blocks - 1,056,000 bytes, which does
# not fit in a 256 KiB region and does fit in `mmap`'s megabytes. The
# sum of 1..2000 is 2,001,000.
sed 's/(chain 100 0)/(chain 2000 0)/' "$work/fit.ax" > "$work/oom.ax"

emit() {  # emit <compiler> <target> <source> <out> [extra flags...]
  local comp="$1" targ="$2" src="$3" out="$4"; shift 4
  "$comp" --target="$targ" "$@" emit-llvm "$src" -o "$out" > "$work/emit.log" 2>&1
}

# The distinct syscall numbers an emitted program uses. The number is
# the first argument after the constraint string's closing quote, which
# is where every `asm sideeffect` syscall this emitter writes puts it -
# and the two inline-asm sites that are NOT syscalls (the recover jump,
# the backtracer's frame read) pass a register or nothing there, so they
# fall out of the match rather than having to be excluded by name.
#
# The number is cut off the front with `sed` rather than pulled out with
# a second `grep -oE '[0-9]+'`, because a second grep also finds the
# `64` in `i64`: the first run of this gate reported FOUR distinct
# syscalls for the minimal program - 64, 33554433, 33554436, 33554629 -
# and would have been "fixed" by relaxing the assertion from three to
# four, which is the shape of a check drifting to match its own bug.
syscall_nums() { grep 'asm sideeffect' "$1" | grep -o '"(i64 [0-9][0-9]*' | sed 's/^"(i64 //' | sort -un; }

CHUNK_BIG='  %big = icmp ugt i64 %need, 1048576'
CHUNK_R0='  %rounded0 = add i64 %need, 65535'
CHUNK_RD='  %rounded = and i64 %rounded0, -65536'
CHUNK_SEL='  %chunk = select i1 %big, i64 %rounded, i64 1048576'
KEEP_WANT='  %want = and i64 %rounded0, -65536'

# ---------------------------------------------------------------------
echo "== A1. every supported target emits the allocator it always did =="
# ---------------------------------------------------------------------
for t in "${targets[@]}"; do
  checks=$((checks + 1))
  if ! emit "$axc" "$t" "$work/min.ax" "$work/min.$t.ll"; then
    bad "[$t] emit-llvm failed for the minimal program"
    sed 's/^/    /' "$work/emit.log" | head -6
    continue
  fi
  lines=$(wc -l < "$work/min.$t.ll" | tr -d ' ')
  if (( lines < 400 )); then
    # A truncated or empty file satisfies every grep below by containing
    # none of the wrong lines either.
    bad "[$t] the minimal program emitted $lines lines; it was 569 on 2026-09-04"
    continue
  fi
  miss=""
  for want in "$CHUNK_BIG" "$CHUNK_R0" "$CHUNK_RD" "$CHUNK_SEL"; do
    n=$(grep -Fxc -- "$want" "$work/min.$t.ll" || true)
    [[ "$n" == "1" ]] || miss="$miss
       $n x |$want|"
  done
  if [[ -n "$miss" ]]; then
    bad "[$t] the refill block is not what it was ($lines lines of IR):$miss"
  else
    note "[$t] refill asks for 1 MiB and rounds to 64 KiB, as it always has"
  fi
done

checks=$((checks + 1))
if emit "$axc" "$host_target" "$keep_probe" "$work/keep.ll"; then
  k2=$(grep -Fxc -- "$KEEP_WANT" "$work/keep.ll" || true)
  kh=$(grep -c '__axiom_arena_reset_keeping_fn' "$work/keep.ll" || true)
  if (( kh < 1 )); then
    bad "165-arena-keep.ax no longer emits the keep helper, so the arena's SECOND
     allocation path is not covered here at all"
  elif [[ "$k2" != "1" ]]; then
    bad "the keep helper's grain moved: $k2 x |$KEEP_WANT|"
  else
    note "the keep helper rounds a fresh mapping to 64 KiB, as it always has"
  fi
else
  bad "emit-llvm failed for $keep_probe"
fi

# ---------------------------------------------------------------------
echo "== A2. the chunk size has exactly one spelling in the source =="
# ---------------------------------------------------------------------
checks=$((checks + 1))
# COMMENT LINES ARE NOT SPELLINGS. The paragraph above the table says
# what the literal used to be and what a bare-metal row looks like, and
# both name the number; counting those made this read 3 on its first
# run. What the check is about is a second place the emitter could take
# the value FROM, so the count is over lines that are not comments.
n_lit=$(grep -v '^[[:space:]]*;' "$src_root/self_host/codegen.ax" | grep -c '1048576' || true)
if [[ "$n_lit" != "1" ]]; then
  bad "\`1048576\` appears $n_lit times in codegen.ax; it must appear once, in
     targetArenaChunkBytes. A second spelling is a target that cannot move its
     own chunk size, which is what 4.1 exists to remove:"
  grep -n '1048576' "$src_root/self_host/codegen.ax" | grep -v ':[[:space:]]*;' | head -5 | sed 's/^/       /'
else
  note "\`1048576\` is written once, in the target table"
fi

# ---------------------------------------------------------------------
echo "== A3. the minimal program's measured baseline, recomputed =="
# ---------------------------------------------------------------------
checks=$((checks + 1))
if ! "$axc" build --input "$work/min.ax" --output "$work/min" --opt 2 > "$work/build.log" 2>&1; then
  bad "the minimal program does not build at --opt 2"
  sed 's/^/    /' "$work/build.log" | head -10
else
  size=$(wc -c < "$work/min" | tr -d ' ')
  # THE CLAIM IS "NOTHING BUT THE PLATFORM'S OWN STARTUP", NOT "ZERO",
  # and until 2026-09-04 this arm said zero. Zero is a DARWIN fact: a
  # Mach-O executable that calls no libc function imports no symbol at
  # all, so `nm -u` is empty and the number read like a property of the
  # runtime. It is a property of the object format. On Linux the same
  # program imports SIX symbols by construction - four weak crt hooks
  # (`_ITM_deregisterTMCloneTable`, `_ITM_registerTMCloneTable`,
  # `__gmon_start__`, `__cxa_finalize`) and two real ones
  # (`__libc_start_main`, `abort`) - because `cc` links crt1, and both
  # Linux legs went red for a program behaving exactly as intended.
  #
  # This is the SECOND time that exact sentence has been written in this
  # repository. `check-thread-local.sh` asserted `nm -u` was empty for a
  # program that spawns no thread, failed on the same six symbols, and
  # its header now records the lesson; `scripts/run-gates-linux.sh`
  # exists because of it. This gate was written on a Mac and encoded the
  # same assumption anyway, which is what that script is for and why it
  # is run before a push rather than after.
  #
  # So the assertion is the one the proposal is actually about: the
  # minimal program imports NO LIBC FUNCTION and nothing the platform's
  # own startup did not put there. `imports_of` is
  # `check-freestanding.sh`'s reader, shared through `lib/imports.sh`;
  # it dispatches on the object's own magic rather than on the host, and
  # strips ELF's `@GLIBC_2.34` versions and Mach-O's leading underscore
  # - the one edit each convention requires. On Darwin the permitted set
  # matches nothing, the count stays 0, and this arm asserts exactly
  # what it asserted before.
  imports_of "$work/min" | LC_ALL=C sort > "$work/min.imports"
  undef=$(grep -c . "$work/min.imports" || true)
  stray="$(grep -vE "^($crt_startup)$" "$work/min.imports" || true)"
  n_stray=$(printf '%s' "$stray" | grep -c . || true)
  scn="$(syscall_nums "$work/min.$host_target.ll" | tr '\n' ' ')"
  nsc=$(syscall_nums "$work/min.$host_target.ll" | grep -c . || true)
  echo "     size $size bytes, $undef import(s) ($n_stray outside the platform's startup set), syscalls: $scn"
  ok=1
  if (( n_stray != 0 )); then
    bad "the minimal program imports $n_stray symbol(s) that are not the platform's own startup:"
    printf '%s\n' "$stray" | sed 's/^/       /'
    ok=0
  fi
  if [[ "$nsc" != "3" ]]; then
    bad "the minimal program makes $nsc distinct syscalls, not 3 (mmap, write, exit).
     Section 2 calls the three the whole of it, and the port is priced on that."
    ok=0
  fi
  # A budget, not a golden, and the reason is worth stating because the
  # obvious alternative is an equality. Section 2 measured 17,472 bytes
  # and that is what this prints from `$work` - but building the same
  # source with the same compiler to a LONGER path measures 17,480,
  # because a Mach-O carries paths the linker chose. An equality here
  # would be an assertion about where the gate's temporary directory
  # landed. The proposal's flash budget for the runtime plus a minimal
  # program is 24 KiB, and the floor stops a failed link from reading as
  # a win.
  #
  # AND THE BAND IS THE PROPOSAL'S, WHICH MEASURED A MACH-O - so it is
  # asserted on that format and on no other. A hosted executable's file
  # size is the LINKER's page policy, not the runtime's: the identical
  # program, from byte-identical IR, is 71,168 bytes linked by clang and
  # lld on the aarch64 Ubuntu 24.04 image `run-gates-linux.sh` runs
  # (lld pads to a 64 KiB max-page-size) and 16,416 bytes linked by gcc
  # and ld.bfd on GitHub's x86_64 runner. Measured 2026-09-04, and
  # measured because this arm's second draft gave ELF a band of its own
  # (32..96 KiB) derived from the first number, and the x86_64 leg went
  # red on the second - the same mistake as asserting Mach-O's band on
  # ELF, one level up. Two supported linkers that disagree by 4.3x on
  # the same input are not measuring the runtime, so on ELF and PE the
  # size is printed above and gated nowhere. The proposal's 24 KiB is a
  # claim about the FREESTANDING build that links no crt (A5 and A6
  # exercise it), and about the Mach-O it was measured on, and that is
  # where it stays.
  #
  # THE FORMAT IS READ BY `object_format`, `lib/imports.sh`'s one
  # reader, and not by this gate. The first draft of this arm read the
  # magic itself - `head -c4 | tr -d '\0'`, then `ELF*)` - and the ELF
  # magic is `\x7fELF`: the DEL byte is not a NUL, `tr` kept it, and
  # the arm never matched. Every Linux build fell to the Mach-O band
  # and a 71,168-byte ELF read as over 24 KiB, which is exactly the
  # failure the arm was written to remove, one line below the sentence
  # explaining it. The podman battery (`scripts/run-gates-linux.sh`)
  # caught it before a push did, on 2026-09-04; the darwin run of the
  # same draft printed `tr: Illegal byte sequence` on the Mach-O magic
  # under a UTF-8 locale and passed anyway. Bytes are not text, and a
  # reader that turns them into hex first is the only one this
  # repository keeps.
  fmt="$(object_format "$work/min")" || fmt="unreadable"
  case "$fmt" in
    macho)
      if (( size > 24576 || size < 8192 )); then
        bad "the minimal program is $size bytes; the proposal's Mach-O budget is 8,192..24,576"
        ok=0
      fi ;;
    elf|pe) ;;   # the linker's number: printed above, gated nowhere
    *)
      bad "the minimal program is not a PE, ELF or Mach-O object ($fmt)"
      ok=0 ;;
  esac
  (( ok )) && note "$size bytes, $undef import(s) and none outside the platform's startup set, exactly 3 distinct syscalls"
fi

# ---------------------------------------------------------------------
echo "== building the variant compiler: 4 KiB chunk on $t41, static arena on $host_target =="
# ---------------------------------------------------------------------
mkdir -p "$work/vtree"
cp -a "$src_root/self_host" "$work/vtree/self_host"
python3 "$repo_root/scripts/lib/embedded-patch.py" \
  "variant:$code41:$host_code" "$work/vtree/self_host/codegen.ax" || exit 1
if ! gate_build_tree "$axiom" "$work/vtree" "$AXIOM_STDLIB" "$work/vaxc" \
      > "$work/vbuild.log" 2>&1; then
  # THIS IS A RED, NOT AN ABORT. A target table whose rows cannot take a
  # different value is 4.1 not being a constant.
  bad "the variant compiler does not build - a target table whose rows cannot take
     a different value is not a table"
  sed 's/^/    /' "$work/vbuild.log" | head -15
  echo
  echo "check-embedded: $failed of $((checks + 1)) checks failed"
  exit 1
fi
vaxc="$work/vaxc"

# ---------------------------------------------------------------------
echo "== A4. 4.1: one target's chunk moves, and the others do not =="
# ---------------------------------------------------------------------
checks=$((checks + 1))
emit "$vaxc" "$t41" "$work/min.ax"  "$work/v.min.$t41.ll"  || bad "[$t41] the variant could not emit"
emit "$vaxc" "$t41" "$keep_probe"   "$work/v.keep.$t41.ll" || bad "[$t41] the variant could not emit the keep probe"
emit "$axc"  "$t41" "$keep_probe"   "$work/keep.$t41.ll"   || bad "[$t41] the tree's compiler could not emit the keep probe"

# Every line that differs must be one of the pairs the constant reaches,
# AND every one of those pairs must be among the lines that differ. Both
# directions are load-bearing and the second was missing on the first
# draft: with only "no strays", the `grain` drill - which stops the
# round-up following the chunk - left `%big` and `%chunk` moving, no
# stray, and a count of exactly 8, and the gate stayed GREEN over a
# 4 KiB-chunk target still rounding to 64 KiB. A check that cannot see
# the thing it was written for is this repository's most common defect,
# and it was sitting in the assertion whose subject is a constant
# reaching the emitter.
expected_moves="< |  %big = icmp ugt i64 %need, 1048576
> |  %big = icmp ugt i64 %need, 4096
< |  %rounded0 = add i64 %need, 65535
> |  %rounded0 = add i64 %need, 4095
< |  %rounded = and i64 %rounded0, -65536
> |  %rounded = and i64 %rounded0, -4096
< |  %chunk = select i1 %big, i64 %rounded, i64 1048576
> |  %chunk = select i1 %big, i64 %rounded, i64 4096
< |  %want = and i64 %rounded0, -65536
> |  %want = and i64 %rounded0, -4096"
stray=0
moved=0
: > "$work/seen.keys"
for pair in "min:$work/min.$t41.ll:$work/v.min.$t41.ll" "keep:$work/keep.$t41.ll:$work/v.keep.$t41.ll"; do
  IFS=: read -r pname pa pb <<< "$pair"
  while IFS= read -r line; do
    case "$line" in "< "*|"> "*) ;; *) continue ;; esac
    moved=$((moved + 1))
    key="${line:0:1} |${line:2}"
    printf '%s\n' "$key" >> "$work/seen.keys"
    if ! printf '%s\n' "$expected_moves" | grep -Fxq -- "$key"; then
      stray=$((stray + 1))
      echo "     stray change in $pname: $line"
    fi
  done < <(diff "$pa" "$pb")
done
missing=""
n_expected=0
while IFS= read -r want; do
  n_expected=$((n_expected + 1))
  grep -Fxq -- "$want" "$work/seen.keys" || missing="$missing
       $want"
done <<< "$expected_moves"
# 20 diff lines on 2026-09-04: `refill:`'s four in each of the two
# probes, plus the keep helper's own two, each counted on both of
# diff's sides. The floor is what stops "nothing moved" from reading as
# "nothing strayed"; the completeness check below is what stops "some of
# it moved" from doing the same.
if (( moved < 8 )); then
  bad "[$t41] changing the chunk row moved $moved lines of IR. The constant is not
     reaching the emitter - which is exactly what 4.1 was before this."
elif (( stray > 0 )); then
  bad "[$t41] $stray of $moved changed lines are not the constant's"
elif [[ -n "$missing" ]]; then
  bad "[$t41] $moved lines moved and none strayed, but these lines that carry the
     constant did NOT move - so something reads a value the target no longer
     supplies:$missing"
else
  note "[$t41] a 4 KiB chunk moves $moved diff lines: every line the constant
     reaches, and no other ($n_expected expected forms, all present)"
fi

checks=$((checks + 1))
untouched=0
same=0
for t in "${targets[@]}"; do
  [[ "$t" == "$t41" || "$t" == "$host_target" ]] && continue
  untouched=$((untouched + 1))
  emit "$vaxc" "$t" "$work/min.ax" "$work/v.min.$t.ll" || { bad "[$t] variant emit failed"; continue; }
  if cmp -s "$work/min.$t.ll" "$work/v.min.$t.ll"; then
    same=$((same + 1))
  else
    bad "[$t] a target neither row names emitted different bytes:"
    diff "$work/min.$t.ll" "$work/v.min.$t.ll" | head -6 | sed 's/^/       /'
  fi
done
if (( untouched < 4 )); then
  bad "only $untouched targets were left untouched by the variant; the floor is 4"
elif (( same == untouched )); then
  note "$same targets that neither row names are byte-identical"
fi

# ---------------------------------------------------------------------
echo "== A5. 4.2: the static target emits a region and no mmap =="
# ---------------------------------------------------------------------
checks=$((checks + 1))
emit "$vaxc" "$host_target" "$work/min.ax" "$work/v.min.$host_target.ll" \
  || bad "[$host_target] the variant compiler could not emit"
sll="$work/v.min.$host_target.ll"
hll="$work/min.$host_target.ll"
sn=$(syscall_nums "$sll" | grep -c . || true)
hn=$(syscall_nums "$hll" | grep -c . || true)
# `comm` wants both inputs in ITS collation, and `syscall_nums` sorts
# numerically for the reader: on darwin the three numbers happen to be
# in lexical order too, on Linux `1 9 231` is not, and the x86_64 leg
# printed "comm: file 1 is not in sorted order" - a warning today, and
# `comm` is documented to answer wrongly rather than fail when it is
# ignored. Re-sort both sides under the one collation `comm` runs in.
gone="$(LC_ALL=C comm -23 <(syscall_nums "$hll" | LC_ALL=C sort) <(syscall_nums "$sll" | LC_ALL=C sort) | tr '\n' ' ')"
prob=0
grep -q '^@__axiom_arena = internal global \[262144 x i8\] zeroinitializer, align 16$' "$sll" \
  || { bad "the static build reserves no region"; prob=1; }
grep -q '^@__axiom_arena_cursor = internal global i64 ptrtoint (ptr @__axiom_arena to i64)$' "$sll" \
  || { bad "the static build has no cursor, or it does not start at the region"; prob=1; }
grep -q '^@__axiom_arena_end = internal constant i64 ptrtoint' "$sll" \
  || { bad "the static build has no end, so nothing bounds the carve"; prob=1; }
grep -q '^  %ar_cur = load i64, ptr @__axiom_arena_cursor$' "$sll" \
  || { bad "the static build has a region and does not carve out of it"; prob=1; }
grep -q 'out of memory (arena exhausted)' "$sll" \
  || { bad "the static build's out-of-memory trap still blames mmap"; prob=1; }
if [[ "$sn" != "2" ]]; then
  bad "the static build makes $sn distinct syscalls; with no mmap it must make 2"
  prob=1
fi
if [[ "$hn" != "3" ]]; then
  bad "the CONTROL - same target, same probe, the tree's compiler - makes $hn
     syscalls, not 3, so 'two' above would not mean 'mmap is gone'"
  prob=1
fi
# ANCHORED ON THE DEFINITION, not on the prefix. `@__axiom_arena_mark_fn`
# and `@__axiom_arena_reset_fn` are in every program's runtime and start
# with the same eleven characters, so the loose grep called the region
# present in a program that has no region - reported on this gate's
# first run.
if grep -q '^@__axiom_arena = ' "$hll"; then
  bad "the tree's own compiler emits an arena region for $host_target - the strategy
     is not off by default, and A5 would pass with 4.2 unwritten"
  prob=1
fi
grep -q 'out of memory (mmap failed)' "$hll" \
  || { bad "the control's trap does not name mmap, so the message check compares nothing"; prob=1; }
(( prob )) || note "region + cursor + carve, $hn syscalls become $sn (gone: ${gone:-none}), trap renamed"

# ---------------------------------------------------------------------
echo "== A6. 4.2: and it runs =="
# ---------------------------------------------------------------------
checks=$((checks + 1))
run_probe() {  # run_probe <compiler> <source> <tag> [extra flags...] -> "<status> <stdout>"
  local comp="$1" src="$2" tag="$3"; shift 3
  local st out
  if ! "$comp" build --input "$src" --output "$work/$tag" "$@" --opt 1 > "$work/$tag.build.log" 2>&1; then
    echo "BUILDFAIL"
    return
  fi
  out="$("$work/$tag" 2> "$work/$tag.err")"
  st=$?
  echo "$st $out"
}
mm_fit="$(run_probe "$axc"  "$work/fit.ax" fit.mmap)"
st_fit="$(run_probe "$vaxc" "$work/fit.ax" fit.static)"
mm_oom="$(run_probe "$axc"  "$work/oom.ax" oom.mmap)"
st_oom="$(run_probe "$vaxc" "$work/oom.ax" oom.static)"
echo "     fits:      mmap [$mm_fit]  static [$st_fit]"
echo "     overflows: mmap [$mm_oom]  static [$st_oom]"
prob=0
[[ "$mm_fit" == "0 5050" ]] \
  || { bad "the mmap build of the fitting program answered [$mm_fit], not [0 5050]"; prob=1; }
[[ "$st_fit" == "0 5050" ]] \
  || { bad "the STATIC build of the fitting program answered [$st_fit], not [0 5050] -
     52,800 bytes carved out of a 256 KiB region in 4 KiB chunks"; prob=1; }
[[ "$mm_oom" == "0 2001000" ]] \
  || { bad "the mmap build of the larger program answered [$mm_oom], not [0 2001000],
     so a 70 from the static build would be the program's verdict, not the region's"; prob=1; }
case "$st_oom" in
  "70"|"70 ") ;;
  *) bad "the static build of the larger program answered [$st_oom]; exhausting the
     region must trap with status 70 (MM-ALLOC-7)"; prob=1 ;;
esac
if ! grep -q 'out of memory (arena exhausted)' "$work/oom.static.err" 2>/dev/null; then
  bad "the static build's trap printed no sentence naming the arena:
     $(head -1 "$work/oom.static.err" 2>/dev/null)"
  prob=1
fi
(( prob )) || note "the static arena answers 5050 as mmap does, and exits 70 when it runs out"

# ---------------------------------------------------------------------
echo "== A7. --heap-ceiling: the bounded mode on a supported target =="
# ---------------------------------------------------------------------
# The same two programs A6 runs, but the region comes from a FLAG on
# the tree's own compiler rather than from a variant target table: no
# second compiler is built here at all. 262144 is the same 256 KiB A6
# uses, so the verdicts must match it exactly - and the `=` spelling
# carries the overflow leg, so both spellings the reader accepts are
# exercised rather than one.
checks=$((checks + 1))
ceil_fit="$(run_probe "$axc" "$work/fit.ax" fit.ceil --heap-ceiling 262144)"
ceil_oom="$(run_probe "$axc" "$work/oom.ax" oom.ceil --heap-ceiling=262144)"
ctl_oom="$(run_probe "$axc" "$work/oom.ax" oom.ctl)"
echo "     fits under ceiling: [$ceil_fit]"
echo "     overflows under ceiling: [$ceil_oom]  control, no flag: [$ctl_oom]"
prob=0
[[ "$ceil_fit" == "0 5050" ]] \
  || { bad "the ceiling build of the fitting program answered [$ceil_fit], not [0 5050]"; prob=1; }
[[ "$ctl_oom" == "0 2001000" ]] \
  || { bad "the control build of the larger program answered [$ctl_oom], not [0 2001000]"; prob=1; }
case "$ceil_oom" in
  "70"|"70 ") ;;
  *) bad "the ceiling build of the larger program answered [$ceil_oom]; a bounded heap
     must trap with status 70 (MM-ALLOC-7) rather than growing past it"; prob=1 ;;
esac
if ! grep -q 'out of memory (arena exhausted)' "$work/oom.ceil.err" 2>/dev/null; then
  bad "the ceiling build's trap printed no sentence naming the arena:
     $(head -1 "$work/oom.ceil.err" 2>/dev/null)"
  prob=1
fi
(( prob )) || note "under a ceiling the fitting program answers 5050 and the larger exits 70"

# The IR behind those verdicts: the asked region, the chunk capped by
# it (262144, not the table's 1048576 and not the variant's 4096 -
# this is what distinguishes the flag path from both), no `mmap`, and
# the renamed trap. Against the no-flag control, which must show the
# opposite of every one.
checks=$((checks + 1))
if ! emit "$axc" "$host_target" "$work/fit.ax" "$work/ceil.fit.ll" --heap-ceiling 262144; then
  bad "emit-llvm failed under --heap-ceiling"
  sed 's/^/    /' "$work/emit.log" | head -6
else
  prob=0
  grep -q '^@__axiom_arena = internal global \[262144 x i8\] zeroinitializer, align 16$' "$work/ceil.fit.ll" \
    || { bad "the ceiling build reserves no 262144-byte region"; prob=1; }
  grep -q '  %chunk = select i1 %big, i64 %rounded, i64 262144$' "$work/ceil.fit.ll" \
    || { bad "the ceiling build's growth unit is not capped by the region"; prob=1; }
  if grep -qE 'mmap|VirtualAlloc' "$work/ceil.fit.ll"; then
    bad "the ceiling build still asks the kernel for pages"; prob=1
  fi
  grep -q 'out of memory (arena exhausted)' "$work/ceil.fit.ll" \
    || { bad "the ceiling build's trap still blames mmap"; prob=1; }
  if grep -q '^@__axiom_arena = ' "$work/min.$host_target.ll"; then
    bad "the CONTROL emits a region - the strategy is not off by default here either"
    prob=1
  fi
  (( prob )) || note "262144-byte region, capped growth, no mmap, renamed trap - and none of it in the control"
fi

# The flag's own refusals. Each is a wrong command line, so each must
# exit 2 naming the flag - and each is planted here rather than
# described, because a refusal that is never refused is the defect.
checks=$((checks + 1))
prob=0
refuse() { # refuse <label> <args...>: exit 2 naming --heap-ceiling
  local label="$1"; shift
  local err; err="$("$axc" build --input "$work/min.ax" --output "$work/refused" "$@" 2>&1)"; local rc=$?
  if (( rc != 2 )) || ! grep -q -- '--heap-ceiling' <<<"$err"; then
    bad "[$label] exited $rc, not 2 naming the flag: $(head -1 <<<"$err")"
    prob=1
  fi
}
refuse "non-numeric" --heap-ceiling banana
refuse "zero" --heap-ceiling 0
refuse "missing value" --heap-ceiling
if (( prob == 0 )); then
  # The refusal names the flag in every case, which is what makes each
  # of the three a pointed refusal rather than a bare status.
  note "non-numeric, zero and missing values each exit 2 naming the flag"
fi

# `--threads` on a spawning program under a ceiling is AX4006 at BUILD
# time: one cursor cannot serve two bump pointers, and the refusal is
# the existing diagnostic rather than a new one. As a DIFFERENTIAL:
# the same program with `--threads` and no ceiling must build here, so
# the refusal below is the ceiling's doing and not the target's. Where
# the plain threads build already fails (a host with no thread
# runtime), the property is untestable and the leg says so instead of
# passing over a refusal it did not cause.
checks=$((checks + 1))
cat > "$work/par7.ax" <<'AX'
(:: main Int)
;@axiom:effect(io)
(fn (main) (parallel p ((a 40) (b 2)) (+ a b)))
AX
if "$axc" build --input "$work/par7.ax" --output "$work/par7.plain" --threads \
    > "$work/par7.plain.log" 2>&1; then
  if "$axc" build --input "$work/par7.ax" --output "$work/par7" --heap-ceiling 262144 --threads \
      > "$work/par7.log" 2>&1; then
    bad "a spawning program built --threads under a ceiling, which has one cursor for two bump pointers"
  elif grep -q 'AX4006' "$work/par7.log"; then
    note "threads under a ceiling are refused as AX4006 before anything emits"
  else
    bad "the threads-under-ceiling build failed, but not as AX4006:"
    head -3 "$work/par7.log" | sed 's/^/       /'
  fi
else
  note "no thread runtime on $host_target: the threads leg is untestable here, and says so"
fi

# ---------------------------------------------------------------------
echo "== A8. 4.3: every supported target writes its traps to fd 2 =="
# ---------------------------------------------------------------------
# The proposal's default: a trap reports its sentence before it exits.
# `emitRuntimeWrite` is the single door - the backtrace writer
# delegates to it - so one probe exercises every site: a division by
# zero for the div guard's trap, plus the backtrace its handler walks.
# On the six syscall targets a trap write is an `asm sideeffect` line
# carrying fd 2; the probe's own `println` carries fd 1, which is what
# makes the pattern the trap's and not the program's. On Windows the
# discriminator is the handle: -12 is STD_ERROR_HANDLE, -11 the
# program's own stdout.
checks=$((checks + 1))
cat > "$work/divtrap.ax" <<'AX'
(import IO)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println (/ 10 0))
    0
  }
)
AX
prob=0
# Trap writes per emitted module, by target. On the six syscall
# targets a trap write is an `asm sideeffect` line carrying fd 2 -
# both halves are load-bearing: `, i64 2, i64 ` alone also matches a
# `memSetWord` of the word 2, and `asm sideeffect` alone is every
# syscall the module makes. On Windows the discriminator is the
# handle: -12 is STD_ERROR_HANDLE, -11 the program's own stdout, and
# both go through `WriteFile`.
trapwrites() {
  if [[ "$2" == windows-* ]]; then grep -c 'GetStdHandle(i64 -12)' "$1" || true
  else grep 'asm sideeffect' "$1" | grep -c ', i64 2, i64 ' || true; fi
}
for t in "${targets[@]}"; do
  if ! emit "$axc" "$t" "$work/divtrap.ax" "$work/div.$t.ll"; then
    bad "[$t] emit-llvm failed for the trapping probe"
    sed 's/^/    /' "$work/emit.log" | head -6
    prob=1
    continue
  fi
  if grep -q 'trap message suppressed' "$work/div.$t.ll"; then
    bad "[$t] the tree's own compiler emits silent traps - the strategy is not off by default"
    prob=1
  fi
  n2=$(trapwrites "$work/div.$t.ll" "$t")
  echo "     [$t] $n2 trap writes"
  (( n2 >= 10 )) || { bad "[$t] $n2 trap writes, floor 10"; prob=1; }
done
(( prob )) || note "seven targets write their traps (15 apiece here), and none is silent"

# The default has one spelling, held the way A2 holds 4.1's: a second
# spelling is a target that cannot choose silence. The row is two lines
# in the current normal form (`fn` heads stand alone), so the check
# reads the header and the line under it as one spelling.
checks=$((checks + 1))
prob=0
spell="$(grep -A1 '^(pub fn (targetTrapSilent t)$' "$src_root/self_host/codegen.ax")"
want="$(printf '(pub fn (targetTrapSilent t)\n  0)')"
if [[ "$spell" != "$want" ]]; then
  bad "targetTrapSilent's default is not the one spelling - a second spelling
     is a target that cannot choose silence: [$spell]"
  prob=1
fi
(( prob )) || note "the silent strategy is one row, off unless a target asks"

# ---------------------------------------------------------------------
echo "== A9. 4.3: silent traps exit with the status and print nothing =="
# ---------------------------------------------------------------------
# A second variant compiler, silent on the host: the no-op door of 4.3,
# which is what a board with nothing to write to would select. The same
# probe as A8, so the comparison is line for line: every fd-2 write the
# tree's build carries must be a suppression mark in the silent one,
# and nothing else may move. Then both binaries run: the statuses must
# agree and only one of them may have spoken.
checks=$((checks + 1))
mkdir -p "$work/stree"
cp -a "$src_root/self_host" "$work/stree/self_host"
python3 "$repo_root/scripts/lib/embedded-patch.py" \
  "silent:$host_code" "$work/stree/self_host/codegen.ax" || exit 1
if ! gate_build_tree "$axiom" "$work/stree" "$AXIOM_STDLIB" "$work/saxc" \
      > "$work/sbuild.log" 2>&1; then
  bad "the silent variant does not build - a target-table row that cannot take 1 is not a row"
  sed 's/^/    /' "$work/sbuild.log" | head -15
else
saxc="$work/saxc"
prob=0
nsup=0; nloud=0; nquiet=0
if ! emit "$saxc" "$host_target" "$work/divtrap.ax" "$work/div.silent.ll"; then
  bad "the silent variant could not emit the trapping probe"
  sed 's/^/    /' "$work/emit.log" | head -6
  prob=1
else
  nsup=$(grep -c 'trap message suppressed' "$work/div.silent.ll" || true)
  nloud=$(trapwrites "$work/div.$host_target.ll" "$host_target")
  nquiet=$(trapwrites "$work/div.silent.ll" "$host_target")
  echo "     $nloud trap writes loud, $nsup suppressions and $nquiet trap writes silent"
  [[ "$nsup" == "$nloud" && "$nloud" != "0" ]] \
    || { bad "the silent build suppresses $nsup writes where the tree's carries $nloud -
     the branch must move exactly the write lines"; prob=1; }
  [[ "$nquiet" == "0" ]] \
    || { bad "the silent build still writes its traps ($nquiet lines)"; prob=1; }
fi
(( prob )) || note "the silent build carries $nsup suppressions for $nloud writes and none of its own"
checks=$((checks + 1))
prob=0
loud="$(run_probe "$axc" "$work/divtrap.ax" div.loud)"
quiet="$(run_probe "$saxc" "$work/divtrap.ax" div.quiet)"
echo "     loud [$loud] quiet [$quiet]"
case "$loud" in
  "72"|"72 ") ;;
  *) bad "the tree's build of the trapping probe answered [$loud], not status 72,
     so the silence below would be compared against nothing"; prob=1 ;;
esac
case "$quiet" in
  "72"|"72 ") ;;
  *) bad "the silent build answered [$quiet]; a trap that cannot write must still exit 72"; prob=1 ;;
esac
if [[ -s "$work/div.quiet.err" ]]; then
  bad "the silent trap wrote $(wc -c < "$work/div.quiet.err" | tr -d ' ') bytes to fd 2"
  prob=1
fi
if ! grep -q 'division by zero' "$work/div.loud.err" 2>/dev/null; then
  bad "the control's trap names no division, so the silence comparison compares nothing"
  prob=1
fi
(( prob )) || note "status 72 out of both, the sentence out of one and zero bytes out of the other"
fi

# ---------------------------------------------------------------------
echo "== A10. section 6: the blink fixture runs under QEMU =="
# ---------------------------------------------------------------------
# The reference port's device leg, docs/embedded-proposal.md section 6:
# the blink fixture built for `baremetal-aarch64` and booted under
# `qemu-system-aarch64 -machine virt`, its UART bytes and its exit
# status asserted - plus the oversized ablation, a program too large
# for the reserved region, which must exit with the status
# tests/stdlib/314-out-of-memory.exit pins against a control that
# exits 0.
#
# THE CONTRACT THIS LEG NEEDS FROM THE PORT (section 6 items 1-3), so
# a red here names which half broke it:
#
#   * `--target baremetal-aarch64` is accepted, and `build` for it
#     links one aarch64 ELF: the linker script places it in `virt`
#     RAM and the reset vector sets sp and branches to `main`.
#   * `println` and the trap sentences reach the PL011 UART at
#     0x09000000, observable on stdio under `-nographic`.
#   * the guest's exit status N surfaces as the qemu process's own
#     status N, through a semihosting SYS_EXIT - `hlt #0xf000` with
#     x0 = 0x18 and x1 pointing at two words, reason 0x20026
#     (`ADP_Stopped_ApplicationExit`) and the status. That is the
#     shape rust-embedded/qemu-exit's AArch64 backend uses, and the
#     flags below are what the shape needs: `-semihosting` with
#     `target=native`, `-monitor none` so stdio carries the UART and
#     nothing else, `-no-reboot` so a faulting guest exits instead of
#     resetting. Measured against hand-built guests: subcodes 0, 5
#     and 70 surface as 0, 5 and 70 with the UART bytes exact and
#     qemu's stderr empty - and the block is two 64-bit words,
#     because two 32-bit ones read the reason as 0x4600020026 and
#     every nonzero status came back 1.
#
# TWO SKIPS, both loud. The target does not exist until section 6's
# items 1-3 land: the probe is an `emit-llvm`, and exit 3 naming
# `unknown target` is the ONLY answer that skips - any other failure
# is the port's, and fails. And QEMU is a host tool no runner image
# promises: without `qemu-system-aarch64` on PATH the device is
# untestable here, as `check-ffi.sh` is without cargo, and the leg
# says so instead of passing over hardware it never booted.
#
# NO ABLATION DRILL, and the absence is load-bearing rather than lazy:
# every drill in `embedded-patch.py` anchors on a string in
# `codegen.ax`, and the port's emission - the UART writer, the exit
# door - is not in this tree yet, so there is nothing to anchor on.
# The comparisons prove themselves meanwhile: an empty UART fails
# blink against its 18 hosted bytes, and a status that never leaves 0
# fails the 70. The merge that lands the port owes this leg a drill
# anchored on its emission.
bm_target=baremetal-aarch64
blink="$repo_root/tests/embedded/blink.ax"
blinkoom="$repo_root/tests/embedded/blink-oom.ax"
oompin="$repo_root/tests/stdlib/314-out-of-memory.exit"
[[ -f "$blink" ]] || abort "$blink is gone; section 6's fixture has no probe."
[[ -f "$blinkoom" ]] || abort "$blinkoom is gone; the oversized ablation has no probe."
[[ -f "$oompin" ]] || abort "$oompin is gone; the exit-70 pin has no file."
want_oom="$(cat "$oompin")"
case "$want_oom" in ''|*[!0-9]*) abort "$oompin answers [$want_oom], not a status" ;; esac

# One build, host or device. `--target` parses after the subcommand as
# well as before it, so the device builds read as `build` flags
# beside `--opt`.
build_bm() {  # build_bm <tag> <source> [extra flags...]
  local tag="$1" src="$2"; shift 2
  "$axc" --diagnostic-format=ai build --input "$src" --output "$work/$tag" "$@" --opt 1 \
    > "$work/$tag.build.log" 2>&1
}
# An aarch64 ELF and nothing else: magic, little-endian, EM_AARCH64
# (183) at offset 18. The guard that names "linked for the wrong
# machine" before qemu names it as a hung boot.
is_aarch64_elf() {
  python3 - "$1" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read(20)
ok = len(d) == 20 and d[:4] == b'\x7fELF' and d[5] == 1 and d[18] == 183 and d[19] == 0
sys.exit(0 if ok else 1)
PY
}
# Boot under QEMU and print the guest's status - or TIMEOUT, when the
# guest never exits. The timeout is generous because a hung guest
# spins host CPU under TCG until it is killed; a healthy one is out
# in seconds. `python3` because macOS ships no `timeout(1)` and the
# gate runs on macos-14 too.
qemu_run() {  # qemu_run <elf> <uart_out> <qemu_err>
  python3 - "$1" "$2" "$3" <<'PY'
import subprocess, sys
elf, out, err = sys.argv[1], sys.argv[2], sys.argv[3]
cmd = ["qemu-system-aarch64", "-machine", "virt", "-cpu", "cortex-a72",
       "-nographic", "-monitor", "none", "-no-reboot",
       "-semihosting", "-semihosting-config", "enable=on,target=native",
       "-kernel", elf]
try:
    p = subprocess.run(cmd, stdout=open(out, "wb"), stderr=open(err, "wb"), timeout=120)
    print(p.returncode)
except subprocess.TimeoutExpired:
    print("TIMEOUT")
PY
}

# The probe exercises target resolution and nothing else, so its
# failure modes are the target's. The accepted-target list is printed
# with the skip, so a port that landed under another NAME shows up as
# a mismatch in every log rather than as a quiet wait.
if ! emit "$axc" "$bm_target" "$work/min.ax" "$work/bm.probe.ll" --diagnostic-format=ai; then
  checks=$((checks + 1))
  if grep -q 'unknown target' "$work/emit.log" 2>/dev/null; then
    echo "     the tree's compiler answers [$(head -1 "$work/emit.log")]"
    note "$bm_target is not a target this compiler knows - section 6 items 1-3
     have not landed, and A10 waits for them rather than failing over a port
     that is not there"
  else
    bad "$bm_target failed to emit for a reason that is not 'unknown target':"
    sed 's/^/       /' "$work/emit.log" | head -6
  fi
elif ! command -v qemu-system-aarch64 >/dev/null 2>&1; then
  checks=$((checks + 1))
  note "qemu-system-aarch64 is not on PATH: the device leg is untestable here, and says so"
else
checks=$((checks + 1))
prob=0
echo "     device leg live: $bm_target under $(qemu-system-aarch64 --version 2>/dev/null | head -1)"
build_bm blink.host "$blink" \
  || { bad "blink does not build for the host:"; sed 's/^/       /' "$work/blink.host.build.log" | head -6; prob=1; }
build_bm blink.bm "$blink" --target="$bm_target" \
  || { bad "blink emits for $bm_target but does not build - the link half of the port:"; sed 's/^/       /' "$work/blink.bm.build.log" | head -6; prob=1; }
build_bm blinkoom.host "$blinkoom" \
  || { bad "the oversized probe does not build for the host:"; sed 's/^/       /' "$work/blinkoom.host.build.log" | head -6; prob=1; }
build_bm blinkoom.bm "$blinkoom" --target="$bm_target" \
  || { bad "the oversized probe emits for $bm_target but does not build:"; sed 's/^/       /' "$work/blinkoom.bm.build.log" | head -6; prob=1; }
if (( prob == 0 )); then
  is_aarch64_elf "$work/blink.bm" \
    || { bad "the $bm_target blink is not an aarch64 ELF - qemu -kernel would boot bytes for another machine"; prob=1; }
  is_aarch64_elf "$work/blinkoom.bm" \
    || { bad "the $bm_target oversized probe is not an aarch64 ELF"; prob=1; }
fi
if (( prob == 0 )); then
  note "blink and its oversized twin build for the host and the device, and the device pair are aarch64 ELFs"
  checks=$((checks + 1))
  prob=0
  "$work/blink.host" > "$work/blink.host.out" 2> "$work/blink.host.err"; host_blink_st=$?
  printf 'LED ON\n42\nLED OFF\n' > "$work/blink.want"
  st_uart="$(qemu_run "$work/blink.bm" "$work/blink.uart" "$work/blink.qemu.err")"
  echo "     blink: host exit $host_blink_st, device exit $st_uart"
  [[ "$host_blink_st" == "0" ]] \
    || { bad "hosted blink exits $host_blink_st, not 0 - the control moved"; prob=1; }
  cmp -s "$work/blink.host.out" "$work/blink.want" \
    || { bad "hosted blink prints [$(tr '\n' ' ' < "$work/blink.host.out")], not [LED ON 42 LED OFF]"; prob=1; }
  case "$st_uart" in
    0) ;;
    TIMEOUT) bad "blink never exited under QEMU in 120s - the guest hung past its semihosting door:"; head -c 300 "$work/blink.qemu.err" | sed 's/^/       /'; prob=1 ;;
    *) bad "blink under QEMU exits $st_uart, not 0:"; head -c 300 "$work/blink.qemu.err" | sed 's/^/       /'; prob=1 ;;
  esac
  if ! cmp -s "$work/blink.host.out" "$work/blink.uart" 2>/dev/null; then
    bad "the UART bytes are not the hosted bytes:"
    { echo "--- host:"; od -A x -t x1 "$work/blink.host.out" 2>/dev/null; echo "--- uart:"; od -A x -t x1 "$work/blink.uart" 2>/dev/null; } | head -12 | sed 's/^/       /'
    prob=1
  fi
  nlit=$(grep -o '"LED [A-Z]*"' "$blink" | wc -l | tr -d ' ')
  [[ "$nlit" == "2" ]] \
    || { bad "blink.ax carries $nlit LED literals, not 2 - the payload anchor moved"; prob=1; }
  while IFS= read -r lit; do
    lit="${lit%\"}"; lit="${lit#\"}"
    grep -Fq -- "$lit" "$work/blink.uart" \
      || { bad "the UART bytes lack [$lit], which blink.ax spells"; prob=1; }
  done < <(grep -o '"LED [A-Z]*"' "$blink")
  (( prob )) || note "device exit 0, UART bytes equal 18 hosted bytes, both LED literals on the wire"
  checks=$((checks + 1))
  prob=0
  "$work/blinkoom.host" > "$work/blinkoom.host.out" 2> "$work/blinkoom.host.err"; host_oom_st=$?
  printf 'OOM PROBE\n200010000\n' > "$work/blinkoom.want"
  st_oom="$(qemu_run "$work/blinkoom.bm" "$work/blinkoom.uart" "$work/blinkoom.qemu.err")"
  echo "     oversized: host exit $host_oom_st, device exit $st_oom, pin $want_oom"
  [[ "$host_oom_st" == "0" ]] && cmp -s "$work/blinkoom.host.out" "$work/blinkoom.want" \
    || { bad "the control - hosted oversized - answered [$host_oom_st $(tr '\n' ' ' < "$work/blinkoom.host.out")], not [0 OOM PROBE 200010000],
     so a $want_oom from the device would be the program's verdict, not the region's"; prob=1; }
  case "$st_oom" in
    "$want_oom") ;;
    TIMEOUT) bad "the oversized probe never exited under QEMU in 120s:"; head -c 300 "$work/blinkoom.qemu.err" | sed 's/^/       /'; prob=1 ;;
    *) bad "the oversized probe under QEMU exits $st_oom, not $want_oom - exhausting the
     region must trap with MM-ALLOC-7's status, the pin $oompin names:"; head -c 300 "$work/blinkoom.qemu.err" | sed 's/^/       /'; prob=1 ;;
  esac
  grep -q 'out of memory (arena exhausted)' "$work/blinkoom.uart" 2>/dev/null \
    || { bad "the device trap printed no sentence naming the arena:"; head -c 300 "$work/blinkoom.uart" 2>/dev/null | sed 's/^/       /'; prob=1; }
  grep -q 'OOM PROBE' "$work/blinkoom.uart" 2>/dev/null \
    || { bad "the UART carries no boot line - the guest died before main"; prob=1; }
  (( prob )) || note "device exit $want_oom with the arena's sentence on the UART, control 0"
fi
fi

# ---------------------------------------------------------------------
echo "== A11. device primitives: volatile at device widths, barriers, AX4008 =="
# ---------------------------------------------------------------------
# docs/memory-model.md MM-FFI-8. The eight volatile accesses and the
# fifteen `__arm_*` primitives (`tcRegDevicePrims`, `emitPrimDevice`),
# asserted on what the compiler EMITS - no QEMU, so this section runs on
# every host, CI runners included:
#
#   * each width is ONE `load volatile iN` / `store volatile iN` with
#     natural alignment, two of each in a probe that writes every
#     register twice and reads it twice;
#   * the volatile writes SURVIVE `opt -O2`, and the proof that this
#     means something is a CONTROL: the same double write through the
#     plain `__store8`/`__store64`, whose dead first store `opt`
#     deletes. A volatile that the optimiser could have removed but
#     didn't is the only evidence the keyword is doing its job;
#   * `llc` keeps each WIDTH - strb/strh/str w/str x and their loads -
#     because a 32-bit device register read as two halves is a wrong
#     program even when the value is right;
#   * every `__arm_*` is its instruction, in the IR and in the AArch64
#     assembly;
#   * AX4008 draws the target line: the volatile set emits for x86-64,
#     the EL0 tier (barriers, counter reads) for an aarch64 host, the
#     EL1 tier only for baremetal-aarch64 - and an EL1 primitive in a
#     function nothing calls is NOT refused, because the check reads
#     the pruned module.
#
# Drills: `volatile` strips the keyword from both emitters (the probe's
# accesses become ordinary and `opt` deletes the first store), `barrier`
# lowers `__arm_dmb` to a `nop`, and `refusal` lets every target run
# every primitive.
cat > "$work/vol.ax" <<'AX'
(import IO)
(import Mem)

(:: twice (-> Int Int))
;@axiom:effect(unsafe)
(fn (twice p)
  {
    (__vstore8 p 11)
    (__vstore8 p 22)
    (__vstore16 (+ p 2) 1111)
    (__vstore16 (+ p 2) 2222)
    (__vstore32 (+ p 4) 33333333)
    (__vstore32 (+ p 4) 44444444)
    (__vstore64 (+ p 8) 5555555555555)
    (__vstore64 (+ p 8) 6666666666666)
    (+ (+ (__vload8 p) (__vload8 p))
      (+ (+ (__vload16 (+ p 2)) (__vload16 (+ p 2)))
        (+ (+ (__vload32 (+ p 4)) (__vload32 (+ p 4)))
          (+ (__vload64 (+ p 8)) (__vload64 (+ p 8))))))
  })

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((p (memAlloc 16)))
    {
      (println (twice p))
      0
    }))
AX
# The control: the same double write, through the ordinary primitives.
cat > "$work/plain.ax" <<'AX'
(import IO)
(import Mem)

(:: twice (-> Int Int))
;@axiom:effect(unsafe)
(fn (twice p)
  {
    (__store8 p 0 11)
    (__store8 p 0 22)
    (__store64 p 1 5555555555555)
    (__store64 p 1 6666666666666)
    (+ (__load8 p 0) (__load64 p 1))
  })

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((p (memAlloc 16)))
    {
      (println (twice p))
      0
    }))
AX
# Every `__arm_*`, each once, in one function `main` calls.
cat > "$work/arm.ax" <<'AX'
(import Mem)

(:: sys (-> Int Int))
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (sys p)
  {
    __arm_dmb
    __arm_dsb
    __arm_isb
    (__arm_set_cntv_cval (+ __arm_cntvct __arm_cntfrq))
    (__arm_set_cntv_ctl 0)
    (__arm_set_tpidr p)
    __arm_irq_mask
    __arm_irq_unmask
    __arm_wfi
    (__arm_dc_cvac p)
    (__arm_dc_civac p)
    (+ __arm_ctr __arm_tpidr)
  })

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (sys (memAlloc 64)))
AX
# The EL0 tier alone - what an aarch64 host may run - and an EL1
# primitive in a function nothing calls.
cat > "$work/el0.ax" <<'AX'
(import IO)

(:: unused Int)
(fn (unused)
  {
    __arm_irq_unmask
    0
  })

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    __arm_dmb
    __arm_dsb
    __arm_isb
    (println (> __arm_cntfrq 0))
    (println (> __arm_cntvct 0))
    0
  })
AX
checks=$((checks + 1))
prob=0
bm=baremetal-aarch64
if ! emit "$axc" "$bm" "$work/vol.ax" "$work/vol.bm.ll"; then
  bad "the volatile probe does not emit for $bm:"; sed 's/^/       /' "$work/emit.log" | head -6; prob=1
else
  for w in 8 16 32 64; do
    a=$((w / 8))
    nl=$(grep -cE "= load volatile i$w, ptr %[^,]+, align $a\$" "$work/vol.bm.ll" || true)
    ns=$(grep -cE "^  store volatile i$w [^,]+, ptr %[^,]+, align $a\$" "$work/vol.bm.ll" || true)
    [[ "$nl" == 2 && "$ns" == 2 ]] \
      || { bad "i$w: $nl volatile loads and $ns volatile stores at align $a, not 2 and 2"; prob=1; }
  done
fi
(( prob )) || note "each of i8/i16/i32/i64 is two volatile loads and two volatile stores at natural alignment"
checks=$((checks + 1))
prob=0
if ! command -v opt >/dev/null 2>&1; then
  bad "opt is not on PATH; the survival half of this section cannot run"
  prob=1
elif ! emit "$axc" "$bm" "$work/plain.ax" "$work/plain.bm.ll"; then
  bad "the control does not emit:"; sed 's/^/       /' "$work/emit.log" | head -6; prob=1
elif ! opt -O2 -S "$work/vol.bm.ll" -o "$work/vol.O2.ll" 2> "$work/opt.log" \
     || ! opt -O2 -S "$work/plain.bm.ll" -o "$work/plain.O2.ll" 2>> "$work/opt.log"; then
  bad "opt -O2 refused the probe or the control:"; head -6 "$work/opt.log" | sed 's/^/       /'; prob=1
else
  # The probe's own function, as `opt` left it: `twice` is also
  # inlined into `main`, and counting the module would count it twice.
  awk '/^define .*@twice\(/{on=1} on{print} on&&/^}/{exit}' "$work/vol.O2.ll" > "$work/vol.twice.ll"
  awk '/^define .*@twice\(/{on=1} on{print} on&&/^}/{exit}' "$work/plain.O2.ll" > "$work/plain.twice.ll"
  [[ -s "$work/vol.twice.ll" && -s "$work/plain.twice.ll" ]] \
    || { bad "opt -O2 left no @twice in the probe or the control to count in"; prob=1; }
  # The FIRST of each pair is the store nothing reads before it is
  # overwritten - a dead store, unless it is volatile.
  for pat in "store volatile i8 11," "store volatile i16 1111," \
             "store volatile i32 33333333," "store volatile i64 5555555555555,"; do
    grep -qF -- "$pat" "$work/vol.twice.ll" \
      || { bad "after opt -O2 the probe has no [$pat] - the dead-looking first write was deleted"; prob=1; }
  done
  nvl=$(grep -c 'load volatile' "$work/vol.twice.ll" || true)
  [[ "$nvl" == 8 ]] || { bad "after opt -O2 the probe has $nvl volatile loads, not 8 - a read was merged"; prob=1; }
  for pat in "store i8 11," "store i64 5555555555555,"; do
    if grep -qF -- "$pat" "$work/plain.twice.ll"; then
      bad "the CONTROL kept [$pat] through opt -O2, so the optimiser did not delete a dead
     store here and the probe's survival above proves nothing"
      prob=1
    fi
  done
fi
(( prob )) || note "opt -O2 keeps all eight volatile writes and eight reads; it deletes the control's plain dead stores"
checks=$((checks + 1))
prob=0
if ! llc -O2 -mtriple=aarch64-unknown-none-elf "$work/vol.bm.ll" -o "$work/vol.bm.s" 2> "$work/llc.log"; then
  bad "llc refused the probe:"; head -6 "$work/llc.log" | sed 's/^/       /'; prob=1
else
  # The probe's function alone, so the runtime's own UART stores and
  # spills do not count.
  awk '/^twice:/{on=1} on{print} on&&/\.Lfunc_end/{exit}' "$work/vol.bm.s" > "$work/twice.s"
  for m in 'strb	w' 'strh	w' 'str	w' 'str	x' 'ldrb	w' 'ldrh	w' 'ldr	w' 'ldr	x'; do
    n=$(grep -cF -- "$m" "$work/twice.s" || true)
    (( n >= 2 )) || { bad "the AArch64 code for the probe carries $n [$m], not 2 - a width was not kept"; prob=1; }
  done
fi
(( prob )) || note "llc keeps every width: strb/strh/str w/str x and ldrb/ldrh/ldr w/ldr x, two of each"
checks=$((checks + 1))
prob=0
if ! emit "$axc" "$bm" "$work/arm.ax" "$work/arm.bm.ll"; then
  bad "the __arm_ probe does not emit for $bm:"; sed 's/^/       /' "$work/emit.log" | head -6; prob=1
else
  for s in '"dmb sy", "~{memory}"' '"dsb sy", "~{memory}"' '"isb", "~{memory}"' \
           '"mrs $0, cntvct_el0", "=r,~{memory}"' '"mrs $0, cntfrq_el0", "=r"' '"mrs $0, ctr_el0", "=r"' \
           '"mrs $0, tpidr_el1", "=r"' '"msr tpidr_el1, $0", "r,~{memory}"' \
           '"msr cntv_cval_el0, $0", "r,~{memory}"' '"msr cntv_ctl_el0, $0", "r,~{memory}"' \
           '"msr daifset, #2", "~{memory}"' '"msr daifclr, #2", "~{memory}"' '"wfi", "~{memory}"' \
           '"dc cvac, $0", "r,~{memory}"' '"dc civac, $0", "r,~{memory}"'; do
    n=$(grep -cF -- "asm sideeffect $s" "$work/arm.bm.ll" || true)
    [[ "$n" == 1 ]] || { bad "the IR carries $n [asm sideeffect $s], not 1"; prob=1; }
  done
  if ! llc -O2 -mtriple=aarch64-unknown-none-elf "$work/arm.bm.ll" -o "$work/arm.bm.s" 2> "$work/llc.log"; then
    bad "llc refused the __arm_ probe:"; head -6 "$work/llc.log" | sed 's/^/       /'; prob=1
  else
    for m in 'dmb	sy' 'dsb	sy' 'isb' 'CNTVCT_EL0' 'CNTFRQ_EL0' 'CTR_EL0' 'TPIDR_EL1' \
             'CNTV_CVAL_EL0' 'CNTV_CTL_EL0' 'DAIFSet' 'DAIFClr' 'wfi' 'dc	cvac' 'dc	civac'; do
      grep -qiF -- "$m" "$work/arm.bm.s" || { bad "the AArch64 code carries no [$m]"; prob=1; }
    done
  fi
fi
(( prob )) || note "every __arm_ primitive is its instruction, in the IR and in the assembly"
checks=$((checks + 1))
prob=0
# The target line. `emit` answers the compiler's own status; AX4008 is
# looked for by code in the ai rendering.
if emit "$axc" linux-x86_64 "$work/arm.ax" "$work/arm.x86.ll" --diagnostic-format=ai \
   || ! grep -q '^E AX4008 ' "$work/emit.log"; then
  bad "the __arm_ probe was not refused as AX4008 for linux-x86_64:"; head -4 "$work/emit.log" | sed 's/^/       /'; prob=1
fi
if emit "$axc" linux-aarch64 "$work/arm.ax" "$work/arm.la.ll" --diagnostic-format=ai \
   || ! grep -q '^E AX4008 .*needs EL1' "$work/emit.log"; then
  bad "the EL1 primitives were not refused as AX4008 for linux-aarch64:"; head -4 "$work/emit.log" | sed 's/^/       /'; prob=1
fi
if ! emit "$axc" linux-aarch64 "$work/el0.ax" "$work/el0.la.ll" --diagnostic-format=ai; then
  bad "the EL0 tier (and an EL1 primitive in an uncalled function) was refused for linux-aarch64:"; head -4 "$work/emit.log" | sed 's/^/       /'; prob=1
fi
if ! emit "$axc" linux-x86_64 "$work/vol.ax" "$work/vol.x86.ll" --diagnostic-format=ai; then
  bad "the volatile accesses were refused for linux-x86_64 - they are portable:"; head -4 "$work/emit.log" | sed 's/^/       /'; prob=1
elif [[ "$(grep -c 'store volatile' "$work/vol.x86.ll" || true)" != 8 ]]; then
  bad "the x86-64 IR carries $(grep -c 'store volatile' "$work/vol.x86.ll" || true) volatile stores, not 8"; prob=1
fi
(( prob )) || note "AX4008: __arm_ refused off AArch64, the EL1 tier off bare metal, the EL0 tier and volatile accepted, a dead use pruned"
checks=$((checks + 1))
prob=0
# And they RUN on this host: the volatile probe answers 22*2+2222*2+
# 44444444*2+6666666666666*2 = 13333422226708 - the second write of
# every pair, read back twice at its own width - and on an aarch64 host
# the EL0 tier executes.
vol_run="$(run_probe "$axc" "$work/vol.ax" vol.host)"
[[ "$vol_run" == "0 13333422226708" ]] \
  || { bad "the volatile probe answered [$vol_run] on this host, not [0 13333422226708]"; prob=1; }
if [[ "$host_arch" == aarch64 ]]; then
  el0_run="$(run_probe "$axc" "$work/el0.ax" el0.host)"
  [[ "$el0_run" == "0 true
true" ]] || { bad "the EL0 tier answered [$el0_run] on this aarch64 host, not [0 true true]"; prob=1; }
  (( prob )) || note "the volatile probe answers 13333422226708 here and the EL0 tier executes on this aarch64 host"
else
  (( prob )) || note "the volatile probe answers 13333422226708 here (an x86-64 host: the EL0 tier is refused, above)"
fi

# ---------------------------------------------------------------------
# The QEMU sections below share one runner and one precondition. The
# runner takes the machine and a timeout: A13-A15 need a GICv2 (`virt`'s
# default has moved between QEMU releases, so it is named), and a
# healthy guest here is out in a second or two, so a hang is 60s rather
# than A10's 120.
# ---------------------------------------------------------------------
qemu_live=1
command -v qemu-system-aarch64 >/dev/null 2>&1 || qemu_live=0
qemu_boot() {  # qemu_boot <elf> <uart_out> <qemu_err> [machine] [timeout]
  python3 - "$1" "$2" "$3" "${4:-virt}" "${5:-60}" <<'PY'
import subprocess, sys
elf, out, err, mach, to = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
cmd = ["qemu-system-aarch64", "-machine", mach, "-cpu", "cortex-a72",
       "-nographic", "-monitor", "none", "-no-reboot",
       "-semihosting", "-semihosting-config", "enable=on,target=native",
       "-kernel", elf]
try:
    p = subprocess.run(cmd, stdout=open(out, "wb"), stderr=open(err, "wb"), timeout=to)
    print(p.returncode)
except subprocess.TimeoutExpired:
    print("TIMEOUT")
PY
}
# A QEMU leg's precondition, said once per section: SKIP, never ok.
qemu_or_skip() {  # qemu_or_skip <section>
  if (( qemu_live )); then return 0; fi
  skip "$1: qemu-system-aarch64 is not on PATH - nothing was booted, and this is not a pass"
  return 1
}

# ---------------------------------------------------------------------
echo "== A12. the exception vector table: a fault is a status, the IRQ vector a tag =="
# ---------------------------------------------------------------------
# Every baremetal-aarch64 executable carries a vector table
# (`emitBaremetalVectors`, TRUSTED assembly: docs/embedded-guide.md
# section 5). `_start` turns the FP unit on and points VBAR_EL1 at it;
# every slot but a bound IRQ reaches `@__axiom_cpu_exception`, which
# writes the vector offset, ESR_EL1, ELR_EL1 and FAR_EL1 to the UART and
# exits 81 (MM-EXEC-16); `;@axiom:isr(irq)` wires slot 5 (current EL,
# SPx, IRQ) to a save/call/restore/`eret` entry around the tagged
# function. Before this a synchronous exception jumped through whatever
# VBAR_EL1 held at reset and the guest spun until killed.
#
# Compile-level half, every host: the table's shape in the IR, the
# `_start` writes, `+strict-align` on the bare target's attribute group
# and on no hosted one, the bound entry and its dispatch, and AX4008 for
# a binding no target can honour. QEMU half: `tests/embedded/fault.ax`
# takes an alignment fault and must exit 81 with the report.
#
# Drill: `vbar` drops VBAR_EL1's write from `_start` - the IR check
# goes red, and under QEMU the fault is a hang again.
cat > "$work/isr.ax" <<'AX'
;@axiom:isr(irq)
(:: onTick Int)
(fn (onTick)
  (+ 1 2))

(:: main Int)
(fn (main)
  0)
AX
sed 's/;@axiom:isr(irq)/;@axiom:isr(timer)/' "$work/isr.ax" > "$work/isr-name.ax"
cat > "$work/isr-two.ax" <<'AX'
;@axiom:isr(irq)
(:: first Int)
(fn (first)
  0)

;@axiom:isr(irq)
(:: second Int)
(fn (second)
  0)

(:: main Int)
(fn (main)
  0)
AX
checks=$((checks + 1))
prob=0
if ! emit "$axc" "$bm" "$blink" "$work/blink.vec.ll"; then
  bad "blink does not emit for $bm:"; sed 's/^/       /' "$work/emit.log" | head -6; prob=1
else
  n2k=$(grep -cxF 'module asm ".balign 2048"' "$work/blink.vec.ll" || true)
  nslot=$(grep -cxF 'module asm ".balign 128"' "$work/blink.vec.ll" || true)
  nfault=$(grep -cxF 'module asm "b __axiom_exc_entry"' "$work/blink.vec.ll" || true)
  [[ "$n2k" == 1 && "$nslot" == 16 && "$nfault" == 16 ]] \
    || { bad "blink's table: $n2k 2 KiB alignments, $nslot slots, $nfault fault branches - not 1, 16, 16"; prob=1; }
  for w in 'msr vbar_el1, x9' 'orr x9, x9, #0x300000' 'msr cpacr_el1, x9'; do
    awk '/^define void @_start\(\)/{on=1} on{print} on&&/^}/{exit}' "$work/blink.vec.ll" | grep -qF -- "$w" \
      || { bad "\`_start\` does not write [$w]"; prob=1; }
  done
  grep -qF '"target-features"="+strict-align"' "$work/blink.vec.ll" \
    || { bad "the bare target's attribute group lacks +strict-align"; prob=1; }
  grep -qF 'define void @__axiom_cpu_exception(' "$work/blink.vec.ll" \
    || { bad "no fault exit is defined"; prob=1; }
fi
if ! emit "$axc" "$host_target" "$blink" "$work/blink.hostvec.ll"; then
  bad "blink does not emit for the host:"; sed 's/^/       /' "$work/emit.log" | head -6; prob=1
elif grep -qE 'module asm|strict-align|__axiom_cpu_exception' "$work/blink.hostvec.ll"; then
  bad "the HOST's IR carries vector-table or strict-align lines - a hosted target must not move"; prob=1
fi
(( prob )) || note "blink carries a 2 KiB table of 16 fault slots, _start writes CPACR and VBAR, +strict-align on bare metal only"
checks=$((checks + 1))
prob=0
if ! emit "$axc" "$bm" "$work/isr.ax" "$work/isr.bm.ll"; then
  bad "the isr(irq) probe does not emit for $bm:"; sed 's/^/       /' "$work/emit.log" | head -6; prob=1
else
  nfault=$(grep -cxF 'module asm "b __axiom_exc_entry"' "$work/isr.bm.ll" || true)
  nirq=$(grep -cxF 'module asm "b __axiom_irq_entry"' "$work/isr.bm.ll" || true)
  slot5=$(grep -E '^module asm "(mov x0, #[0-9]+|b __axiom_irq_entry)"$' "$work/isr.bm.ll" | sed -n 6p)
  [[ "$nfault" == 15 && "$nirq" == 1 && "$slot5" == 'module asm "b __axiom_irq_entry"' ]] \
    || { bad "bound table: $nfault fault slots and $nirq IRQ branches, slot 5 [$slot5] - not 15, 1 and the IRQ entry"; prob=1; }
  nsave=$(grep -cE '^module asm "stp (x|q)' "$work/isr.bm.ll" || true)
  nload=$(grep -cE '^module asm "ldp (x|q)' "$work/isr.bm.ll" || true)
  [[ "$nsave" == 24 && "$nload" == 24 ]] \
    || { bad "the IRQ entry saves $nsave and restores $nload register pairs, not 24 and 24 (x0-x17, x18/x29, x30/ELR, SPSR/FPCR, 12 q pairs)"; prob=1; }
  for w in 'sub sp, sp, #592' 'add sp, sp, #592' 'eret' 'bl __axiom_irq_dispatch' 'msr elr_el1, x0' 'msr spsr_el1, x0'; do
    grep -qxF "module asm \"$w\"" "$work/isr.bm.ll" || { bad "the IRQ entry lacks [$w]"; prob=1; }
  done
  awk '/^define void @__axiom_irq_dispatch\(\)/{on=1} on{print} on&&/^}/{exit}' "$work/isr.bm.ll" > "$work/dispatch.ll"
  grep -qF 'call i64 @onTick()' "$work/dispatch.ll" \
    || { bad "the dispatch does not call the tagged handler"; prob=1; }
  grep -qF 'store i64 0, ptr @__axiom_recover_top' "$work/dispatch.ll" \
    || { bad "the dispatch leaves a recovery point armed across the handler"; prob=1; }
  grep -qF '[ptr @__axiom_cpu_exception, ptr @__axiom_irq_dispatch]' "$work/isr.bm.ll" \
    || { bad "@llvm.used does not keep both entries"; prob=1; }
fi
(( prob )) || note "isr(irq) wires slot 5 to a 592-byte save, a dispatch that calls the handler with no recovery point armed, and eret"
checks=$((checks + 1))
prob=0
if emit "$axc" linux-aarch64 "$work/isr.ax" "$work/isr.la.ll" --diagnostic-format=ai \
   || ! grep -q '^E AX4008 .*binds the IRQ exception vector' "$work/emit.log"; then
  bad "isr(irq) was not refused as AX4008 for linux-aarch64:"; head -3 "$work/emit.log" | sed 's/^/       /'; prob=1
fi
if emit "$axc" "$bm" "$work/isr-name.ax" "$work/isr-name.ll" --diagnostic-format=ai \
   || ! grep -q '^E AX4008 .*names no vector' "$work/emit.log"; then
  bad "isr(timer) was not refused as AX4008:"; head -3 "$work/emit.log" | sed 's/^/       /'; prob=1
fi
if emit "$axc" "$bm" "$work/isr-two.ax" "$work/isr-two.ll" --diagnostic-format=ai \
   || ! grep -q '^E AX4008 .*binds 2 functions' "$work/emit.log"; then
  bad "two isr(irq) handlers were not refused as AX4008:"; head -3 "$work/emit.log" | sed 's/^/       /'; prob=1
fi
(( prob )) || note "AX4008 refuses isr(irq) off bare metal, a vector name it does not bind, and two handlers for one vector"
fault="$repo_root/tests/embedded/fault.ax"
[[ -f "$fault" ]] || abort "$fault is gone; A12 has no fault probe."
if qemu_or_skip "A12 fault under QEMU"; then
  checks=$((checks + 1))
  prob=0
  if ! build_bm fault.bm "$fault" --target="$bm"; then
    bad "the fault probe does not build for $bm:"; sed 's/^/       /' "$work/fault.bm.build.log" | head -6; prob=1
  else
    st_fault="$(qemu_boot "$work/fault.bm" "$work/fault.uart" "$work/fault.qemu.err")"
    echo "     fault probe: exit $st_fault"
    sed 's/^/     | /' "$work/fault.uart" | head -4
    [[ "$st_fault" == 81 ]] \
      || { bad "the fault probe exits [$st_fault], not 81 - an unhandled CPU exception must be MM-EXEC-16's status, not a hang"; prob=1; }
    [[ "$(sed -n 1p "$work/fault.uart")" == "FAULT PROBE" ]] \
      || { bad "the UART's first line is not the boot line"; prob=1; }
    rep="$(sed -n 2p "$work/fault.uart")"
    [[ "$rep" =~ ^axiom:\ unhandled\ CPU\ exception\ at\ vector\ 0x0000000000000200\ esr\ 0x0000000096000021\ elr\ 0x[0-9a-f]{16}\ far\ 0x[0-9a-f]{15}[13579bdf]$ ]] \
      || { bad "the report is [$rep], not vector 0x200 with ESR 0x96000021 (EC 0x25 data abort, DFSC 0x21 alignment) and an odd FAR"; prob=1; }
    ! grep -q 'NOT REACHED' "$work/fault.uart" \
      || { bad "the program ran past its fault"; prob=1; }
  fi
  (( prob )) || note "an alignment fault exits 81 naming vector 0x200, ESR 0x96000021, the faulting PC and the odd address (QEMU TCG)"
fi

# ---------------------------------------------------------------------
echo "== A13. a periodic workload on the timer's interrupt, within its budgets =="
# ---------------------------------------------------------------------
# docs/assurance/demonstrators.md D-5. `main` initialises once and then
# only waits; the virtual timer's interrupt, routed through QEMU virt's
# GICv2 to the `isr(irq)` handler, counts ticks and re-arms; one run of a
# `restrict(no-alloc, no-recursion, strict)` step per tick. The program
# checks itself (the timed steps equal the same steps run straight
# through, and every counted tick is a step, a miss, or the one that
# lands after the last step) and ends `ok`.
#
# Compile-level half, every host: `scripts/axiom-report.py` under the
# restricted profile refuses nothing across the whole program - the
# handler and the step are steady roots, so an allocation reachable from
# either is RP-5 - and the stack bound read from the machine code fits
# a 2 KiB budget. QEMU half: the boot, and a drill.
#
# Drill (a copy of the PROGRAM, not the compiler): the handler's
# end-of-interrupt write deleted. The GICv2 then keeps the timer's
# interrupt active and never delivers it again, so the guest waits in
# `wfi` for ever; it must not finish, which is what shows the boot above
# rode on the interrupt and not on a loop that would end anyway.
periodic="$repo_root/tests/embedded/periodic.ax"
[[ -f "$periodic" ]] || abort "$periodic is gone; A13 has no workload."
checks=$((checks + 1))
prob=0
if ! AXIOM="$axc" python3 "$repo_root/scripts/axiom-report.py" --axiom "$axc" --profile restricted \
      --target "$bm" --stack --stack-budget 2048 "$periodic" > "$work/periodic.report" 2>&1; then
  bad "the restricted profile refuses periodic.ax, or cannot bound its stack under 2 KiB:"
  tail -8 "$work/periodic.report" | sed 's/^/       /'; prob=1
elif ! grep -q '^verdict: no refusal$' "$work/periodic.report"; then
  bad "the report on periodic.ax ends without its verdict line:"; tail -4 "$work/periodic.report" | sed 's/^/       /'; prob=1
fi
(( prob )) || note "periodic.ax: the restricted profile refuses nothing; stack $(grep -o '_start: [0-9]* bytes' "$work/periodic.report" | head -1), the handler's own $(grep -o 'onIrq: [0-9]* bytes' "$work/periodic.report" | head -1 | sed 's/onIrq: //'), under a 2 KiB budget"
if qemu_or_skip "A13 periodic under QEMU"; then
  checks=$((checks + 1))
  prob=0
  if ! build_bm periodic.bm "$periodic" --target="$bm"; then
    bad "periodic.ax does not build for $bm:"; sed 's/^/       /' "$work/periodic.bm.build.log" | head -6; prob=1
  else
    st="$(qemu_boot "$work/periodic.bm" "$work/periodic.uart" "$work/periodic.qemu.err" virt,gic-version=2)"
    echo "     periodic: exit $st"
    sed 's/^/     | /' "$work/periodic.uart" | head -4
    [[ "$st" == 0 ]] || { bad "periodic exits [$st], not 0"; prob=1; }
    grep -qE '^periodic: 20 steps on [0-9]+ ticks, [0-9]+ missed, 0 other interrupts$' "$work/periodic.uart" \
      || { bad "periodic's first line is not twenty steps with no stray interrupt"; prob=1; }
    grep -qE '^periodic: checksum [0-9]+ equals the straight run$' "$work/periodic.uart" \
      || { bad "periodic's timed steps did not equal the straight run"; prob=1; }
    [[ "$(tail -1 "$work/periodic.uart")" == ok ]] || { bad "periodic did not end ok"; prob=1; }
  fi
  (( prob )) || note "twenty steps on twenty-odd real timer interrupts through the GICv2, equal to the straight run (QEMU TCG: the lateness it prints is the emulator's)"
  checks=$((checks + 1))
  if python3 - "$periodic" "$work/periodic-noeoi.ax" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = "      (__vstore32 (+ gicc 16) iar)\n      0"
if s.count(old) != 1:
    sys.exit("the end-of-interrupt write is not in periodic.ax as the drill expects")
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, "      0"))
PY
  then
    if build_bm periodic-noeoi.bm "$work/periodic-noeoi.ax" --target="$bm"; then
      st="$(qemu_boot "$work/periodic-noeoi.bm" "$work/periodic-noeoi.uart" "$work/periodic-noeoi.qemu.err" virt,gic-version=2 20)"
      if [[ "$st" == TIMEOUT ]] && ! grep -qx ok "$work/periodic-noeoi.uart"; then
        note "drill: with the end-of-interrupt write deleted the timer is never delivered again and the guest does not finish"
      else
        bad "drill: without the end-of-interrupt write the guest still answered [$st] - the boot above cannot show the interrupt did the work"
      fi
    else
      bad "drill: the copy without the end-of-interrupt write does not build"; sed 's/^/       /' "$work/periodic-noeoi.bm.build.log" | head -4
    fi
  else
    bad "drill: the seam is gone from periodic.ax, so the drill proves nothing"
  fi
fi

# ---------------------------------------------------------------------
echo "== A14. a driver with interrupt and DMA ownership boundaries =="
# ---------------------------------------------------------------------
# docs/assurance/demonstrators.md D-6. QEMU virt's fw_cfg has a DMA
# engine: it reads a descriptor from guest memory and writes the item
# into a guest buffer. `tests/embedded/dma.ax` reads the file directory
# that way under a CPU/device ownership protocol whose every step is a
# contract checked on every call (give: clean, DSB, device owns; take:
# DSB, invalidate, DSB, CPU owns; a CPU read only while the CPU owns
# it), with the virtual timer's interrupt as the completion deadline,
# then reads the same directory a byte at a time through the data
# register. The two copies must be equal, and the directory non-empty:
# the DMA really wrote the buffer.
#
# Two drills, each a copy of the PROGRAM:
#   misuse  `dmaTake` deleted, so the driver reads the buffer while the
#           device owns it: the contract must stop it, status 80;
#   silent  the doorbell deleted, so the transfer never starts: the
#           timer's interrupt must end the wait, `dma: timed out`, and
#           the program answers 1 rather than hanging.
# With the MMU off the data cache is off (docs/embedded-guide.md section
# 6), so the cache maintenance is exercised for ordering only, and TCG
# models no reordering a missing barrier would expose: deleting a DSB
# cannot turn this red here, and no drill claims it does.
dmaprog="$repo_root/tests/embedded/dma.ax"
[[ -f "$dmaprog" ]] || abort "$dmaprog is gone; A14 has no driver."
if qemu_or_skip "A14 DMA driver under QEMU"; then
  checks=$((checks + 1))
  prob=0
  if ! build_bm dma.bm "$dmaprog" --target="$bm"; then
    bad "dma.ax does not build for $bm:"; sed 's/^/       /' "$work/dma.bm.build.log" | head -6; prob=1
  else
    st="$(qemu_boot "$work/dma.bm" "$work/dma.uart" "$work/dma.qemu.err" virt,gic-version=2)"
    echo "     dma: exit $st"
    sed 's/^/     | /' "$work/dma.uart" | head -4
    [[ "$st" == 0 ]] || { bad "dma exits [$st], not 0"; prob=1; }
    grep -qx 'dma: the interface answers QEMU CFG' "$work/dma.uart" || { bad "fw_cfg's DMA signature was not read"; prob=1; }
    grep -qx 'dma: transfer complete' "$work/dma.uart" || { bad "the transfer did not complete"; prob=1; }
    grep -qE '^dma: [1-9][0-9]* files in the directory, 0 of 4096 bytes differ from the data register.s copy$' "$work/dma.uart" \
      || { bad "the DMA copy is empty or differs from the data register's"; prob=1; }
    [[ "$(tail -1 "$work/dma.uart")" == ok ]] || { bad "dma did not end ok"; prob=1; }
  fi
  (( prob )) || note "fw_cfg's directory by DMA under the ownership protocol, byte-equal to the data register's copy (QEMU TCG)"
  for drill in misuse silent; do
    checks=$((checks + 1))
    if ! python3 - "$dmaprog" "$work/dma-$drill.ax" "$drill" <<'PY'
import sys
src, dst, drill = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src, encoding="utf-8").read()
if drill == "misuse":
    old, new = "          (dmaTake b)\n          (pioRead copy len itemFileDir)", "          (pioRead copy len itemFileDir)"
else:
    old = ("    (__vstore32 (+ cfgBase 16) (bswap32 (& (>> desc 32) 4294967295)))\n"
           "    (__vstore32 (+ cfgBase 20) (bswap32 (& desc 4294967295)))")
    new = "    0"
if s.count(old) != 1:
    sys.exit("the %s seam is not in dma.ax as the drill expects" % drill)
open(dst, "w", encoding="utf-8").write(s.replace(old, new))
PY
    then
      bad "drill $drill: its seam is gone from dma.ax, so it proves nothing"; continue
    fi
    if ! build_bm "dma-$drill.bm" "$work/dma-$drill.ax" --target="$bm"; then
      bad "drill $drill: the copy does not build"; sed 's/^/       /' "$work/dma-$drill.bm.build.log" | head -4; continue
    fi
    st="$(qemu_boot "$work/dma-$drill.bm" "$work/dma-$drill.uart" "$work/dma-$drill.qemu.err" virt,gic-version=2 30)"
    if [[ "$drill" == misuse ]]; then
      if [[ "$st" == 80 ]] && grep -q 'precondition failed in `dmaByte`' "$work/dma-$drill.uart"; then
        note "drill misuse: a CPU read while the device owns the buffer is stopped by its contract (80)"
      else
        bad "drill misuse: a read of a device-owned buffer answered [$st] - the ownership contract did not stop it"
      fi
    else
      if [[ "$st" == 1 ]] && grep -qx 'dma: timed out' "$work/dma-$drill.uart"; then
        note "drill silent: a transfer that never starts ends at the timer interrupt's deadline, not in a hang"
      else
        bad "drill silent: a transfer never started answered [$st] - the deadline did not end the wait"
      fi
    fi
  done
fi

echo
if (( skipped > 0 )); then
  echo "check-embedded: $skipped QEMU leg(s) SKIPPED - booted nothing, proved nothing, and are not counted below"
fi
if (( failed > 0 )); then
  echo "check-embedded: $failed of $checks checks failed"
  exit 1
fi
echo "check-embedded: $checks checks - the arena's chunk size is a target constant,"
echo "                mmap is one of two strategies, and traps write or stay silent"
echo "                per target - and where the bare-metal port and QEMU are both"
echo "                present, blink boots under QEMU with its UART bytes, its exit"
echo "                status and the oversized 70 asserted; the device primitives"
echo "                lower to volatile accesses at their widths and to their"
echo "                AArch64 instructions, and AX4008 refuses what a target lacks;"
echo "                a periodic step runs on the timer's interrupt within its"
echo "                budgets, and a DMA driver keeps its ownership protocol"
