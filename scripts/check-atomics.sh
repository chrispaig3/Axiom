#!/usr/bin/env bash
# The five atomic primitives, in machine code and on two threads (R-C3).
#
# `__atomic_load`, `__atomic_store`, `__atomic_add`, `__atomic_cas` and
# `__fence` lower to sequentially consistent LLVM atomics with no target
# arm (`emitPrimAtomic`, self_host/codegen.ax). What LLVM then makes of
# `seq_cst` on each ISA was stated in that comment and checked by
# nothing: `check-freestanding.sh` says they lower inline, and
# `check-cross-targets.sh` says the objects relocate, and neither looks
# at an instruction. This gate does, and then runs them.
#
# THREE SECTIONS.
#
#   1. MACHINE CODE. tests/stdlib/440-atomics.ax spells each primitive
#      a known number of times on one straight-line path. It is emitted
#      for every target the compiler knows, put through the driver's own
#      pipeline (opt -O<n>, llc -O<n> -relocation-model=pic) to assembly
#      at -O0..-O3, and the ordering instructions are counted. Each count
#      must EQUAL the source's uses of its primitive:
#
#        x86-64   store -> xchg          add -> lock xadd
#                 cas   -> lock cmpxchg  fence -> lock or to the stack
#                                        (LLVM's full barrier; mfence
#                                        would be accepted)
#        AArch64  load  -> ldar          store -> stlr
#                 add, cas -> one ldaxr/stlxr loop each, or LSE's
#                             ldaddal/casal      fence -> dmb ish
#
#      and AArch64 may show no exclusive or LSE form without both
#      acquire and release (ldxr, stxr, ldadd, ldadda, ldaddl, cas,
#      casa, casl). A program with no atomics (010-hello) must count
#      ZERO of every one on every target and level - so the counts are
#      the primitives' own, not the runtime's.
#
#      The x86-64 LOAD is not in the table because it cannot be: under
#      the standard mapping a seq_cst load on x86 is a plain `mov`, the
#      ordering being paid by the store's `xchg`. Section 2 measures that
#      instead of asserting it.
#
#   2. ABLATIONS. Each weakening of the emitted IR must turn section 1's
#      check red on the ISA that can show it - store -> monotonic (both),
#      load -> monotonic (AArch64), add/cas -> monotonic (AArch64, at -O2
#      only: at -O0 LLVM lowers every AArch64 read-modify-write with
#      ldaxr/stlxr whatever its ordering, so section 1's rmw rows at -O0
#      hold for ANY ordering and say nothing), the fence deleted (both) -
#      and each seam must match exactly the
#      source's count of lines, so an emitter change that moves the
#      spelling cannot make an ablation silently apply to nothing. The
#      x86-64 load weakened to monotonic must leave the assembly
#      byte-identical: that is the invisibility above, measured.
#
#   3. LITMUS, ON THIS HOST. tests/litmus/atomics.ax, built with
#      `--threads` at --opt 0..3, runs three families on two threads,
#      each printing `<forbidden> <witnessed>`:
#
#        sb sc | sb fence   forbidden 0 in every run
#        mp sc              forbidden 0 in every run, flag seen > 0
#        add sc | add cas   forbidden (lost updates) 0 in every run
#        sb plain           CONTROL: forbidden > 0 in some run
#        add split          CONTROL: forbidden > 0 in some run
#        mp plain           reported, not required - x86 hardware never
#                           reorders this pattern, so at -O0 there is
#                           nothing to show and a requirement would fail
#                           on the one ISA whose answer is "correct"
#
#      A control that never shows its outcome is a FAILURE, not a pass:
#      the zeros above it would then mean only that this harness cannot
#      see a reordering at all.
#
# LIMITS. Section 1 is one fixture's shapes, as this LLVM lowers them,
# for targets named by triple with no CPU - so AArch64 shows LL/SC loops
# because the IR names no LSE-capable CPU, and a host with LSE runs
# those same loops. Section 3 is the rounds run, on this host, at these
# levels: an absent outcome is evidence, not proof, and a litmus pass
# on x86 says nothing about AArch64. The linux-x86_64, linux-aarch64
# and darwin-aarch64 CI legs are the three hosts it runs on.
#
# Usage: check-atomics.sh
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

command -v llc >/dev/null || { echo "FAIL: llc is not on PATH"; exit 1; }
command -v opt >/dev/null || { echo "FAIL: opt is not on PATH"; exit 1; }

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

fixture="$repo_root/tests/stdlib/440-atomics.ax"
control="$repo_root/tests/stdlib/010-hello.ax"
litmus="$repo_root/tests/litmus/atomics.ax"
x86_targets="linux-x86_64 darwin-x86_64 freebsd-x86_64 windows-x86_64"
a64_targets="linux-aarch64 darwin-aarch64 freebsd-aarch64"

# The source's own count of each primitive, comments stripped - COUNTED,
# not typed, so a fixture that gains a use moves the expectation with it.
uses() { sed 's/;.*//' "$fixture" | grep -o "$1" | wc -l | tr -d ' '; }
n_load="$(uses '(__atomic_load ')"
n_store="$(uses '(__atomic_store ')"
n_add="$(uses '(__atomic_add ')"
n_cas="$(uses '(__atomic_cas ')"
n_fence="$(uses '__fence')"
if (( n_load == 0 || n_store == 0 || n_add == 0 || n_cas == 0 || n_fence == 0 )); then
  echo "FAIL: 440-atomics.ax no longer spells every primitive (load $n_load, store $n_store, add $n_add, cas $n_cas, fence $n_fence)"
  exit 1
fi
echo "   440-atomics.ax: load $n_load, store $n_store, add $n_add, cas $n_cas, fence $n_fence"

# asm <ll> <out.s> <level>: the driver's pipeline, to assembly.
asm() {
  local in="$1"
  if (( $3 > 0 )); then
    opt "-O$3" "$1" -S -o "$2.opt.ll" 2> "$2.log" || return 1
    in="$2.opt.ll"
  fi
  llc "$in" -filetype=asm "-O$3" -relocation-model=pic -o "$2" 2>> "$2.log"
}

cnt() { grep -cE "$2" "$1"; }   # <asm> <ERE>: matching lines

X86_XCHG='^[[:space:]]+xchg[bwlq]?[[:space:]]'
X86_XADD='^[[:space:]]+lock[[:space:]]+xadd'
X86_CMPXCHG='^[[:space:]]+lock[[:space:]]+cmpxchg'
X86_FENCE='^[[:space:]]+(mfence|lock[[:space:]]+or[bwlq]?[[:space:]]+\$0,[[:space:]]*-?[0-9]*\(%rsp\))'
A64_LDAR='^[[:space:]]+ldar[[:space:]]'
A64_STLR='^[[:space:]]+stlr[[:space:]]'
A64_LDAXR='^[[:space:]]+ldaxr[[:space:]]'
A64_STLXR='^[[:space:]]+stlxr[[:space:]]'
A64_LSE='^[[:space:]]+(ldaddal|casal)[[:space:]]'
A64_WEAK='^[[:space:]]+(ldxr|stxr|ldadd|ldadda|ldaddl|cas|casa|casl)[[:space:]]'
A64_DMB='^[[:space:]]+dmb[[:space:]]+ish$'

# x86 <asm> <want-store> <want-add> <want-cas> <want-fence>: "" when the
# counts are as wanted, else what differed.
x86_diff() {
  local s="$1" out="" g
  g="$(cnt "$s" "$X86_XCHG")";    [[ "$g" == "$2" ]] || out+=" xchg $g (want $2)"
  g="$(cnt "$s" "$X86_XADD")";    [[ "$g" == "$3" ]] || out+=" lock-xadd $g (want $3)"
  g="$(cnt "$s" "$X86_CMPXCHG")"; [[ "$g" == "$4" ]] || out+=" lock-cmpxchg $g (want $4)"
  g="$(cnt "$s" "$X86_FENCE")";   [[ "$g" == "$5" ]] || out+=" full-fence $g (want $5)"
  echo "$out"
}

# a64 <asm> <want-load> <want-store> <want-rmw> <want-fence>
a64_diff() {
  local s="$1" out="" g lx sx lse weak
  g="$(cnt "$s" "$A64_LDAR")"; [[ "$g" == "$2" ]] || out+=" ldar $g (want $2)"
  g="$(cnt "$s" "$A64_STLR")"; [[ "$g" == "$3" ]] || out+=" stlr $g (want $3)"
  lx="$(cnt "$s" "$A64_LDAXR")"; sx="$(cnt "$s" "$A64_STLXR")"; lse="$(cnt "$s" "$A64_LSE")"
  [[ "$lx" == "$sx" ]] || out+=" ldaxr $lx vs stlxr $sx"
  (( lx + lse == $4 )) || out+=" acq-rel rmw $((lx + lse)) (want $4)"
  weak="$(cnt "$s" "$A64_WEAK")"; [[ "$weak" == 0 ]] || out+=" $weak exclusive/LSE op(s) without acquire-release"
  g="$(cnt "$s" "$A64_DMB")"; [[ "$g" == "$5" ]] || out+=" dmb-ish $g (want $5)"
  echo "$out"
}

# ---------------------------------------------------------------------
echo "== 1. machine code: every target, every level =="
for t in $x86_targets $a64_targets; do
  for f in atomics control; do
    src="$fixture"; [[ "$f" == control ]] && src="$control"
    if ! "$axc" --target="$t" emit-llvm "$src" -o "$work/$f.$t.ll" > "$work/$f.$t.emit" 2>&1; then
      bad "[$t] emit-llvm of $f failed"; continue
    fi
  done
  shape=""
  for lvl in 0 1 2 3; do
    if ! asm "$work/atomics.$t.ll" "$work/atomics.$t.O$lvl.s" "$lvl" \
       || ! asm "$work/control.$t.ll" "$work/control.$t.O$lvl.s" "$lvl"; then
      bad "[$t] -O$lvl: the pipeline failed"; sed 's/^/    /' "$work/atomics.$t.O$lvl.s.log" | head -5; continue
    fi
    if [[ " $x86_targets " == *" $t "* ]]; then
      d="$(x86_diff "$work/atomics.$t.O$lvl.s" "$n_store" "$n_add" "$n_cas" "$n_fence")"
      c="$(x86_diff "$work/control.$t.O$lvl.s" 0 0 0 0)"
    else
      d="$(a64_diff "$work/atomics.$t.O$lvl.s" "$n_load" "$n_store" $((n_add + n_cas)) "$n_fence")"
      c="$(a64_diff "$work/control.$t.O$lvl.s" 0 0 0 0)"
      (( $(cnt "$work/atomics.$t.O$lvl.s" "$A64_LSE") > 0 )) && shape="LSE" || shape="LL/SC loops"
    fi
    if [[ -n "$d" ]]; then bad "[$t] -O$lvl: the atomics fixture:$d"; continue; fi
    if [[ -n "$c" ]]; then bad "[$t] -O$lvl: the no-atomics control is not clean:$c"; continue; fi
    ok "[$t] -O$lvl: every ordering instruction present, once per use; control clean${shape:+ ($shape)}"
  done
done

# ---------------------------------------------------------------------
echo "== 2. ablations: a weakened IR turns section 1 red =="
# ablate <in.ll> <out.ll> <want-matches> <perl-substitution>
ablate() {
  local got
  got="$(perl -ne "\$n += ($4) ? 1 : 0; END { print \$n + 0 }" "$1")"
  if [[ "$got" != "$3" ]]; then
    echo "matched $got line(s), wanted $3"; return 1
  fi
  perl -pe "$4" "$1" > "$2"
}

# kind  isa  levels  want-matches  seam. The levels are where the ISA
# can show the weakening: at -O0 LLVM lowers EVERY AArch64 read-modify-
# write with acquire-release exclusives (ldaxr/stlxr), monotonic or not -
# measured 2026-09-27, LLVM 23 - and only -O1 and up weaken it to
# ldxr/stxr, so the rmw row is measured at -O2 alone.
while read -r kind isa levels want subst; do
  t=linux-x86_64; [[ "$isa" == a64 ]] && t=linux-aarch64
  for lvl in ${levels//,/ }; do
    in="$work/atomics.$t.ll"; out="$work/abl-$kind-$isa.ll"
    if ! msg="$(ablate "$in" "$out" "$want" "$subst")"; then
      bad "$kind [$t]: the seam $msg - the emitter's spelling moved"; continue
    fi
    if ! asm "$out" "$work/abl-$kind-$isa.O$lvl.s" "$lvl"; then
      bad "$kind [$t] -O$lvl: the ablated IR did not assemble"; continue
    fi
    s="$work/abl-$kind-$isa.O$lvl.s"
    if [[ "$kind" == x86-load ]]; then
      # `.file` names the .ll the assembly came from, which differs by
      # construction; every other line must match.
      if cmp -s <(grep -v "^[[:space:]]*\.file" "$s") \
                <(grep -v "^[[:space:]]*\.file" "$work/atomics.$t.O$lvl.s"); then
        ok "$kind [$t] -O$lvl: a monotonic load assembles byte-identically - the x86 load's ordering is invisible in machine code, as stated"
      else
        bad "$kind [$t] -O$lvl: a monotonic load changed the assembly, so the load IS observable and section 1 should check it"
      fi
      continue
    fi
    if [[ "$isa" == x86 ]]; then
      d="$(x86_diff "$s" "$n_store" "$n_add" "$n_cas" "$n_fence")"
    else
      d="$(a64_diff "$s" "$n_load" "$n_store" $((n_add + n_cas)) "$n_fence")"
    fi
    if [[ -n "$d" ]]; then
      ok "$kind [$t] -O$lvl: red -$d"
    else
      bad "$kind [$t] -O$lvl: the weakened IR still passes section 1 - the check is blind to it"
    fi
  done
done <<ROWS
store     x86  0,2  $n_store  s/(store atomic i64 .*) seq_cst,/\$1 monotonic,/
fence     x86  0,2  $n_fence  s/^\s*fence seq_cst\n//
x86-load  x86  0,2  $n_load   s/(load atomic i64, ptr \S+) seq_cst,/\$1 monotonic,/
store     a64  0,2  $n_store  s/(store atomic i64 .*) seq_cst,/\$1 monotonic,/
load      a64  0,2  $n_load   s/(load atomic i64, ptr \S+) seq_cst,/\$1 monotonic,/
rmw       a64  2    $((n_add + n_cas))  s/(atomicrmw add .*) seq_cst,|(cmpxchg .*) seq_cst seq_cst,/defined(\$1) ? "\$1 monotonic," : "\$2 monotonic monotonic,"/e
fence     a64  0,2  $n_fence  s/^\s*fence seq_cst\n//
ROWS

# ---------------------------------------------------------------------
echo "== 3. litmus on this host, two threads =="
runs=3
# run_row <bin> <family> <mode> -> sets $r_forb $r_wit (sums over runs) and $r_max; 1 on a bad run
run_once() {
  local out rc=0
  out="$(gate_timeout 120 "$1" "$2" "$3" 2> "$work/litmus.err")" || rc=$?
  if (( rc != 0 )) || [[ ! "$out" =~ ^-?[0-9]+\ [0-9]+$ ]]; then
    bad "$2 $3: exit $rc, stdout '$out', stderr '$(head -1 "$work/litmus.err")'"
    return 1
  fi
  r_f="${out% *}"; r_w="${out#* }"
}

for lvl in 0 1 2 3; do
  bin="$work/litmus.O$lvl"
  if ! "$axc" build --threads --input "$litmus" --output "$bin" --opt "$lvl" > "$work/litmus.O$lvl.build" 2>&1; then
    bad "litmus --threads --opt $lvl did not build:"; sed 's/^/    /' "$work/litmus.O$lvl.build" | head -12; continue
  fi
  for row in "sb sc" "sb fence" "mp sc" "add sc" "add cas"; do
    set -- $row
    forb=0; wit=0; good=1
    for ((k = 0; k < runs; k++)); do
      run_once "$bin" "$1" "$2" || { good=0; break; }
      forb=$((forb + (r_f < 0 ? -r_f : r_f))); wit=$((wit + r_w))
    done
    (( good )) || continue
    if (( forb != 0 )); then
      bad "$row -O$lvl: the forbidden outcome $forb time(s) in $runs runs"
    elif [[ "$1" == mp ]] && (( wit == 0 )); then
      bad "$row -O$lvl: no round saw the flag, so the test tested nothing"
    else
      ok "$row -O$lvl: forbidden 0 in $runs runs (witnessed $wit)"
    fi
  done
  for row in "sb plain" "add split"; do
    set -- $row
    seen=0; tries=0
    while (( seen == 0 && tries < 5 )); do
      tries=$((tries + 1))
      run_once "$bin" "$1" "$2" || break
      seen="$r_f"
    done
    if (( seen > 0 )); then
      ok "$row -O$lvl: CONTROL shows the forbidden outcome ($seen, run $tries) - the zeros above can fail"
    else
      bad "$row -O$lvl: CONTROL never showed its outcome in $tries runs - this host cannot see what the zeros claim to exclude"
    fi
  done
  if run_once "$bin" mp plain; then
    echo "     mp plain -O$lvl: $r_f of $r_w flag-seen rounds read stale data (reported, not required)"
  fi
done

echo
if (( failed > 0 )); then
  echo "check-atomics: $failed failed, $checks passed"
  exit 1
fi
echo "check-atomics: $checks checks - the five primitives lower to their ordering"
echo "               instructions on every target and level, and in the rounds run"
echo "               two threads on this host saw nothing sequential consistency forbids"
