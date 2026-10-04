#!/usr/bin/env bash
# The five atomic primitives, in machine code and on threads (R-C3).
#
# `__atomic_load`, `__atomic_store`, `__atomic_add`, `__atomic_cas` and
# `__fence` lower to sequentially consistent LLVM atomics with no target
# arm (`emitPrimAtomic`, self_host/codegen.ax). What LLVM then makes of
# `seq_cst` on each ISA was stated in that comment and checked by
# nothing: `check-freestanding.sh` says they lower inline, and
# `check-cross-targets.sh` says the objects relocate, and neither looks
# at an instruction. This gate does, and then runs them.
#
# FOUR SECTIONS.
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
#      casa, casl). windows-aarch64 adds barriers: LLVM ends every
#      seq_cst store and read-modify-write there with a trailing
#      `dmb ish`, because MSVC's runtime does not implement seq_cst
#      loads with `ldar` and a release store alone would not order
#      against them. `a64_dmb_want` states that count. A program with
#      no atomics (010-hello) must count
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
#      `--threads` at --opt 0..3, runs fifteen families on two threads
#      (three for wrc, isa2 and 3.sb, four for iriw), each printing
#      `<forbidden> <witnessed>`. A run is 500,000 rounds (200,000 for
#      iriw, wrc, isa2 and 3.sb); an atomic or fence row is three runs
#      per level, and a required control gets up to five runs to show:
#
#        sb sc | sb fence   forbidden 0 in every run
#        mp sc | mp fence   forbidden 0 in every run, flag seen > 0
#        add sc | add cas   forbidden (lost updates) 0 in every run
#        lb sc              forbidden 0 in every run, both loads 0 > 0
#        2+2w sc            forbidden 0 in every run, x 2 and y 2 > 0
#        r sc | r fence     forbidden (y ends 2, x read 0) 0 in every
#                           run; y ends 1 with x read 1 > 0, the one
#                           outcome only interleaved accesses give
#        s sc | s fence     forbidden (x ends 2, y read 1) 0 in every
#                           run; x ends 1 with y read 0 > 0, likewise
#        3.sb sc            forbidden (all three loads 0) 0 in every
#                           run; all three loads 1 > 0, the one outcome
#                           no order of whole bindings gives
#        iriw sc            forbidden 0 in every run, each reader's
#                           half of the outcome seen > 0
#        wrc sc | isa2 sc   forbidden 0 in every run, the chain (R1 saw
#                           the write, R2 saw R1's) formed > 0
#        corr sc            forbidden 0 in every run, reads straddling
#                           the store > 0
#        coww sc            forbidden 0 in every run, the reader saw x
#                           change > 0
#        cowr sc | corw sc  forbidden 0 in every run, the other
#                           binding's store read > 0
#        sb plain           CONTROL: forbidden > 0 in some run
#        add split          CONTROL: forbidden > 0 in some run
#        mp | lb | 2+2w | r | s | 3.sb | iriw | wrc | isa2 reorder
#        corr | coww | cowr | corw reorder
#                           CONTROL: forbidden > 0 in some run. The
#                           reordering is written into the program with
#                           the atomics, so sequential consistency allows
#                           the outcome and any host can show it: these
#                           prove the harness sees it when it happens.
#                           mp's, r's and s's second binding swaps its
#                           two accesses and makes the second wait for
#                           the first binding's store; 3.sb's bindings
#                           each load, wait until all three have, then
#                           store. Waiting for the event, as wrc's reader
#                           does, shows the outcome in nearly every round
#                           on a host where a fixed pause is too short.
#                           isa2's R2 does the same beside its writer's
#                           pause: with the pause alone, linux-aarch64
#                           showed nothing at -O1 and -O2 in 5 runs.
#                           For the four coherence families it is the
#                           only control there can be: x86-64 and AArch64
#                           keep every aligned access to one word
#                           coherent, plain or atomic, so their plain
#                           rows show nothing on any host this runs on
#        2+2w plain         CONTROL on darwin-aarch64 at -O1..-O3 only;
#                           reported elsewhere (below)
#        mp plain           reported, not required - x86 hardware never
#                           reorders this pattern, so at -O0 there is
#                           nothing to show and a requirement would fail
#                           on the one ISA whose answer is "correct"
#        wrc | isa2 plain   reported, not required. On darwin-aarch64
#                           wrc plain showed its outcome once or twice
#                           in some runs of 200,000 rounds (R1's store
#                           does not depend on its load, so the core may
#                           pass it ahead); x86-64 is TSO and forbids it
#        corr | coww | cowr | corw plain
#                           reported, not required, and expected 0 on
#                           every host: hardware coherence
#        lb | iriw plain    reported, not required. x86-64 is TSO, which
#        2+2w plain         forbids all three outcomes for plain accesses.
#                           On darwin-aarch64 (Apple M1, 2026-09-28, idle
#                           and with every core busy) lb plain showed in
#                           0 of 98 runs. iriw plain showed in 15 of 76,
#                           at every level but in bursts: 4 of 4 in each
#                           of two gate runs, 3 of 40 in a batch of runs.
#                           2+2w plain showed in 138 of 141 runs at
#                           -O1..-O3 and 22 of 47 at -O0, so it is
#                           required at -O1..-O3, with five tries. Other
#                           AArch64 cores, linux-aarch64's among them,
#                           were not measured, so it is reported there.
#                           (ARMv8's multi-copy atomicity forbids iriw
#                           only when each reader's loads stay in order,
#                           as `ldar` keeps them; plain loads may pass
#                           each other)
#
#        r | s | 3.sb plain reported, not required. x86-64 is TSO, which
#                           allows r and 3.sb (a store waits in the
#                           buffer while the next load runs) and forbids
#                           s. On darwin-aarch64 (M1) and linux-aarch64
#                           (podman on an M1), r plain and 3.sb plain
#                           showed their outcomes at every level in
#                           every run measured; s plain showed at
#                           -O1..-O3 on linux-aarch64 and seldom on
#                           darwin-aarch64. x86-64 was not measured
#
#      A control that never shows its outcome is a FAILURE, not a pass:
#      the zeros above it would then mean only that this harness cannot
#      see a reordering at all.
#
#      THE FENCE ROWS put `__fence` between plain accesses, which race:
#      MM-PAR-9 gives a racing plain access no defined value, so these
#      rows measure what this compiler and this hardware make of a
#      `fence seq_cst` between plain accesses (`dmb ish` on AArch64, a
#      locked `or` on x86-64), not a promise of the language.
#
#      DEPENDENCY VARIANTS ARE NOT RUN: Axiom cannot state one. The
#      language has one ordering, seq_cst, so the only access a
#      dependency could order is a plain load that races, whose value
#      MM-PAR-9 leaves undefined. LLVM keeps no dependency it can compute
#      away either: an address `f - f` from a loaded f folds to 0 at -O2,
#      and the two loads issue independently. A row would test LLVM's
#      current choices on an undefined program.
#
#   4. LSE. The driver calls llc with no -mcpu or -mattr, and llc picks
#      no LSE-capable CPU for any seed triple, `arm64-apple-macosx`
#      included (clang would choose apple-m1; llc does not), so section 1's
#      LL/SC loops are what every AArch64 build runs, an M1's included.
#      This section asks for the ARMv8.1 atomics by flag and counts again:
#
#        4a. The fixture and the control through the same pipeline with
#            -mattr=+lse for all three AArch64 targets, -mcpu=apple-m1
#            for darwin-aarch64 and -mcpu=neoverse-n1 for linux-aarch64,
#            at -O0..-O3. Each count must equal the source's uses:
#              load -> ldar   store -> stlr   add -> ldaddal
#              cas  -> casal  fence -> dmb ish
#            with no exclusive (an LL/SC loop where LSE was asked for)
#            and no LSE or RCpc form short of acquire-release (ldadd,
#            ldadda, ldaddl, stadd, staddl, cas, casa, casl, swp, swpa,
#            swpl, ldapr, ldapur). There is no exchange primitive, so no
#            `swpal` is expected. The control must count zero.
#        4b. add/cas weakened to monotonic, acquire and release, with
#            +lse at -O0 and -O2, and the load weakened to acquire under
#            neoverse-n1 at -O0 and -O2, must each turn 4a red. LSE gives
#            every ordering its own instruction at -O0 too, so these -O0
#            rows discriminate where section 2's cannot.
#        4c. On a host that executes LSE (Darwin's
#            hw.optional.arm.FEAT_LSE, or `atomics` in Linux's
#            /proc/cpuinfo), the litmus program is built by the driver
#            with llc wrapped to append -mattr=+lse, at every level. The
#            wrapper must have run once, and the binary's disassembly
#            must hold ldaddal and casal and no exclusive or weaker form.
#            Then the sb, mp and add rows, and their controls, run from
#            it. Any other host reports that it did not run them; Apple
#            silicon must.
#
# LIMITS. Sections 1 and 4 are one fixture's shapes, as this LLVM lowers
# them: section 1 for targets named by triple with no CPU, which is what
# the driver builds, and section 4 with LSE asked for by flag, which the
# driver never does. Machine code cannot tell every ordering apart on
# AArch64: a release store and a seq_cst one are both `stlr`, an
# acq_rel read-modify-write is `ldaddal`/`casal` like a seq_cst one, and
# without RCpc an acquire load is `ldar`. Section 3 is the rounds run, on
# this host, at these levels: an absent outcome is evidence, not proof,
# and a litmus pass on x86 says nothing about AArch64. The fifteen
# families are the classic two-, three- and four-thread shapes, not an
# exhaustive suite: the dependency variants cannot be written (above),
# and the rest of the catalogue is not run. The linux-x86_64,
# linux-aarch64 and darwin-aarch64 CI legs are the three hosts it runs
# on.
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
a64_targets="linux-aarch64 darwin-aarch64 freebsd-aarch64 windows-aarch64"

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

# asm <ll> <out.s> <level> [llc flag...]: the driver's pipeline, to
# assembly. Section 4 passes the LSE flags, to llc alone, as its build
# does.
asm() {
  local in="$1"
  if (( $3 > 0 )); then
    opt "-O$3" "$1" -S -o "$2.opt.ll" 2> "$2.log" || return 1
    in="$2.opt.ll"
  fi
  llc "$in" -filetype=asm "-O$3" -relocation-model=pic "${@:4}" -o "$2" 2>> "$2.log"
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

A64_LDADDAL='^[[:space:]]+ldaddal[[:space:]]'
A64_CASAL='^[[:space:]]+casal[[:space:]]'
A64_EXCL='^[[:space:]]+(ldxr|stxr|ldaxr|stlxr)[[:space:]]'
A64_LSE_WEAK='^[[:space:]]+(ldadd|ldadda|ldaddl|stadd|staddl|cas|casa|casl|swp|swpa|swpl|ldapr|ldapur)[[:space:]]'

# lse <asm> <want-load> <want-store> <want-add> <want-cas> <want-fence>:
# section 4's counts, each primitive on its own instruction.
lse_diff() {
  local s="$1" out="" g
  g="$(cnt "$s" "$A64_LDAR")";     [[ "$g" == "$2" ]] || out+=" ldar $g (want $2)"
  g="$(cnt "$s" "$A64_STLR")";     [[ "$g" == "$3" ]] || out+=" stlr $g (want $3)"
  g="$(cnt "$s" "$A64_LDADDAL")";  [[ "$g" == "$4" ]] || out+=" ldaddal $g (want $4)"
  g="$(cnt "$s" "$A64_CASAL")";    [[ "$g" == "$5" ]] || out+=" casal $g (want $5)"
  g="$(cnt "$s" "$A64_DMB")";      [[ "$g" == "$6" ]] || out+=" dmb-ish $g (want $6)"
  g="$(cnt "$s" "$A64_EXCL")";     [[ "$g" == 0 ]] || out+=" $g exclusive(s), an LL/SC loop where LSE was asked for"
  g="$(cnt "$s" "$A64_LSE_WEAK")"; [[ "$g" == 0 ]] || out+=" $g LSE or RCpc op(s) short of acquire-release"
  echo "$out"
}

# Measure this backend's Windows SC lowering independently of Axiom.
# LLVM 18 shares a cmpxchg exit barrier at -O0; LLVM 23 duplicates it
# across the success and failure exits. The reference uses the same
# pipeline and returns the old word, as the Axiom primitive does.
# Count each primitive separately so weakened fixture IR still fails
# against an unchanged seq_cst reference in section 2.
win_store_dmb=() win_add_dmb=() win_cas_dmb=()
for kind in store add cas; do
  ref="$work/backend-$kind.ll"
  cat > "$ref" <<'IR'
target triple = "aarch64-pc-windows-msvc"
define i64 @probe(ptr %p, i64 %v, i64 %expected) {
entry:
IR
  case "$kind" in
    store) cat >> "$ref" <<'IR'
  store atomic i64 %v, ptr %p seq_cst, align 8
  ret i64 0
}
IR
      ;;
    add) cat >> "$ref" <<'IR'
  %old = atomicrmw add ptr %p, i64 %v seq_cst, align 8
  ret i64 %old
}
IR
      ;;
    cas) cat >> "$ref" <<'IR'
  %pair = cmpxchg ptr %p, i64 %expected, i64 %v seq_cst seq_cst, align 8
  %old = extractvalue { i64, i1 } %pair, 0
  ret i64 %old
}
IR
      ;;
  esac
  for lvl in 0 1 2 3; do
    ref_asm="$work/backend-$kind.O$lvl.s"
    if ! asm "$ref" "$ref_asm" "$lvl"; then
      bad "Windows SC $kind reference -O$lvl: the pipeline failed"
      exit 1
    fi
    barriers="$(cnt "$ref_asm" "$A64_DMB")"
    if (( barriers == 0 )); then
      bad "Windows SC $kind reference -O$lvl: no trailing barrier"
      exit 1
    fi
    case "$kind" in
      store) win_store_dmb[$lvl]="$barriers"; d="$(a64_diff "$ref_asm" 0 1 0 "$barriers")" ;;
      add) win_add_dmb[$lvl]="$barriers"; d="$(a64_diff "$ref_asm" 0 0 1 "$barriers")" ;;
      cas) win_cas_dmb[$lvl]="$barriers"; d="$(a64_diff "$ref_asm" 0 0 1 "$barriers")" ;;
    esac
    if [[ -n "$d" ]]; then
      bad "Windows SC $kind reference -O$lvl:$d"
      exit 1
    fi
    ok "Windows SC $kind reference -O$lvl: acquire-release lowering, $barriers trailing barrier(s)"
  done
done

# a64_dmb_want <target> <level>: source uses times this backend's
# measured barriers per primitive, plus each explicit fence.
a64_dmb_want() {
  if [[ "$1" == windows-* ]]; then
    echo $((n_fence + n_store * win_store_dmb[$2] + n_add * win_add_dmb[$2] + n_cas * win_cas_dmb[$2]))
  else
    echo "$n_fence"
  fi
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
      d="$(a64_diff "$work/atomics.$t.O$lvl.s" "$n_load" "$n_store" $((n_add + n_cas)) "$(a64_dmb_want "$t" "$lvl")")"
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
  t=linux-x86_64; [[ "$isa" == a64 ]] && t=linux-aarch64; [[ "$isa" == w64 ]] && t=windows-aarch64
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
      d="$(a64_diff "$s" "$n_load" "$n_store" $((n_add + n_cas)) "$(a64_dmb_want "$t" "$lvl")")"
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
store     w64  0,2  $n_store  s/(store atomic i64 .*) seq_cst,/\$1 monotonic,/
fence     w64  0,2  $n_fence  s/^\s*fence seq_cst\n//
ROWS

# ---------------------------------------------------------------------
echo "== 3. litmus on this host, two, three and four threads =="
runs=3
# Apple silicon, the one host the 2+2w plain requirement was measured
# on: `uname` answers Darwin arm64 nowhere else.
apple=0; [[ "$(uname -s) $(uname -m)" == "Darwin arm64" ]] && apple=1
# run_once <bin> <family> <mode> -> sets $r_f $r_w; 1 on a bad run
run_once() {
  local out rc=0
  out="$(gate_timeout 120 "$1" "$2" "$3" 2> "$work/litmus.err")" || rc=$?
  if (( rc != 0 )) || [[ ! "$out" =~ ^-?[0-9]+\ [0-9]+$ ]]; then
    bad "$ltag$2 $3 -O$lvl: exit $rc, stdout '$out', stderr '$(head -1 "$work/litmus.err")'"
    return 1
  fi
  r_f="${out% *}"; r_w="${out#* }"
}

# in_scope <family>: whether $scope, family names between spaces, takes
# it. An empty $scope takes every family.
in_scope() { [[ -z "$scope" || "$scope" == *" $1 "* ]]; }

# litmus_rows <bin>: every row of the families $scope takes, at level
# $lvl, each line led by $ltag.
litmus_rows() {
  local bin="$1" row forb wit good k none seen tries
  local -a required reported
  for row in "sb sc" "sb fence" "mp sc" "mp fence" "add sc" "add cas" "lb sc" "2+2w sc" \
             "r sc" "r fence" "s sc" "s fence" "3.sb sc" "iriw sc" \
             "wrc sc" "isa2 sc" "corr sc" "coww sc" "cowr sc" "corw sc"; do
    set -- $row
    in_scope "$1" || continue
    forb=0; wit=0; good=1
    for ((k = 0; k < runs; k++)); do
      run_once "$bin" "$1" "$2" || { good=0; break; }
      forb=$((forb + (r_f < 0 ? -r_f : r_f))); wit=$((wit + r_w))
    done
    (( good )) || continue
    # What a zero witness means: the rounds never overlapped the way the
    # forbidden outcome needs, so its absence says nothing.
    case "$1" in
      mp)   none="no round saw the flag" ;;
      lb)   none="no round had both loads answer 0, so the threads never overlapped" ;;
      2+2w) none="no round ended x 2 and y 2, so the stores never interleaved" ;;
      r)    none="no round ended y 1 with x read 1, so the two bindings' accesses never interleaved" ;;
      s)    none="no round ended x 1 with y read 0, so the two bindings' accesses never interleaved" ;;
      3.sb) none="no round had all three loads see the stores, so the three bindings never overlapped" ;;
      iriw) none="one reader never saw one write without the other" ;;
      wrc|isa2) none="no round had R1 see the first write and R2 see R1's, so the chain never formed" ;;
      corr) none="no round's two reads straddled the store" ;;
      coww) none="the reader never saw x change" ;;
      cowr|corw) none="the writer never read the other binding's store" ;;
      *)    none="" ;;
    esac
    if (( forb != 0 )); then
      bad "$ltag$row -O$lvl: the forbidden outcome $forb time(s) in $runs runs"
    elif [[ -n "$none" ]] && (( wit == 0 )); then
      bad "$ltag$row -O$lvl: $none, so the test tested nothing"
    else
      ok "$ltag$row -O$lvl: forbidden 0 in $runs runs (witnessed $wit)"
    fi
  done
  required=("sb plain" "add split" "mp reorder" "lb reorder" "2+2w reorder" "r reorder" "s reorder"
            "3.sb reorder" "iriw reorder" "wrc reorder" "isa2 reorder"
            "corr reorder" "coww reorder" "cowr reorder" "corw reorder")
  reported=("lb plain" "r plain" "s plain" "3.sb plain" "iriw plain" "wrc plain" "isa2 plain"
            "corr plain" "coww plain" "cowr plain" "corw plain")
  if (( apple && lvl > 0 )); then required+=("2+2w plain"); else reported+=("2+2w plain"); fi
  for row in "${required[@]}"; do
    set -- $row
    in_scope "$1" || continue
    seen=0; tries=0
    while (( seen == 0 && tries < 5 )); do
      tries=$((tries + 1))
      run_once "$bin" "$1" "$2" || break
      seen="$r_f"
    done
    if (( seen > 0 )); then
      ok "$ltag$row -O$lvl: CONTROL shows the forbidden outcome ($seen, run $tries) - the zeros above can fail"
    else
      bad "$ltag$row -O$lvl: CONTROL never showed its outcome in $tries runs - this host cannot see what the zeros claim to exclude"
    fi
  done
  if in_scope mp && run_once "$bin" mp plain; then
    echo "     ${ltag}mp plain -O$lvl: $r_f of $r_w flag-seen rounds read stale data (reported, not required)"
  fi
  for row in "${reported[@]}"; do
    set -- $row
    in_scope "$1" || continue
    if run_once "$bin" "$1" "$2"; then
      echo "     $ltag$row -O$lvl: the forbidden outcome $r_f time(s) in one run, witnessed $r_w (reported, not required)"
    fi
  done
}

scope=""; ltag=""
for lvl in 0 1 2 3; do
  bin="$work/litmus.O$lvl"
  if ! "$axc" build --threads --input "$litmus" --output "$bin" --opt "$lvl" > "$work/litmus.O$lvl.build" 2>&1; then
    bad "litmus --threads --opt $lvl did not build:"; sed 's/^/    /' "$work/litmus.O$lvl.build" | head -12; continue
  fi
  litmus_rows "$bin"
done

# ---------------------------------------------------------------------
echo "== 4. LSE: the ARMv8.1 atomics, asked for =="
# 4a. Section 1's fixture and control, with LSE named to llc. RCpc comes
# with both named CPUs, and is what lets an acquire load show as `ldapr`.
while read -r t flag; do
  for lvl in 0 1 2 3; do
    s="$work/lse.$t$flag.O$lvl.s"; cs="$work/lse-control.$t$flag.O$lvl.s"
    if [[ ! -f "$work/atomics.$t.ll" || ! -f "$work/control.$t.ll" ]]; then
      bad "[$t $flag] -O$lvl: section 1 emitted no IR for $t"; continue
    fi
    if ! asm "$work/atomics.$t.ll" "$s" "$lvl" "$flag" || ! asm "$work/control.$t.ll" "$cs" "$lvl" "$flag"; then
      bad "[$t $flag] -O$lvl: the pipeline failed"; sed 's/^/    /' "$s.log" | head -5; continue
    fi
    d="$(lse_diff "$s" "$n_load" "$n_store" "$n_add" "$n_cas" "$n_fence")"
    c="$(lse_diff "$cs" 0 0 0 0 0)"
    if [[ -n "$d" ]]; then bad "[$t $flag] -O$lvl: the atomics fixture:$d"; continue; fi
    if [[ -n "$c" ]]; then bad "[$t $flag] -O$lvl: the no-atomics control is not clean:$c"; continue; fi
    ok "[$t $flag] -O$lvl: ldar, stlr, ldaddal, casal and dmb ish once per use, no exclusive and nothing weaker; control clean"
  done
done <<ROWS
linux-aarch64    -mattr=+lse
darwin-aarch64   -mattr=+lse
freebsd-aarch64  -mattr=+lse
darwin-aarch64   -mcpu=apple-m1
linux-aarch64    -mcpu=neoverse-n1
ROWS

# 4b. Each weakening must turn 4a red, at -O0 as well as -O2: unlike the
# LL/SC loops, LSE gives every ordering of a read-modify-write its own
# instruction at every level.
# kind  llc-flag  levels  want-matches  seam
while read -r kind flag levels want subst; do
  t=linux-aarch64
  for lvl in ${levels//,/ }; do
    in="$work/atomics.$t.ll"; out="$work/abl-lse-$kind.ll"; s="$work/abl-lse-$kind.O$lvl.s"
    if ! msg="$(ablate "$in" "$out" "$want" "$subst")"; then
      bad "lse $kind [$t]: the seam $msg - the emitter's spelling moved"; continue
    fi
    if ! asm "$out" "$s" "$lvl" "$flag"; then
      bad "lse $kind [$t $flag] -O$lvl: the ablated IR did not assemble"; continue
    fi
    d="$(lse_diff "$s" "$n_load" "$n_store" "$n_add" "$n_cas" "$n_fence")"
    if [[ -n "$d" ]]; then
      ok "lse $kind [$t $flag] -O$lvl: red -$d"
    else
      bad "lse $kind [$t $flag] -O$lvl: the weakened IR still passes section 4 - the check is blind to it"
    fi
  done
done <<ROWS
rmw-monotonic  -mattr=+lse        0,2  $((n_add + n_cas))  s/(atomicrmw add .*) seq_cst,|(cmpxchg .*) seq_cst seq_cst,/defined(\$1) ? "\$1 monotonic," : "\$2 monotonic monotonic,"/e
rmw-acquire    -mattr=+lse        0,2  $((n_add + n_cas))  s/(atomicrmw add .*) seq_cst,|(cmpxchg .*) seq_cst seq_cst,/defined(\$1) ? "\$1 acquire," : "\$2 acquire acquire,"/e
rmw-release    -mattr=+lse        0,2  $((n_add + n_cas))  s/(atomicrmw add .*) seq_cst,|(cmpxchg .*) seq_cst seq_cst,/defined(\$1) ? "\$1 release," : "\$2 release monotonic,"/e
load-acquire   -mcpu=neoverse-n1  0,2  $n_load             s/(load atomic i64, ptr \S+) seq_cst,/\$1 acquire,/
ROWS

# 4c. The litmus program, built by the driver with llc wrapped to add
# -mattr=+lse, on a host that executes LSE. Its disassembly must hold the
# LSE forms and no exclusive, so the rows below ran what they say.
lse_host=0; lse_why=""
case "$(uname -s) $(uname -m)" in
  "Darwin arm64")
    if [[ "$(sysctl -n hw.optional.arm.FEAT_LSE 2>/dev/null)" == 1 ]]; then lse_host=1
    else lse_why="sysctl hw.optional.arm.FEAT_LSE is not 1"; fi ;;
  "Linux aarch64")
    if grep -qw atomics /proc/cpuinfo 2>/dev/null; then lse_host=1
    else lse_why="/proc/cpuinfo lists no 'atomics' feature"; fi ;;
  *) lse_why="$(uname -s) $(uname -m) is not an AArch64 host this gate can ask" ;;
esac
if (( apple && !lse_host )); then
  bad "[lse] every Apple silicon core has LSE, yet $lse_why - the probe is broken"
elif (( !lse_host )); then
  echo "     [lse] litmus not run: $lse_why (reported, not required)"
elif ! command -v llvm-objdump >/dev/null; then
  bad "[lse] llvm-objdump is not on PATH, so an LSE build cannot be shown to be one"
else
  mkdir -p "$work/lse-bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@" -mattr=+lse\n' \
    "$work/lse-llc.log" "$(command -v llc)" > "$work/lse-bin/llc"
  chmod +x "$work/lse-bin/llc"
  scope=" sb mp add "; ltag="[lse] "
  for lvl in 0 1 2 3; do
    bin="$work/litmus-lse.O$lvl"; : > "$work/lse-llc.log"
    if ! PATH="$work/lse-bin:$PATH" "$axc" build --threads --input "$litmus" --output "$bin" --opt "$lvl" > "$bin.build" 2>&1; then
      bad "[lse] litmus --threads --opt $lvl did not build:"; sed 's/^/    /' "$bin.build" | head -12; continue
    fi
    llvm-objdump -d --no-show-raw-insn "$bin" > "$bin.dis" 2>&1
    calls="$(grep -c -- '-filetype=obj' "$work/lse-llc.log")"
    add_ops="$(grep -cE ':[[:space:]]+ldaddal[[:space:]]' "$bin.dis")"
    cas_ops="$(grep -cE ':[[:space:]]+casal[[:space:]]' "$bin.dis")"
    excl="$(grep -cE ':[[:space:]]+(ldxr|stxr|ldaxr|stlxr)[[:space:]]' "$bin.dis")"
    weak="$(grep -cE ':[[:space:]]+(ldadd|ldadda|ldaddl|stadd|staddl|cas|casa|casl|swp|swpa|swpl|ldapr|ldapur)[[:space:]]' "$bin.dis")"
    if (( calls != 1 || add_ops == 0 || cas_ops == 0 || excl != 0 || weak != 0 )); then
      bad "[lse] -O$lvl: not an LSE build - llc wrapped $calls time(s); ldaddal $add_ops, casal $cas_ops, exclusives $excl, weaker $weak"
      continue
    fi
    ok "[lse] -O$lvl: built through llc -mattr=+lse - $add_ops ldaddal, $cas_ops casal, no exclusive, nothing weaker"
    litmus_rows "$bin"
  done
fi

echo
if (( failed > 0 )); then
  echo "check-atomics: $failed failed, $checks passed"
  exit 1
fi
echo "check-atomics: $checks checks - the five primitives lower to their ordering"
echo "               instructions on every target and level, with and without LSE,"
echo "               and in the rounds run two, three and four threads on this host"
echo "               saw nothing sequential consistency forbids"
