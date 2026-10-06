#!/usr/bin/env bash
# Check that a dying Axiom program names the functions on its stack.
#
# Without a backtrace, a trap gives a status and one line, such as
# "axiom: division by zero" and 72. That says what happened, not where.
# A worker dying in a pre-forked pool has no debugger attached, and once
# the supervisor respawns it the frame is gone. Function-level frames
# answer most production triage.
#
# The mechanism has three pieces, none of them debug metadata:
#   1. `"frame-pointer"="all"` on the module's one attribute group, so
#      the chain is walkable on every target. Checked in §5.
#   2. `@__axiom_symtab`, an address-beside-name table over every symbol
#      the module defines, emitted as ordinary constant data. Checked in §6.
#   3. `@__axiom_backtrace`, which walks the chain and resolves each
#      return address. Checked in §1-§4.
# `-g` is never passed and there is no `!dbg` anywhere. The whole
# mechanism is emitted text, so the committed seed compiles `self_host/`
# unchanged.
#
# A five-deep chain cannot name five functions at every optimisation
# level. At `--opt 1` and above there is no five-deep chain: LLVM
# inlines it into `main`, so the trace reads `__axiom_div_by_zero main`.
# Mutual recursion does not stop the inliner. So the gate asserts what
# holds at every level: the walker names exactly the frames that are on
# the stack.
#   §1 pins all eight frames byte for byte at `--opt 0`.
#   §2 checks every printed name at every level against `nm`, a source
#      outside the compiler, so an invented name fails even where the
#      frame count is unpredictable.
#   §3 pins the ra-1 lookup, which otherwise names a plausible wrong frame.

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

# check_map <label> <trace> <map> <exact> [count]
# Every located frame (`at FN FILE:L:C`) must match a map row byte for
# byte. With exact=1 the located multiset must equal the map, in any
# order. Map rows are `FN FILE:L:C`, one per expected located frame, so
# recursion repeats rows. Bare frames (`at FN`) assert nothing: runtime
# helpers and generated wrappers have no source node.
# `__axiom_user_main` is the user's renamed main, so it is located like
# any user function. Always returns 0, so bare calls are safe under
# `set -e`. The verdict is in $map_failed. Pass count=0 when a mismatch
# is the expected result, as in the tamper probe.
map_failed=0
check_map() {
  local label="$1" trace="$2" map="$3" exact="$4" count="${5:-1}"
  map_failed=0
  # A trace with no located frames is valid input, and under `pipefail`
  # a grep that selects nothing exits 1, hence `|| true`. The braces
  # matter: `||` binds looser than `|`.
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

# The five-deep chain. The divisor comes from `sysArgc` at run time, so
# neither the trap nor the chain folds away before `llc` sees them.
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

# Expected lines come from the fixture's own bytes, never from a golden:
# each `at` line is built from a line number read out of chain.ax, so a
# wrong line written into this file still fails. `lineno <file> <pattern>`
# is the line holding the pattern, and `linecol` its 1-based column, as
# the compiler prints it.
lineno()  { grep -nF "$2" "$1" | head -1 | cut -d: -f1; }
linecol() { awk -v pat="$2" 'index($0, pat) { print index($0, pat); exit }' "$1"; }
# `colat <file> <line> <word>` is the column of a word on a known line.
# `linecol` on a `(name)` pattern finds the paren, one short of the name
# the trace points at.
colat()   { awk -v n="$2" -v pat="$3" 'NR==n { print index($0, pat); exit }' "$1"; }
fx="$work/chain.ax"
# The binary prints the basename, never the build dir, so absolute
# workdirs never leak into binaries or traces.
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

# Eight frames: `__axiom_user_main` is the compiler's rename of the
# user's `main`, and `main` is the argv wrapper around it. Both are real
# frames and both are named, so the trace hides nothing from the reader.
# Runtime frames stay bare, having no source node. Every user frame
# carries its file and line.
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

# No build dir in the trace. A compiler that embedded argv's absolute
# path would fail every map above; this check names the reason.
if grep -qF "$work" <<<"$got"; then
  bad "--opt 0: the trace leaks the build dir"
  grep -F "$work" <<<"$got" | head -3 | sed 's/^/       /'
else
  ok "--opt 0: no build-dir path in the trace - files print as basenames"
fi

echo
echo "--- 2. every optimisation level: every name printed is a real frame ---"

# The independent source. `nm` reads the linked binary's symbol table,
# which the linker writes, not the compiler. A walker that invented a
# name, or read the wrong table entry, passes any self-comparison and
# fails this one.
#
# `symbol_names <binary>` prints one symbol name per line. Apple's and
# GNU's nm take `-j`. FreeBSD's base `nm` (ELF Tool Chain) does not, and
# under `pipefail` its exit 1 would end the gate silently, so fall back
# to `llvm-nm`. An empty answer fails the comparison below, since every
# printed frame is then a name no table has.
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

  # `nm` prints Mach-O symbols with a leading underscore and ELF symbols
  # without, so the set holds both spellings. Stripping `_` instead would
  # eat a real character on ELF, turning `__axiom_div_by_zero` into
  # `_axiom_div_by_zero`.
  #
  # A frame is a name plus an optional location. This check reads the
  # name (the first word) and §7 reads the line, so an invented
  # `name:line` pair fails here even where the line is right.
  symbol_names "$work/c$opt" | sed -e 'p' -e 's/^_//' | LC_ALL=C sort -u > "$work/syms.txt"
  # `<unknown>` is the walker's answer for an address outside every table
  # entry, such as a crt startup frame past `main` above `--opt 0`, where
  # the next fp points past the table. It is not an invented name. A user
  # frame mis-resolved as unknown still fails §7 for a missing located row.
  unknown=""
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    name="${f%% *}"
    [[ "$name" == "<unknown>" ]] && continue
    grep -qxF "$name" "$work/syms.txt" || unknown="$unknown $name"
  done <<< "$frames"
  if [[ -z "$unknown" ]]; then
    ok "--opt $opt: every name printed is a symbol nm finds in the binary"
  else
    bad "--opt $opt: names no symbol table has:$unknown"
    echo "     trace at --opt $opt ($nframes frames):" | sed 's/^/     /'
    printf '%s\n' "$frames" | sed 's/^/       at /' | head -15
  fi

  # Above `--opt 0` the optimiser decides the first and last frames: the
  # trap function inlines away, and a sibling jump can elide the frames
  # above the highest survivor. §1 pins both ends where every frame
  # exists. Here every printed frame must be genuine (the `nm` check
  # above and §7's line map), and the exit status never changes.
  [[ "$st" == "72" ]] \
    && ok "--opt $opt: exit 72" \
    || bad "--opt $opt: exit $st, expected 72"
done

echo
echo "--- 3. the return address is resolved at ra-1, not ra ---"

# A return address points at the byte after the call. When the call is a
# function's last instruction, that byte is the next function's entry,
# so a nearest-preceding-symbol lookup names the wrong frame with a real
# symbol. On darwin-aarch64 at --opt 1, `_main` ends with
# `bl ___axiom_div_by_zero` and `_axiom_alloc` starts right after it, so
# resolving ra prints `main` as `axiom_alloc`.
#
# At `--opt 0` the trap frame exists, so the check is exact: the frame
# under it is `e5` at the division's line. Above 0 the trap inlines away,
# and §7's line map covers whatever survives.
trace="$(run_err "$work/c0")"
under="$(printf '%s\n' "$trace" | sed -n 's/^  at //p' | sed -n '2p')"
if [[ "$under" == "e5 $fxb:$e5l:$e5c" ]]; then
  ok "--opt 0: the frame under the trap is e5 at the division's line"
else
  bad "--opt 0: the frame under the trap is \`$under\` - expected \`e5 $fxb:$e5l:$e5c\`; if it is \`axiom_alloc\`, the lookup went back to resolving ra rather than ra-1"
fi

echo
echo "--- 4. all three traps, and each one names itself first ---"

# The trap family is `emitDivTrap` (72), `emitOomTrap` (70) and
# `emitUnhandledTrap` (71), and all three must carry the trace. The
# unhandled-effect trap is emitted only when a program declares an
# effect, a conditional emission that is easy to leave behind.
#
# The allocation is 2^60 bytes, as in `tests/stdlib/314-out-of-memory.ax`.
# macOS overcommits, so 1 TiB succeeds, and FreeBSD/arm64 grants 2^47.
# The size must exceed the user address space on every target. A size
# that fits somewhere makes this probe exit 0 there and assert nothing.
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
  grep -q "^  at main$" <<< "$trace" \
    && ok "$name: the trace reaches main" \
    || bad "$name: the trace never reaches main"
done

# The other two traps name lines too, derived the same way: the
# `memAlloc` call behind `outer`, and the `ask` behind `main`.
oomloc="$(lineno "$work/oom.ax" 'memAlloc 1152921504606846976)')"
oomcol="$(linecol "$work/oom.ax" 'memAlloc 1152921504606846976)')"
printf 'outer %s:%s:%s\n' "oom.ax" "$oomloc" "$oomcol" > "$work/oom.map"
# `main`'s body is the bare reference `outer`, a nullary call. It marks
# like any other call, so the user's renamed frame is located too.
umloc="$(lineno "$work/oom.ax" '(main) outer)')"
umcol="$(colat "$work/oom.ax" "$umloc" 'outer')"
printf '__axiom_user_main %s:%s:%s\n' "oom.ax" "$umloc" "$umcol" >> "$work/oom.map"
oomtrace="$(run_err "$work/oom")"
check_map "oom: the allocating frame carries its call site" "$oomtrace" "$work/oom.map" 1
ueloc="$(lineno "$work/ue.ax" 'ask 1)')"
uecol="$(linecol "$work/ue.ax" 'ask 1)')"
# The user's `main` is renamed to `__axiom_user_main` at emission. Only
# the C wrapper's bare `main` prints, which asserts nothing, so the map
# leaves it out.
printf '__axiom_user_main %s:%s:%s\n' "ue.ax" "$ueloc" "$uecol" > "$work/ue.map"
uetrace="$(run_err "$work/ue")"
check_map "ue: the performing frame carries its call site" "$uetrace" "$work/ue.map" 1

echo
echo "--- 5. the frame pointer is kept on every target, and the attribute is why ---"

# Only one of the six targets runs here, but `llc` assembles all six, as
# `check-cross-targets.sh` relies on. So the check reads the prologue
# `llc` emits per target, with and without the attribute: a live
# ablation that needs no compiler build.
#
# The check greps for `mov x29, sp`, not `stp`. Without the attribute,
# Darwin/arm64 still saves the pair with `stp x29, x30, [sp, #-16]!` but
# never sets `mov x29, sp`, so x29 holds the caller's frame and the chain
# is not walkable. `___axiom_div_by_zero` at --opt 1 is such a function.
#
# AArch64 and X86 are the backend names `llc --version` prints, not
# target triples, spelled as `check-cross-targets.sh` spells them.
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
    grep -qE 'mov[[:space:]]+x29, sp' <<< "$body" && echo kept || echo omitted
  else
    grep -qE 'movq[[:space:]]+%rsp, %rbp' <<< "$body" && echo kept || echo omitted
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

  # The ablation: remove the attribute and assemble the same module again.
  sed 's/ "frame-pointer"="all"//' "$work/t.ll" > "$work/t.noattr.ll"
  if [[ "$(fp_probe "$target" "$work/t.noattr.ll")" == "omitted" ]]; then
    ok "[$target] ablation: without the attribute the frame pointer is gone"
    ablated=$((ablated + 1))
  else
    # Not a failure alone: a target whose ABI mandates a frame pointer
    # lands here, and the positive check above still holds for it. The
    # floor below stops a run where nothing discriminates from passing.
    ok "[$target] ablation: the frame pointer survives the attribute being removed"
  fi
done

# An ablation that never fires proves nothing. All six targets
# discriminate, and the floor is one below that. A toolchain that makes
# one target keep frame pointers by default is then no spurious failure,
# while an attribute that stops mattering everywhere still fails.
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

# The walker resolves a return address to the greatest table entry at or
# below it, so a function missing from the table is silently reported as
# the function before it. The table must hold every `define`: lifted
# lambdas, thunks, the argv wrapper and the runtime helpers included.
#
# `defines` also counts the walker's own three, which are emitted after
# the table and are not in it. `@__axiom_backtrace` never appears as a
# frame, since the first return address it reads is its caller's.
# `@__axiom_bt_name` returns before anything is read, and
# `@__axiom_lineinit` fills the address array before the walk starts.
want "every define is in the table, but for the walker's own three" \
      "$((defines - 3))" "$rows"
want "the table states its own row count" "$rows" "$stated"

# The table must not be empty or degenerate, since an empty table
# resolves every address to <unknown>. A row-count floor expires when
# dead-code stripping changes the module's size. So the check is that
# the probe's own six functions are named, which cannot pass vacuously.
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

# The names in the table must be symbols the linker emitted. This is §2's
# `nm` cross-check applied to the whole table, so a name mangled
# differently in the table than in its `define` fails even if no frame
# lands on it. Both spellings go in the set, as in §2.
symbol_names "$work/chain0" | sed -e 'p' -e 's/^_//' | LC_ALL=C sort -u > "$work/syms.txt"
missing=0
while IFS= read -r sym; do
  [[ -n "$sym" ]] || continue
  grep -qxF "$sym" "$work/syms.txt" || missing=$((missing + 1))
done < <(grep -o 'ptrtoint (ptr @[A-Za-z0-9_.$]* to i64), i64 ptrtoint (ptr @__axiom_symn' \
           "$work/chain.ll" | sed 's/ptrtoint (ptr @//; s/ to i64.*//')
# The direction that can be wrong is table names the linker never
# emitted. `internal` symbols can be stripped, so a small residue is
# fine, but a large one means the walker resolves against names that do
# not exist.
#
# `found` stops a one-row table that happens to resolve from passing.
# Its floor is the probe's own six functions, which the check above
# established, rather than a snapshot of the table's size.
found=$((rows - missing))
if (( missing * 4 <= rows && found >= 6 )); then
  ok "$found of $rows table names resolve in the linked symbol table ($missing do not)"
else
  bad "$missing of $rows table names are in no symbol table - the table names functions the linker never emitted"
fi

echo
echo "--- 7. lines come from the fixture's bytes, not from a golden ---"
echo "     (the roadmap's acceptance for this item)"
# The map is derived here afresh, and again in §1. If either stops
# deriving from the bytes, the shift probe in §7c, which moves every
# line, tells them apart.
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
  # Whatever the optimiser kept, every located frame carries the
  # fixture's line. The match is a subset, since removed frames have no
  # line. The exit status is checked separately.
  check_map "--opt $opt: every located frame carries the fixture's line" "$trace" "$work/chain.map" 0
  [[ "$st" == "72" ]] \
    && ok "--opt $opt: exit 72 beside located lines" \
    || bad "--opt $opt: exit $st, expected 72"
done

echo
echo "--- 7b. a tampered line table fails the derived lines ---"
# The ablation a golden cannot do: rewrite one row's line in the emitted
# IR and rebuild through llc and cc. The trace must follow the tamper
# (the walker reads the table) while the derived expectation fails (the
# gate reads the fixture). e5's rows carry `i64 5, i64 22`, the
# division's line and column from §1. They occur exactly twice, one per
# trap site: divide-by-zero and overflow. Any other count means the
# anchor moved; re-anchor it.
"$axc" emit-llvm --diagnostic-format=ai "$work/chain.ax" -o "$work/tamper.ll" >/dev/null 2>&1
anchor="$(grep -c 'i64 5, i64 22,' "$work/tamper.ll" || true)"
if [[ "$anchor" != "2" ]]; then
  bad "the tamper anchor occurs $anchor times, not twice - re-anchor it"
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
    # Silent: the line below reports this comparison's verdict.
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
# line down by four. A golden would fail here; the derivation moves
# with the bytes.
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
# `(boom)` with no arguments reaches the emitter as a variable
# reference. The reference node carries the span, so it marks like any
# other call site. A regression prints a bare `at wrap`.
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
