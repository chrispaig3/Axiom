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

# check_map <label> <trace> <map> <exact> [count]: every LOCATED
# frame (`at FN FILE:L:C`) must match a map row byte for byte, and
# with exact=1 the located multiset must equal the map
# (order-insensitive). Map rows are `FN FILE:L:C`, one per expected
# located frame - duplicates allowed (recursion prints one row per
# frame, all alike except the innermost). Bare frames (`at FN`)
# assert nothing either way: runtime helpers and generated wrappers
# have no source node. `__axiom_user_main` needs no exemption: it IS
# the user's renamed main, so calls in its body attribute exactly
# like any user function's (a body with no calls stays bare, as
# `oom` shows). Always returns 0 (like `bad`), so bare calls are safe
# under `set -e`; the verdict is in $map_failed, and failures count
# unless count is 0 - the tamper probe below expects the mismatch,
# and counting it would fail the gate for passing.
map_failed=0
check_map() {
  local label="$1" trace="$2" map="$3" exact="$4" count="${5:-1}"
  map_failed=0
  # The filters end `|| true`: an empty selection is legitimate input
  # (a trace with no located frames at all), and under `pipefail` a
  # filtering grep that selects nothing exits 1 - which must report
  # through the comparisons below, not kill the gate. Braced, because
  # `||` binds looser than `|` and a bare `a | b || true | c` would
  # rewire the pipeline instead of guarding it.
  { printf '%s\n' "$trace" | sed -n 's/^  at //p' | grep . | grep ' ' || true; } \
    | LC_ALL=C sort > "$work/map.got"
  LC_ALL=C sort "$map" > "$work/map.want"
  checks=$((checks + 1))
  if [[ -n "$(LC_ALL=C comm -23 "$work/map.got" "$work/map.want")" ]]; then
    echo "FAIL $label: located frames with no map row:"
    LC_ALL=C comm -23 "$work/map.got" "$work/map.want" | sed 's/^/       /'
    map_failed=1
  fi
  if (( exact )) && ! cmp -s "$work/map.got" "$work/map.want"; then
    echo "FAIL $label: located frames differ from the map:"
    diff "$work/map.want" "$work/map.got" | sed 's/^/     /' || true
    map_failed=1
  fi
  if (( map_failed )); then
    if (( count )); then failed=$((failed + 1)); fi
    return 0
  fi
  echo "ok   $label"
  return 0
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

# The expected LINES come from the fixture's own bytes, never from a
# golden alone: each `at` line below is assembled from a line number
# `grep` read out of chain.ax just now, so a wrong line blessed into
# this file still fails. `lineno <pattern>` is the line holding it;
# `linecol <pattern>` its column (awk's index, 1-based, like the
# compiler prints).
lineno()  { grep -nF "$2" "$1" | head -1 | cut -d: -f1; }
linecol() { awk -v pat="$2" 'index($0, pat) { print index($0, pat); exit }' "$1"; }
# Column of WORD on a known line. `linecol` finds a pattern's own
# start, which for a `(name)` call pattern is the paren - one short
# of the name the trace points at. Pin the line first, then index
# the word itself.
colat()   { awk -v n="$2" -v pat="$3" 'NR==n { print index($0, pat); exit }' "$1"; }
fx="$work/chain.ax"
# What the binary prints is the basename, never the build dir: argv
# spells absolute workdirs, and those must not leak into binaries or
# traces. Every expectation below is assembled with the basename;
# the line numbers still come from the file's bytes via $fx.
fxb="$(basename "$fx")"
e5l="$(lineno "$fx" '/ 100 n)))')"
e5c="$(linecol "$fx" '/ 100 n)))')"
d4l="$(lineno "$fx" 'e5 n)))')"
d4c="$(linecol "$fx" 'e5 n)))')"
c3l="$(lineno "$fx" 'd4 n)))')"
c3c="$(linecol "$fx" 'd4 n)))')"
b2l="$(lineno "$fx" 'c3 n)))')"
b2c="$(linecol "$fx" 'c3 n)))')"
a1l="$(lineno "$fx" 'b2 n)))')"
a1c="$(linecol "$fx" 'b2 n)))')"
mnl="$(lineno "$fx" 'a1 (- sysArgc 1)))')"
mnc="$(linecol "$fx" 'a1 (- sysArgc 1)))')"

# Eight frames and not seven: `__axiom_user_main` is the compiler's
# rename of the user's `main`, and `main` is the argv wrapper the
# emitter writes around it. Both are real frames and both are named,
# because a trace that silently drops the runtime's own frames is a
# trace whose omissions the reader cannot know about. The runtime
# frames stay bare - no row can exist for code with no source node -
# while every user frame carries the file and line the fixture above
# names for it.
read -r -d '' expected <<TRACE || true
axiom: division by zero
axiom: backtrace (most recent call first)
  at __axiom_div_by_zero
  at e5 $fxb:$e5l:$e5c
  at d4 $fxb:$d4l:$d4c
  at c3 $fxb:$c3l:$c3c
  at b2 $fxb:$b2l:$b2c
  at a1 $fxb:$a1l:$a1c
  at __axiom_user_main $fxb:$mnl:$mnc
  at main
TRACE

want "--opt 0: the five-deep chain names all five, in order with their lines, and stops at main" \
     "$expected" "$got"

if [[ "$o0_status" == "72" ]]; then
  ok "--opt 0: the status is still 72 - a backtrace does not change how the process dies"
else
  bad "--opt 0: status $o0_status, expected 72"
fi

# No build dir in the trace: the binary prints basenames, so the
# workdir the fixture was built from must appear nowhere in it. A
# compiler that embedded argv's absolute path would fail every map
# above on principle; this names the reason.
if grep -qF "$work" <<<"$got"; then
  bad "--opt 0: the trace leaks the build dir"
  grep -F "$work" <<<"$got" | head -3 | sed 's/^/       /'
else
  ok "--opt 0: no build-dir path in the trace - files print as basenames"
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
  #
  # Since lines landed, a frame is a name plus an optional location:
  # the `nm` half reads the name (the first word) and the line half
  # (§7) reads the rest. A walker that invented a plausible
  # `name:line` pair fails here on the name even where the line
  # happens to be right.
  symbol_names "$work/c$opt" | sed -e 'p' -e 's/^_//' | LC_ALL=C sort -u > "$work/syms.txt"
  unknown=""
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    name="${f%% *}"
    grep -qxF "$name" "$work/syms.txt" || unknown="$unknown $name"
  done <<< "$frames"
  if [[ -z "$unknown" ]]; then
    ok "--opt $opt: every name printed is a symbol nm finds in the binary"
  else
    bad "--opt $opt: names no symbol table has:$unknown"
  fi

  # First and last frames are the OPTIMISER's to decide above `--opt
  # 0`: the trap fn inlines away (no frame to print first) and a
  # sibling jump can elide the frames above the highest surviving one
  # (nothing to stop at). §1 pins both ends where every frame exists;
  # here the walk's honesty is that every frame it DOES print is
  # genuine, which the `nm` check above and the line map in §7 assert.
  # What stays unconditional is how the process dies.
  [[ "$st" == "72" ]] \
    && ok "--opt $opt: exit 72" \
    || bad "--opt $opt: exit $st, expected 72"
done

echo
echo "--- 3. the return address is resolved at ra-1, not ra ---"

# THE BUG THIS PINS, because it is the one the first implementation
# shipped and it is invisible to any check that does not know the
# layout. A return address points at the byte AFTER the call. When the
# call is a function's last instruction, that byte is the next
# function's entry, and a nearest-preceding-symbol lookup answers with
# the next function - a real name, a real symbol, and the wrong frame.
#
# Measured before the fix, darwin-aarch64 at --opt 1: `_main` ends
# `bl ___axiom_div_by_zero` at 0x528 and `_axiom_alloc` begins at
# 0x52c, and the frame that was `main` printed as `axiom_alloc`. The
# program allocates nothing.
#
# At `--opt 0` the trap frame exists, so the assertion is exact: the
# frame under it is `e5` at the division's own line (derived above),
# and not `axiom_alloc`. Above 0 the trap inlines away and there is no
# under-trap frame to assert about; the line map in §7 covers whatever
# survives there instead.
trace="$(run_err "$work/c0")"
under="$(printf '%s\n' "$trace" | sed -n 's/^  at //p' | sed -n '2p')"
if [[ "$under" == "e5 $fxb:$e5l:$e5c" ]]; then
  ok "--opt 0: the frame under the trap is e5 at the division's line"
else
  bad "--opt 0: the frame under the trap is \`$under\` - expected \`e5 $fxb:$e5l:$e5c\`; if it is \`axiom_alloc\`, the lookup went back to resolving ra rather than ra-1"
fi

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
    sed 's/^/    /' "$work/build.log" | head -10
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

# The other two traps name lines too, derived the same way: the
# `memAlloc` call behind `outer`, and the `ask` behind `main`.
oomloc="$(lineno "$work/oom.ax" 'memAlloc 1152921504606846976)')"
oomcol="$(linecol "$work/oom.ax" 'memAlloc 1152921504606846976)')"
printf 'outer %s:%s:%s\n' "oom.ax" "$oomloc" "$oomcol" > "$work/oom.map"
# `main`'s body is the bare reference `outer` - a nullary call, which
# marks like any other, so the user's renamed frame is located too.
umloc="$(lineno "$work/oom.ax" '(main) outer)')"
umcol="$(colat "$work/oom.ax" "$umloc" 'outer')"
printf '__axiom_user_main %s:%s:%s\n' "oom.ax" "$umloc" "$umcol" >> "$work/oom.map"
oomtrace="$(run_err "$work/oom")"
check_map "oom: the allocating frame carries its call site" "$oomtrace" "$work/oom.map" 1
ueloc="$(lineno "$work/ue.ax" 'ask 1)')"
uecol="$(linecol "$work/ue.ax" 'ask 1)')"
# `main` (the user's) never appears: it is renamed to
# `__axiom_user_main` at emission, so only the C wrapper's bare `main`
# can print - which asserts nothing and is not listed.
printf '__axiom_user_main %s:%s:%s\n' "ue.ax" "$ueloc" "$uecol" > "$work/ue.map"
uetrace="$(run_err "$work/ue")"
check_map "ue: the performing frame carries its call site" "$uetrace" "$work/ue.map" 1

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
# `defines` counts the walker's own three, which are emitted after the
# table is built and are deliberately not in it: `@__axiom_backtrace`
# never appears as a frame (the first return address read is the one in
# ITS frame, which is its caller), `@__axiom_bt_name` has returned
# before anything is read, and `@__axiom_lineinit` fills the address
# array and returns before the walk starts.
want "every define is in the table, but for the walker's own three" \
      "$((defines - 3))" "$rows"
want "the table states its own row count" "$rows" "$stated"

# NOT a row COUNT. This was `rows >= 200`, calibrated on "a probe
# importing Sys had 275 on 2026-08-24" - a count of everything
# `(import Sys)` dragged in, most of which this probe never calls. Dead
# code is stripped now, so the same probe emits 16 rows and the floor
# went red on a module that got BETTER. A floor drawn round a corpus
# population expires the moment the population legitimately moves.
#
# What the floor was defending is that the table is not empty or
# degenerate, because an empty one resolves every address to
# <unknown> - and the probe itself says what "not degenerate" means:
# it writes a six-deep chain on purpose, and §2 walks a real trace
# through it. So the assertion is that those six are NAMED, which is
# the property, cannot pass vacuously on a small table, and cannot
# expire when the module's size changes again.
chain_missing=""
for fn in main a1 b2 c3 d4 e5; do
  grep -q "ptrtoint (ptr @$fn to i64)" "$work/chain.ll" \
    || chain_missing="$chain_missing $fn"
done
if [[ -z "$chain_missing" ]]; then
  ok "all six of the probe's own functions are in the table ($rows rows in total)"
else
  bad "the table is missing$chain_missing - the walker cannot name a frame it has no entry for"
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
# on 2026-08-24, and 0 of 16 after dead code stopped being emitted.
#
# `found` is the anti-vacuousness half: without it a table of one row
# that happened to resolve would pass. It was 20 - a second floor
# calibrated on the unpruned population, and it failed this gate while
# `missing` was 0, printing "0 of 16 table names are in no symbol
# table" and blaming the emitter for the number that was RIGHT. Six is
# the probe's own chain, which the check above has just established is
# present, so the guard rests on that fact rather than on a snapshot.
found=$((rows - missing))
if (( missing * 4 <= rows && found >= 6 )); then
  ok "$found of $rows table names resolve in the linked symbol table ($missing do not)"
else
  bad "$missing of $rows table names are in no symbol table - the table names functions the linker never emitted"
fi

echo
echo "--- 7. lines come from the fixture's bytes, not from a golden ---"
echo "     (the roadmap's acceptance for this item)"
# The map is derived twice: once here, afresh, and once in §1. The
# two derivations agree today; if either ever stops deriving from the
# bytes - a hardcoded line smuggled in - the shift probe below (which
# moves every line) tells them apart.
{
  echo "e5 $fxb:$(lineno "$fx" '/ 100 n)))'):$(linecol "$fx" '/ 100 n)))')"
  echo "d4 $fxb:$(lineno "$fx" 'e5 n)))'):$(linecol "$fx" 'e5 n)))')"
  echo "c3 $fxb:$(lineno "$fx" 'd4 n)))'):$(linecol "$fx" 'd4 n)))')"
  echo "b2 $fxb:$(lineno "$fx" 'c3 n)))'):$(linecol "$fx" 'c3 n)))')"
  echo "a1 $fxb:$(lineno "$fx" 'b2 n)))'):$(linecol "$fx" 'b2 n)))')"
  echo "__axiom_user_main $fxb:$mnl:$mnc"
} > "$work/chain.map"
for opt in 0 1 2 3; do
  trace="$(run_err "$work/c$opt")"
  st="$(last_rc)"
  # Whatever the optimiser kept, every located frame answers with the
  # fixture's line for it; subset, because frames it removed have no
  # line to check. Exit preserved separately - a right line with a
  # wrong death would still fail below.
  check_map "--opt $opt: every located frame carries the fixture's line" "$trace" "$work/chain.map" 0
  [[ "$st" == "72" ]] \
    && ok "--opt $opt: exit 72 beside located lines" \
    || bad "--opt $opt: exit $st, expected 72"
done

echo
echo "--- 7b. a tampered line table fails the derived lines ---"
# The ablation a golden cannot do: rewrite one row's line in the
# EMITTED IR, rebuild through llc/cc, and require the trace to follow
# the tamper (proving the walker reads the table) while the derived
# expectation goes red (proving the gate reads the fixture). e5's row
# carries `i64 5, i64 22` - the DIV line and column §1 derived - and
# it occurs exactly once; anything else means the anchor moved and the
# probe is measuring itself.
"$axc" emit-llvm --diagnostic-format=ai "$work/chain.ax" -o "$work/tamper.ll" >/dev/null 2>&1
anchor="$(grep -c 'i64 5, i64 22,' "$work/tamper.ll" || true)"
if [[ "$anchor" != "1" ]]; then
  bad "the tamper anchor occurs $anchor times, not once - re-anchor it"
else
  sed 's/i64 5, i64 22,/i64 99, i64 22,/' "$work/tamper.ll" > "$work/tamper.evil.ll"
  if cmp -s "$work/tamper.ll" "$work/tamper.evil.ll"; then
    bad "the tamper changed no byte"
  elif llc -filetype=obj -relocation-model=pic "$work/tamper.evil.ll" -o "$work/tamper.o" 2>"$work/tamper.link.err" \
    && cc "$work/tamper.o" -o "$work/tamper" $link_entry 2>>"$work/tamper.link.err"; then
    trace="$(run_err "$work/tamper")"
    st="$(last_rc)"
    [[ "$st" == "72" ]] \
      && ok "tampered metadata still exits 72 - the defect is in the lines, not the behaviour" \
      || bad "tampered metadata exits $st, expected 72"
    # Silent by design: this comparison's verdict is the line
    # below, but it still counts as a check above.
    check_map "tampered table" "$trace" "$work/chain.map" 1 0 >/dev/null 2>&1
    if (( map_failed )); then
      ok "a linetab claiming line 99 fails the derived line 5"
    else
      bad "a linetab claiming line 99 still matched the derived line 5"
    fi
    grep -q '^  at e5 .*:99:22$' <<<"$trace" \
      && ok "the trace follows the tamper (the walker reads the table)" \
      || bad "the trace does not show the tampered line"
  else
    bad "could not build the tampered IR:"
    head -3 "$work/tamper.link.err" | sed 's/^/       /'
  fi
fi

echo
echo "--- 7c. shifted lines still match, because nothing is blessed ---"
# Three blank lines and a comment above the chain move every derived
# number down by four. A golden would fail here on principle; the
# derivation moves with the bytes.
{ echo ""; echo ""; echo ""; echo "; shifted down by four"; cat "$work/chain.ax"; } > "$work/shifted.ax"
"$axc" build --input "$work/shifted.ax" --output "$work/shifted" --opt 0 >"$work/build.log" 2>&1 \
  || { bad "the shifted probe would not build"; sed 's/^/    /' "$work/build.log" | head -6; }
{
  echo "e5 shifted.ax:$(lineno "$work/shifted.ax" '/ 100 n)))'):$(linecol "$work/shifted.ax" '/ 100 n)))')"
  echo "d4 shifted.ax:$(lineno "$work/shifted.ax" 'e5 n)))'):$(linecol "$work/shifted.ax" 'e5 n)))')"
  echo "c3 shifted.ax:$(lineno "$work/shifted.ax" 'd4 n)))'):$(linecol "$work/shifted.ax" 'd4 n)))')"
  echo "b2 shifted.ax:$(lineno "$work/shifted.ax" 'c3 n)))'):$(linecol "$work/shifted.ax" 'c3 n)))')"
  echo "a1 shifted.ax:$(lineno "$work/shifted.ax" 'b2 n)))'):$(linecol "$work/shifted.ax" 'b2 n)))')"
  echo "__axiom_user_main shifted.ax:$(lineno "$work/shifted.ax" 'a1 (- sysArgc 1)))'):$(linecol "$work/shifted.ax" 'a1 (- sysArgc 1)))')"
} > "$work/shifted.map"
trace="$(run_err "$work/shifted")"
check_map "shifted: the moved lines still match" "$trace" "$work/shifted.map" 1

echo
echo "--- 7d. recursion: one name, as many lines as frames ---"
# Five `sum` frames share one name and one call-site line, and the
# innermost answers the division's. Names alone cannot separate them;
# the map lists one row per expected frame, duplicates and all.
cat > "$work/rec.ax" <<'PROBE'
(:: sum (-> Int Int))
(fn (sum n)
  (if (<= n 0)
    (/ 1 n)
    (+ n (sum (- n 1)))
  )
)
(:: main Int)
(fn (main) (sum 5))
PROBE
"$axc" build --input "$work/rec.ax" --output "$work/rec" --opt 0 >"$work/build.log" 2>&1 \
  || { bad "the recursion probe would not build"; sed 's/^/    /' "$work/build.log" | head -6; }
{
  echo "sum rec.ax:$(lineno "$work/rec.ax" '/ 1 n)'):$(linecol "$work/rec.ax" '/ 1 n)')"
  echo "sum rec.ax:$(lineno "$work/rec.ax" 'sum (- n 1)))'):$(linecol "$work/rec.ax" 'sum (- n 1)))')"
  echo "sum rec.ax:$(lineno "$work/rec.ax" 'sum (- n 1)))'):$(linecol "$work/rec.ax" 'sum (- n 1)))')"
  echo "sum rec.ax:$(lineno "$work/rec.ax" 'sum (- n 1)))'):$(linecol "$work/rec.ax" 'sum (- n 1)))')"
  echo "sum rec.ax:$(lineno "$work/rec.ax" 'sum (- n 1)))'):$(linecol "$work/rec.ax" 'sum (- n 1)))')"
  echo "sum rec.ax:$(lineno "$work/rec.ax" 'sum (- n 1)))'):$(linecol "$work/rec.ax" 'sum (- n 1)))')"
  echo "__axiom_user_main rec.ax:$(lineno "$work/rec.ax" 'sum 5)'):$(linecol "$work/rec.ax" 'sum 5)')"
} > "$work/rec.map"
trace="$(run_err "$work/rec")"
check_map "recursion: five frames share a name and a call line, the sixth names the division" "$trace" "$work/rec.map" 1

echo
echo "--- 7e. nullary calls mark too: a bare reference is still a call ---"
# `(boom)` with no arguments is a variable reference by the time it
# reaches the emitter, and that path used to emit its call with no
# marker - a frame with a name and no line. The reference node
# carries the span, so it marks like every other call site; this
# probe would print a bare `at wrap` if that ever regressed.
cat > "$work/nullary.ax" <<'PROBE'
(:: boom Int)
(fn (boom) (/ 1 0))
(:: wrap Int)
(fn (wrap) (+ (boom) 1))
(:: main Int)
(fn (main) (+ (wrap) 1))
PROBE
"$axc" build --input "$work/nullary.ax" --output "$work/nullary" --opt 0 >"$work/build.log" 2>&1 \
  || { bad "the nullary probe would not build"; sed 's/^/    /' "$work/build.log" | head -6; }
{
  echo "boom nullary.ax:$(lineno "$work/nullary.ax" '/ 1 0)'):$(linecol "$work/nullary.ax" '/ 1 0)')"
  wline="$(lineno "$work/nullary.ax" '(boom) 1)')"
  echo "wrap nullary.ax:$wline:$(colat "$work/nullary.ax" "$wline" 'boom')"
  mline="$(lineno "$work/nullary.ax" '(wrap) 1)')"
  echo "__axiom_user_main nullary.ax:$mline:$(colat "$work/nullary.ax" "$mline" 'wrap')"
} > "$work/nullary.map"
trace="$(run_err "$work/nullary")"
check_map "nullary: bare-reference calls carry their lines" "$trace" "$work/nullary.map" 1

echo
if (( failed > 0 )); then
  echo "check-backtrace: $failed of $checks checks failed"
  exit 1
fi
echo "check-backtrace: $checks checks - a dying program names its frames, the"
echo "                 names are symbols nm confirms, the walk stops where this"
echo "                 module's table ends, and the attribute that makes the"
echo "                 chain walkable is load-bearing on every target"
