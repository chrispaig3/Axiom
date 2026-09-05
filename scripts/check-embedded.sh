#!/usr/bin/env bash
# ---------------------------------------------------------------------
# The arena's two assumptions about a hosted operating system, removed
# and gated. docs/embedded-proposal.md 4.1 and 4.2, and the gate its
# section 8 names for both rows.
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
#       distinct syscalls, and its size is inside the flash budget for
#       its object format. Those are section 2's figures and the port is
#       priced on them. The import set and the band are per FORMAT, not
#       per host: section 2 measured a Mach-O, and the identical program
#       as an ELF carries crt1's six imports and 71,168 bytes. Asserting
#       Mach-O's zero and Mach-O's 24 KiB on both is a check only the
#       machine that wrote it can pass - see the paragraphs at A3.
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
#
# ABLATIONS. `AXIOM_ABLATE=<name>` copies `self_host/` to a scratch
# directory, breaks ONE thing in `codegen.ax` there, builds every
# compiler this gate uses from the broken copy, and the gate must FAIL.
# The patch is applied by exact string match by
# `scripts/lib/embedded-patch.py`, which ABORTS if the string is not
# there: an ablation that silently does not apply is a drill proving the
# gate can pass. `--ablations` runs all six and requires each to go red.
#
#   chunk     every target answers 4 KiB                   -> A1
#   literal   `refill:` goes back to the hardcoded 1 MiB   -> A2, A4
#   grain     the grain stops following the chunk          -> A4
#   strategy  `emitRuntimeMap` ignores the static arena    -> A5
#   cursor    the carve never advances its cursor          -> A6
#   oomsig    the carve never answers 0, so exhaustion is
#             never seen                                   -> A6
#
# WHAT THIS GATE DOES NOT COVER, said here rather than left to be
# discovered: section 6's QEMU reference port. There is no bare-metal
# TARGET in the tree - no triple, no `Sys/Platform.baremetal-*.ax`, no
# linker script - so nothing here executes on a device. What it does
# establish is that the two things the port needs from the COMPILER are
# per-target values a port can set, that setting them changes the
# emitted program in the ways they claim to, and that a program built
# with them set runs and traps correctly. 4.3, 4.4 and 4.5 remain
# proposed.
#
# Usage:
#   scripts/check-embedded.sh              # the gate
#   scripts/check-embedded.sh --ablations  # the six drills, each red
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
  for ab in chunk literal grain strategy cursor oomsig; do
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
note() { echo "ok   $1"; }
bad()  { echo "FAIL $1"; failed=$((failed + 1)); }
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
  if ! ( cd "$src_root" && "$axiom" build --input self_host/main.ax --output "$work/axc-abl" ) \
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
if (( n_codes != 7 )); then
  abort "read $n_codes target codes out of targetCode, expected 7 - the parse broke,
       and every assertion below is written in terms of those codes."
fi
code_of() { printf '%s\n' "$codes_raw" | awk -v n="$1" '$1==n{print $2}'; }

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

emit() {  # emit <compiler> <target> <source> <out>
  "$1" --target="$2" emit-llvm "$3" -o "$4" > "$work/emit.log" 2>&1
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
  # AND THE BAND IS PER FORMAT, for the same reason the import set is.
  # 24 KiB is the Mach-O measurement; the identical program is 71,168
  # bytes as an ELF, because `cc` links crt1, the ELF program headers
  # and the `.eh_frame`/`.note` sections a Mach-O keeps elsewhere. That
  # is not the runtime growing, and one band across both formats can
  # only be satisfied by whichever host wrote it. The proposal's 24 KiB
  # is a claim about the FREESTANDING build - the statically-arena'd
  # target A5 and A6 exercise, which links no crt at all - so it stays
  # exactly where it was measured and ELF gets its own, measured here.
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
    elf)   lo=32768; hi=98304 ;;   # ELF + crt1: measured 71,168
    macho) lo=8192;  hi=24576 ;;   # Mach-O, and the proposal's budget
    *)     lo=0;     hi=0     ;;   # a format A3 has no band for: fails below
  esac
  if (( hi == 0 )); then
    bad "the minimal program is a $fmt object, and A3 has no size band for that format"
    ok=0
  elif (( size > hi || size < lo )); then
    bad "the minimal program is $size bytes; the budget for this format ($fmt) is $lo..$hi"
    ok=0
  fi
  (( ok )) && note "$size bytes, $undef import(s) and none outside the platform's startup set, exactly 3 distinct syscalls"
fi

# ---------------------------------------------------------------------
echo "== building the variant compiler: 4 KiB chunk on $t41, static arena on $host_target =="
# ---------------------------------------------------------------------
mkdir -p "$work/vtree"
cp -a "$src_root/self_host" "$work/vtree/self_host"
python3 "$repo_root/scripts/lib/embedded-patch.py" \
  "variant:$code41:$host_code" "$work/vtree/self_host/codegen.ax" || exit 1
if ! ( cd "$work/vtree" && "$axiom" build --input self_host/main.ax --output "$work/vaxc" ) \
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
gone="$(comm -23 <(syscall_nums "$hll") <(syscall_nums "$sll") | tr '\n' ' ')"
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
run_probe() {  # run_probe <compiler> <source> <tag> -> "<status> <stdout>"
  local st out
  if ! "$1" build --input "$2" --output "$work/$3" --opt 1 > "$work/$3.build.log" 2>&1; then
    echo "BUILDFAIL"
    return
  fi
  out="$("$work/$3" 2> "$work/$3.err")"
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

echo
if (( failed > 0 )); then
  echo "check-embedded: $failed of $checks checks failed"
  exit 1
fi
echo "check-embedded: $checks checks - the arena's chunk size is a target constant"
echo "                and mmap is one of two strategies, with every supported target"
echo "                emitting the bytes it emitted before either was true"
