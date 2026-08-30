#!/usr/bin/env bash
# Assert that a dying Axiom program says WHICH FUNCTION died.
#
# WHAT THIS EXISTS FOR. Until 2026-08-24 a trapping program yielded a
# status and one line - "axiom: division by zero" and 72 - which answers
# what happened and nothing at all about where. `check-stack-depth.sh`
# records three SIGSEGVs whose cause was found only by attaching
# `lldb`, and a worker dying inside a pre-forked pool has no `lldb`
# attached and no second chance: the supervisor respawns it and the
# frame that died is gone. Function-level frames answer most of
# production triage; that is what is gated here.
#
# THE MECHANISM, in three pieces, none of them debug metadata:
#   1. `"frame-pointer"="all"` on the module's one attribute group, so
#      the chain is walkable on all four targets. Checked in §5.
#   2. `@__axiom_symtab`, an address-beside-name table over every symbol
#      the module defines, emitted as ordinary constant data. Checked in
#      §6.
#   3. `@__axiom_backtrace`, which walks the chain and resolves each
#      return address. Checked in §1-§4.
# `-g` is still never passed, there is still no `!dbg` anywhere, and the
# committed seed still compiles `self_host/` unchanged - the whole
# addition is emitted text.
#
# ------------------------------------------------------------------
# THE ROADMAP ASKED FOR SOMETHING THIS GATE CANNOT ASSERT, AND THE
# MEASUREMENT IS WHY.
#
# The roadmap's acceptance line reads: "a 5-deep chain names five
# functions, at every optimisation level." The first half holds and is
# §1. The second half does not, and it is not the backtracer that
# fails it - it is that AT `--opt 1` AND ABOVE THERE IS NO FIVE-DEEP
# CHAIN. Measured on this host, darwin-aarch64, LLVM 22.1.8, with the
# five-function chain in §1 and a divisor read from `sysArgc` so
# nothing folds:
#
#   --opt 0   frames: __axiom_div_by_zero e5 d4 c3 b2 a1 __axiom_user_main main
#   --opt 1   frames: __axiom_div_by_zero main
#   --opt 2   frames: __axiom_div_by_zero main
#   --opt 3   frames: __axiom_div_by_zero main
#
# Disassembling the `--opt 1` binary shows why: `_main` contains the
# whole chain and ends `bl ___axiom_div_by_zero`. The five frames were
# not lost by the walker, they were never pushed.
#
# Two ways to satisfy the sentence as written were tried and are
# recorded because they are the obvious ones:
#
#   - MUTUAL RECURSION, a1 -> b2 -> c3 -> d4 -> e5 -> a1, on the theory
#     that a call inside a strongly connected component is one the
#     inliner leaves alone. It is not: at every level above 0 LLVM
#     inlined a1 and b2 into main and left three frames, not five.
#   - AN INDIRECT CALL through a lambda pulled out of a `Vec`, which no
#     optimiser can devirtualise. `__call_word` on a lambda handle
#     faulted (exit 138) before reaching the trap; making that work is
#     a separate question about the lambda calling convention and does
#     not belong in this gate.
#
# So this gate asserts the thing that is actually true and is worth
# more: THE WALKER NAMES EXACTLY THE FRAMES THAT ARE ON THE STACK, AT
# EVERY OPTIMISATION LEVEL. §1 pins all eight frames byte for byte
# where all eight exist. §2 checks every level, and checks each printed
# name against `nm` - a source outside the compiler, as this
# repository's gates are required to have - so a walker that invented
# a plausible name would fail even where the frame count is not
# predictable.
#
# That distinction is not academic. §3 exists because the first
# implementation DID invent a plausible name.
# ------------------------------------------------------------------

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0

ok()   { echo "ok   $1"; checks=$((checks + 1)); }
bad()  { echo "FAIL $1"; checks=$((checks + 1)); failed=$((failed + 1)); }
want() { # want <label> <expected> <actual>
  checks=$((checks + 1))
  if [[ "$2" == "$3" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    diff <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/     /' || true
    failed=$((failed + 1))
  fi
}

# The five-deep chain. `sysArgc` is read at run time, so the divisor is
# not a constant and neither the trap nor the chain can be folded away
# before `llc` sees them.
cat > "$work/chain.ax" <<'PROBE'
(import Sys)

(pub :: e5 (-> Int Int))

(pub fn (e5 n) (+ 1 (/ 100 n)))

(pub :: d4 (-> Int Int))

(pub fn (d4 n) (+ 1 (e5 n)))

(pub :: c3 (-> Int Int))

(pub fn (c3 n) (+ 1 (d4 n)))

(pub :: b2 (-> Int Int))

(pub fn (b2 n) (+ 1 (c3 n)))

(pub :: a1 (-> Int Int))

(pub fn (a1 n) (+ 1 (b2 n)))

(pub :: main Int)

;@axiom:effect(io)
(pub fn (main) (a1 (- sysArgc 1)))
PROBE

build_at() { # build_at <opt> <out>
  "$axc" build --input "$work/chain.ax" --output "$2" --opt "$1" \
    > "$work/build.log" 2>&1 || {
      echo "FAIL: the probe would not build at --opt $1" >&2
      sed 's/^/    /' "$work/build.log" | head -20 >&2
      exit 1
    }
}

rc=0
run_err() { # run_err <binary> -> stderr on stdout, status in $rc
  rc=0
  set +e
  "$1" > /dev/null 2> "$work/err.txt"
  printf '%s' "$?" > "$work/rc.txt"
  set -e
  cat "$work/err.txt"
}
last_rc() { cat "$work/rc.txt"; }

echo "--- 1. the whole trace, byte for byte, where every frame exists ---"

build_at 0 "$work/chain0"
got="$(run_err "$work/chain0")"
o0_status="$(last_rc)"

# Eight frames and not seven: `__axiom_user_main` is the compiler's
# rename of the user's `main`, and `main` is the argv wrapper the
# emitter writes around it. Both are real frames and both are named,
# because a trace that silently drops the runtime's own frames is a
# trace whose omissions the reader cannot know about.
read -r -d '' expected <<'TRACE' || true
axiom: division by zero
axiom: backtrace (most recent call first)
  at __axiom_div_by_zero
  at e5
  at d4
  at c3
  at b2
  at a1
  at __axiom_user_main
  at main
TRACE

want "--opt 0: the five-deep chain names all five, in order, and stops at main" \
     "$expected" "$got"

if [[ "$o0_status" == "72" ]]; then
  ok "--opt 0: the status is still 72 - a backtrace does not change how the process dies"
else
  bad "--opt 0: status $o0_status, expected 72"
fi

echo
echo "--- 2. every optimisation level: every name printed is a real frame ---"

# THE INDEPENDENT SOURCE. `nm` reads the linked binary's symbol table,
# which the compiler does not write - the linker does, from the object
# `llc` produced. A walker that printed a name it had invented, or read
# a name out of the wrong table entry, passes every check that compares
# its output against itself and fails this one.
#
# `symbol_names <binary>` prints one symbol name per line. `nm -j` is
# the spelling Apple's and GNU's nm share; FreeBSD's base `nm` is ELF
# Tool Chain's, which has no `-j` and exits 1 - under `set -eo
# pipefail` that ended this gate silently after "--opt 0: 8 frames
# named" on FreeBSD 14.4/arm64 (2026-08-29) - and FreeBSD's base
# `llvm-nm` takes it. Whichever answers is the linker's table either
# way; an empty answer fails the comparison below by construction,
# because every printed frame is then a name no table has.
symbol_names() {
  nm -j "$1" 2>/dev/null && return 0
  llvm-nm -j "$1" 2>/dev/null
}
for opt in 0 1 2 3; do
  build_at "$opt" "$work/c$opt"
  trace="$(run_err "$work/c$opt")"
  st="$(last_rc)"

  hdr="$(printf '%s\n' "$trace" | grep -c '^axiom: backtrace' || true)"
  if [[ "$hdr" == "1" ]]; then
    ok "--opt $opt: a backtrace is printed"
  else
    bad "--opt $opt: $hdr backtrace headers, expected 1"
  fi

  frames="$(printf '%s\n' "$trace" | sed -n 's/^  at //p')"
  nframes="$(printf '%s\n' "$frames" | grep -c . || true)"

  # A trace of zero frames is a trace that agrees with everything.
  if (( nframes >= 2 )); then
    ok "--opt $opt: $nframes frames named"
  else
    bad "--opt $opt: $nframes frames named, and a trace this short asserts nothing"
  fi

  # `nm` prints Mach-O symbols with a leading underscore and ELF
  # symbols without one, so both spellings are accepted; what is
  # asserted is that the name EXISTS, not how the platform spells it.
  #
  # ACCEPTED, not REWRITTEN, and the difference was a Linux-only red on
  # trunk. This was one `sed 's/^_//'`, which is the Mach-O convention
  # applied unconditionally: on ELF there is no prefix to strip, so it
  # ate a real character and turned `__axiom_div_by_zero` into
  # `_axiom_div_by_zero`. Every emitted-runtime name is `__`-prefixed
  # and every one of them failed; `main`, `a1`..`e5` passed, because
  # they have no underscore for the sed to take. The comment above said
  # the right thing and the line below it did not do it.
  #
  # Both spellings now go in the set, so a name matches whichever
  # platform spelled it.
  symbol_names "$work/c$opt" | sed -e 'p' -e 's/^_//' | LC_ALL=C sort -u > "$work/syms.txt"
  unknown=""
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    grep -qxF "$f" "$work/syms.txt" || unknown="$unknown $f"
  done <<< "$frames"
  if [[ -z "$unknown" ]]; then
    ok "--opt $opt: every name printed is a symbol nm finds in the binary"
  else
    bad "--opt $opt: names no symbol table has:$unknown"
  fi

  first="$(printf '%s\n' "$frames" | head -1)"
  last="$(printf '%s\n' "$frames" | grep . | tail -1)"
  [[ "$first" == "__axiom_div_by_zero" ]] \
    && ok "--opt $opt: the deepest frame is the trap" \
    || bad "--opt $opt: the deepest frame is \`$first\`, expected __axiom_div_by_zero"

  # The walk STOPS at `main`. Above it the frames belong to the C
  # runtime, this module's table has no entry for any of them, and the
  # lookup would answer with whichever of our functions happens to lie
  # below a libc address. Before the stop existed, `--opt 0` printed a
  # trailing `at __axiom_user_main` UNDER `at main` - a frame that is
  # not on the stack, named with the same confidence as the seven that
  # are.
  [[ "$last" == "main" ]] \
    && ok "--opt $opt: the walk stops at main" \
    || bad "--opt $opt: the last frame is \`$last\`, expected main"

  [[ "$st" == "72" ]] \
    && ok "--opt $opt: exit 72" \
    || bad "--opt $opt: exit $st, expected 72"
done

echo
echo "--- 3. the return address is resolved at ra-1, not ra ---"

# THE BUG THIS PINS, because it is the one the first implementation
# shipped and it is invisible to any check that does not know the
# layout. A return address points at the byte AFTER the call. When the
# call is the caller's LAST instruction, that byte is the next
# function's entry, and a nearest-preceding-symbol lookup answers with
# the next function - a real name, a real symbol, and the wrong frame.
#
# Measured before the fix, darwin-aarch64 at --opt 1: `_main` ends
# `bl ___axiom_div_by_zero` at 0x528 and `_axiom_alloc` begins at
# 0x52c, and the frame that was `main` printed as `axiom_alloc`. The
# program allocates nothing.
#
# So the assertion is not "the trace looks right" but the specific
# wrong answer: at every level above 0 the frame under the trap is
# `main`, and it is not `axiom_alloc`.
for opt in 1 2 3; do
  trace="$(run_err "$work/c$opt")"
  under="$(printf '%s\n' "$trace" | sed -n 's/^  at //p' | sed -n '2p')"
  if [[ "$under" == "main" ]]; then
    ok "--opt $opt: the frame under the trap is main"
  else
    bad "--opt $opt: the frame under the trap is \`$under\` - if it is \`axiom_alloc\`, the lookup went back to resolving ra rather than ra-1"
  fi
done

echo
echo "--- 4. all three traps, and each one names itself first ---"

# The family is `emitDivTrap` (72), `emitOomTrap` (70) and
# `emitUnhandledTrap` (71). All three are on the same emitted shape and
# all three must carry the trace; the unhandled-effect one is emitted
# only when a program declares an effect, which is exactly the kind of
# conditional emission that gets left behind.
# 2^60, the size `tests/stdlib/314-out-of-memory.ax` uses and for the
# reason it records: macOS overcommits, so a request for 1 TiB
# SUCCEEDS and never reaches the failure path, and the size has to be
# past the user address space on every target so the mapping is
# refused rather than merely unbacked. It was 2^47 until FreeBSD
# 14.4/arm64 granted that (48-bit user space, no overcommit
# accounting); a number that fits somewhere makes this probe exit 0
# there and assert nothing, which is how the number was rediscovered
# the first time too.
cat > "$work/oom.ax" <<'PROBE'
(import Mem)

(pub :: outer Int)

(pub fn (outer) (memAlloc 1152921504606846976))

(pub :: main Int)

(pub fn (main) outer)
PROBE

cat > "$work/ue.ax" <<'PROBE'
;@axiom:unhandled(trap)
(effect Ask (ask :: (-> Int Int)))

(pub :: main Int)

;@axiom:effect(Ask)
(pub fn (main) (ask 1))
PROBE

for pair in "oom:70:__axiom_out_of_memory" "ue:71:__axiom_unhandled_effect"; do
  name="${pair%%:*}"; rest="${pair#*:}"; status="${rest%%:*}"; sym="${rest#*:}"
  if ! "$axc" build --input "$work/$name.ax" --output "$work/$name" --opt 0 \
       > "$work/build.log" 2>&1; then
    bad "the $name probe would not build"
    sed 's/^/     /' "$work/build.log" | head -10
    continue
  fi
  trace="$(run_err "$work/$name")"
  st="$(last_rc)"
  first="$(printf '%s\n' "$trace" | sed -n 's/^  at //p' | head -1)"
  [[ "$st" == "$status" ]] \
    && ok "$name: exit $status" \
    || bad "$name: exit $st, expected $status"
  [[ "$first" == "$sym" ]] \
    && ok "$name: the deepest frame is $sym" \
    || bad "$name: the deepest frame is \`$first\`, expected $sym"
  printf '%s\n' "$trace" | grep -q "^  at main$" \
    && ok "$name: the trace reaches main" \
    || bad "$name: the trace never reaches main"
done

echo
echo "--- 5. the frame pointer is kept on every target, and the attribute is why ---"

# FIVE OF THE SIX TARGETS CANNOT BE RUN HERE, but all six can be
# ASSEMBLED here, which is the technique `check-cross-targets.sh`
# already rests on. So the assertion is made on the prologue `llc`
# emits rather than on a program that ran.
#
# A CORRECTION, because the first draft of this gate carried the wrong
# claim in this comment. It said Darwin/arm64 keeps a frame pointer by
# ABI and that ablating the attribute there would change nothing, so
# the ablation would discriminate on three targets and not four.
# Measured: it discriminates on ALL FOUR. The confusion is that
# Darwin/arm64 does emit `stp x29, x30, [sp, #-16]!` without the
# attribute - it saves the pair - but it does not follow it with
# `mov x29, sp`, so x29 still holds the CALLER frame and the chain is
# not walkable. Saving the register and establishing the frame pointer
# are different things, and only the second one is what a walker needs;
# `___axiom_div_by_zero` at --opt 1 is a function in the tree that does
# the first and not the second. That is why the test below greps for
# `mov x29, sp` and not for `stp`.
#
# So the assertion is made on the prologue `llc` emits, per target,
# with and without the attribute. That is a live ablation rather than a
# recorded one: it costs four `llc` invocations and no compiler build.
# The backend names `llc --version` prints, which are not the target
# triples: AArch64 and X86, spelled as `check-cross-targets.sh` spells
# them.
for arch in AArch64 X86; do
  llc --version | grep -q "$arch" || {
    echo "error: this llc has no $arch backend; cannot verify every target" >&2
    exit 1
  }
done

fp_probe() { # fp_probe <target> <ir> -> prints "kept" or "omitted"
  llc -O2 -relocation-model=pic -filetype=asm "$2" -o "$work/fp.s" 2>/dev/null
  # `b2` is the middle of the chain: non-leaf, and not the function the
  # trap is in, so nothing about it forces a frame pointer except the
  # attribute.
  body="$(awk '/^_?b2:/{f=1;next} f&&/^_?[A-Za-z_.]+:/{exit} f' "$work/fp.s")"
  if [[ "$1" == *aarch64 ]]; then
    printf '%s\n' "$body" | grep -qE 'mov[[:space:]]+x29, sp' && echo kept || echo omitted
  else
    printf '%s\n' "$body" | grep -qE 'movq[[:space:]]+%rsp, %rbp' && echo kept || echo omitted
  fi
}

ablated=0
for target in darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64 freebsd-x86_64 freebsd-aarch64; do
  "$axc" --target="$target" emit-llvm "$work/chain.ax" -o "$work/t.ll" >/dev/null 2>&1

  grep -q '"frame-pointer"="all"' "$work/t.ll" \
    && ok "[$target] the attribute group carries \"frame-pointer\"=\"all\"" \
    || bad "[$target] no frame-pointer attribute in the emitted module"

  [[ "$(fp_probe "$target" "$work/t.ll")" == "kept" ]] \
    && ok "[$target] llc -O2 establishes a frame pointer in a non-leaf function" \
    || bad "[$target] llc -O2 emitted no frame pointer - the chain is not walkable"

  # THE ABLATION, run rather than recorded: take the attribute away and
  # assemble the same module again.
  sed 's/ "frame-pointer"="all"//' "$work/t.ll" > "$work/t.noattr.ll"
  if [[ "$(fp_probe "$target" "$work/t.noattr.ll")" == "omitted" ]]; then
    ok "[$target] ablation: without the attribute the frame pointer is gone"
    ablated=$((ablated + 1))
  else
    # Not a failure on its own - a target whose ABI mandates a frame
    # pointer would land here honestly, and the positive check above
    # still holds for it. The floor below is what keeps a run where
    # NOTHING discriminates from reading as a pass.
    ok "[$target] ablation: the frame pointer survives the attribute being removed"
  fi
done

# An ablation that never fires is not an ablation. All four
# discriminated on 2026-08-24, and all six on 2026-08-29 when the
# FreeBSD pair joined; the floor is one below the count, so that a
# future toolchain making one target keep frame pointers by default is
# not a spurious failure, while a run where the attribute has stopped
# mattering anywhere still goes red.
if (( ablated >= 5 )); then
  ok "the ablation discriminates on $ablated of 6 targets (6 on 2026-08-29)"
else
  bad "the ablation changed nothing on $((6 - ablated)) of 6 targets - it proves nothing"
fi

echo
echo "--- 6. the symbol table is complete, and not empty ---"

"$axc" emit-llvm "$work/chain.ax" -o "$work/chain.ll" >/dev/null 2>&1

defines="$(grep -c '^define ' "$work/chain.ll" || true)"
rows="$(sed -n '/^@__axiom_symtab = /,/^\]/p' "$work/chain.ll" | grep -c 'ptrtoint' || true)"
stated="$(sed -n 's/^@__axiom_symtab_n = internal constant i64 //p' "$work/chain.ll")"

# The walker resolves a return address to the greatest table entry at
# or below it, so a function MISSING from the table is not a gap - it
# is a wrong answer, silently attributed to whichever function precedes
# it. Completeness is therefore the property, not coverage: every
# `define` in the module, including the lifted lambdas, the thunks, the
# argv wrapper and the runtime helpers, or the trace lies.
#
# `defines` counts the walker's own two, which are emitted after the
# table is built and are deliberately not in it: `@__axiom_backtrace`
# never appears as a frame (the first return address read is the one in
# ITS frame, which is its caller) and `@__axiom_bt_name` has returned
# before anything is read.
want "every define is in the table, but for the walker's own two" \
     "$((defines - 2))" "$rows"
want "the table states its own row count" "$rows" "$stated"

if (( rows >= 200 )); then
  ok "the table has $rows entries - a probe importing Sys had 275 on 2026-08-24"
else
  bad "the table has only $rows entries; an empty table resolves every address to <unknown>"
fi

# And the names in it must be the symbols the linker emitted. This is
# the same `nm` cross-check as §2, applied to the table rather than to
# one trace, so a name mangled differently in the table than in the
# `define` would be caught even if no frame ever landed on it.
# Both spellings, for the reason §2 records: stripping the Mach-O
# prefix unconditionally eats a real character on ELF.
symbol_names "$work/chain0" | sed -e 'p' -e 's/^_//' | LC_ALL=C sort -u > "$work/syms.txt"
missing=0
while IFS= read -r sym; do
  [[ -n "$sym" ]] || continue
  grep -qxF "$sym" "$work/syms.txt" || missing=$((missing + 1))
done < <(grep -o 'ptrtoint (ptr @[A-Za-z0-9_.$]* to i64), i64 ptrtoint (ptr @__axiom_symn' \
           "$work/chain.ll" | sed 's/ptrtoint (ptr @//; s/ to i64.*//')
# What is asserted is the direction that can be wrong: names in the
# table that the linker never emitted. `internal` symbols can be
# stripped, so a small residue would be honest - but a LARGE one would
# mean the table is naming things that do not exist, and the walker
# would be resolving addresses against fiction. 0 of 275 were missing
# on 2026-08-24.
found=$((rows - missing))
if (( missing * 4 <= rows && found >= 20 )); then
  ok "$found of $rows table names resolve in the linked symbol table ($missing do not)"
else
  bad "$missing of $rows table names are in no symbol table - the table names functions the linker never emitted"
fi

echo
if (( failed > 0 )); then
  echo "check-backtrace: $failed of $checks checks failed"
  exit 1
fi
echo "check-backtrace: $checks checks - a dying program names its frames, the"
echo "                 names are symbols nm confirms, the walk stops where this"
echo "                 module's table ends, and the attribute that makes the"
echo "                 chain walkable is load-bearing on every target"
