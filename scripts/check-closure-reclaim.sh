#!/usr/bin/env bash
# THE CLOSURE-APPLICATION RECLAMATION GATE (docs/memory-model.md
# MM-LIFE-2c, the closure half).
#
# A DIRECT call has given back the owned temporaries it consumed since
# MM-LIFE-2g - `releaseOwnedArgs` in self_host/codegen.ax. An
# application THROUGH A CLOSURE gave back nothing at all, and the
# clearest measurement of the gap is that the same work costs 0 bytes
# a call one way and 32 the other:
#
#   direct call, owned argument            0 bytes per call
#   closure chain, two arguments          32 bytes per call
#
# 32 is the inner closure the first step of a curried chain returns.
# Every function value absorbs exactly one argument, so a two-argument
# handler is a chain, and the record step 1 answers is born at count 1,
# consumed by step 2, and was then simply dropped. `stdlib/Fallible.ax`
# recorded that cost as a REASON ITS OPERATION TAKES ONE ARGUMENT,
# which is a language design decision taken because of a compiler
# defect; the row is now 0 and the header says so.
#
# WHY THIS IS NOT `tests/stdlib/460-closure-reclaim.ax` ALONE. The
# fixture's byte terms are FLAT LINES, and this repository's standing
# rule is that a flat line also reads flat when the measurement is
# broken. The fixture answers half of that from the inside - its terms
# 4 and 2 check that the chains still ANSWER correctly, so a compiler
# that released a record still in use fails them - but nothing in a
# fixture can change the compiler, so nothing in it can show that the
# COMPILER is what makes the byte terms flat.
#
# This gate can. It takes the one word the fix turns on, turns it off,
# rebuilds the compiler from the ablated tree, and requires the fixture
# to go red at exactly the byte terms and at no other.
#
#   `recOwned` in `emitApplyRegsOwned` and `emitApplyChainOwned` is 0
#   for the record the caller handed in - the handler out of the
#   evidence slot, or a closure value someone else's `let` holds - and
#   1 for a record a previous step of the same walk returned. Only the
#   second is this walk's to give back. The ablation is `(== recOwned
#   1)` -> `(== recOwned 9)` in both walkers: no record is ever the
#   walk's own, which is what the compiler believed before 2026-08-30.
#
# Measured 2026-08-30 on darwin-aarch64:
#
#   built from the tree      460 exits 255  closure chain delta 80 B
#   built from the ablation  460 exits 199  closure chain delta 45,664 B
#
# 255 - 199 = 56 = 32 + 16 + 8, which is every byte term and only the
# byte terms: the correctness terms, the parked-argument term and the
# step count hold in both, so the ablation restores the defect rather
# than breaking the program. 45,664 is 32 bytes x 1,428 applications,
# the number Fallible.ax's table was written from, to the byte.
#
# The delta is what this gate asserts, not the totals, so a term added
# for some other question moves both numbers and leaves 56 alone. Term
# 128 was added the same day and did exactly that: 127/71 became
# 255/199. Its own discrimination is a DIFFERENT ablation - revert
# `checkLamAgainst`'s third caller in self_host/typecheck.ax and the
# fixture exits 127, which is 255 with term 128 struck out and nothing
# else moved.
#
# TERMS 64 AND 128 ARE NOT ABOUT THIS FIX. They are about the store
# inside a lifted lambda, and both changed meaning on 2026-08-30.
#
# A store inside a lifted lambda used to take NO share. `MM-LIFE-2g`'s
# `__retainref` is stamped from an evidence word, and a lambda had none
# for its own parameter, so a parked reference sat in the container
# uncounted. Two consequences, one latent and one live:
#
#   TERM 64, latent. A closure application does not release its owned
#   ARGUMENT - 96 bytes an operation - and the design for closing it
#   releases when the application's RESULT CLASS is a word. Under an
#   uncounted park that frees a block the container still points at.
#   Simulated with `__release` at exactly the point
#   `emitApplyChainOwned` would emit it, the term read 3 where it must
#   read 16, so the leak was load-bearing against that release.
#
#   TERM 128, live. Event 5 - a struct field overwritten by code that
#   never heard of the closure - reaches the same block from a frame
#   the closure never consulted, and answers to nothing. `check`
#   printed OK and the program read a string allocated after the free.
#
# BOTH ARE CLOSED. `checkLamAgainst` binds a declared parameter type
# instead of a minted placeholder, and a lifted lambda now takes an
# evidence word for its own argument, passed by the APPLICATION:
#
#   in a named `fn`   call @Vec$vecPush(i64 %box, i64 %s, i64 1)
#   in `_lam_0`       call @Vec$vecPush(i64 %.t2, i64 %m, i64 %.t5)
#
# with `%.t5` bit 0 of `%__evwa.h`. The `__release` probe now reads 16
# against the 3 it read before, so TERM 64 NO LONGER REFUSES THE
# RELEASE and the argument half is unblocked wherever the application
# classifies its argument.
#
# IT IS NOT UNBLOCKED IN GENERAL, and the two cases this header used to
# name were both wrong - corrected 2026-08-30, by probes that should
# have come before the sentence. The effect-operation path passes 0 and
# never needed more: a handler's parameter is the OPERATION's declared
# type, which `AX3017` will not let be a variable, so the retain is
# unconditional (`i64 1`, measured). The outer parameter of a curried
# lambda was not a leak but a live use-after-free, and the evidence
# words travel by depth now - `tests/stdlib/461-curried-closure-arg.ax`
# pins four depths and exits 139 on the compiler one commit back.
#
# THE TWO THAT REMAINED WERE PROBED ON 2026-08-31, and they were the
# same sentence wrong a third and fourth time. The surplus arguments of
# a `cast` spine and the over-applied path did not leak: both were LIVE
# USE-AFTER-FREES, for the same reason the curried case was. Measured
# against `9116167` (0.6.0), with a compiler built from that tree, on
# the shape `461` uses - a lambda parks its argument, the struct field
# it came from is overwritten, and a fresh string takes the freed
# block:
#
#   ((mkParker log) h.name)                    122, the `z`
#   ((cast Int (lambda (v) ..)) h.name)        122, the `z`
#   ((lambda (v) ..) h.name)                    97, the `a` - control
#
# `axiom check` printed OK on all three. Neither path carried the
# evidence word: `emitApplyChain` passed `vecNew`, so `evOperandAt`
# read 0 at every step, and for the `cast` spine the class had never
# been recorded at all because `checkCastForm` claims the whole spine
# at its outermost node and the intermediate application nodes never
# reach the arm that stamps them. `tests/stdlib/462-surplus-closure-arg.ax`
# is what pins both, and the section at the end of this gate is what
# makes it able to fail.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

fixture="$repo_root/tests/stdlib/460-closure-reclaim.ax"
want="$(tr -d '[:space:]' < "$repo_root/tests/stdlib/460-closure-reclaim.exit")"

# The fixture's own exit status IS its report: a bitmask, one bit per
# term, and `.exit` is the golden.
run_fixture() {  # <compiler> -> exit status
  ( "$1" run "$fixture" ) >"$work/run.$$" 2>&1
  printf '%s' "$?"
}

# --------------------------------------------------------------------
echo "== the tree as it stands gives the intermediate record back =="
# --------------------------------------------------------------------
rc="$(run_fixture "$axc")"
if [[ "$rc" == "$want" ]]; then
  ok "460-closure-reclaim exits $rc - every term, including 32, 16 and 8"
else
  bad "460-closure-reclaim exits $rc, wanted $want"
  echo "     the compiler under test is $axc"
fi

# --------------------------------------------------------------------
echo
echo "== and one word in each walker is what does it =="
# --------------------------------------------------------------------
# Ablated on a COPY of the tree: `gate_source_stamp` hashes
# `self_host/`, so an ablation left behind would silently become the
# tree every later gate builds from.
abl="$work/tree"
mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/" || {
  echo "FAIL: could not copy the tree to ablate" >&2; exit 1; }

target="$abl/self_host/codegen.ax"
if ! python3 - "$target" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
# Anchored on each walker's own body rather than on the bare guard,
# so a third use of `recOwned` added later is not silently ablated
# instead of - or as well as - these two.
pairs = [
    ("""(pub fn (emitApplyRegsOwned args regs cg rec i recOwned snode)""", "emitApplyRegsOwned"),
    ("""(pub fn (emitApplyChainOwned args cg rec i recOwned evs snode arel)""", "emitApplyChainOwned"),
]
for head, name in pairs:
    if s.count(head) != 1:
        sys.stderr.write("%s not found verbatim (%d matches)\n" % (name, s.count(head)))
        sys.exit(1)
    i = s.index(head)
    j = s.index("(== recOwned 1)", i)
    s = s[:j] + "(== recOwned 9)" + s[j + len("(== recOwned 1)"):]
open(p, "w").write(s)
PY
then
  bad "could not ablate the two walkers' recOwned guards"
  echo "     nothing was ablated, so the red half of this gate proves nothing"
else
  echo "-- rebuilding the compiler from the ablated tree --"
  if AXIOM_STDLIB="$abl/stdlib" "$axiom" build "$abl/self_host/main.ax" \
       -o "$work/axc-ablated" >"$work/ablated.build.log" 2>&1; then
    rc_abl="$(run_fixture "$work/axc-ablated")"
    if [[ "$rc_abl" == "$want" ]]; then
      bad "the ablated compiler still exits $rc_abl - the byte terms cannot fail"
    elif (( (want - rc_abl) == 56 )); then
      ok "the ablated compiler exits $rc_abl - terms 32, 16 and 8 and nothing else"
    else
      bad "the ablated compiler exits $rc_abl; wanted $((want - 56))"
      echo "     $want - $rc_abl = $((want - rc_abl)), so a term other than the"
      echo "     three byte terms moved and the ablation is not isolated"
      echo "     (terms 4 and 2 are the correctness half: if either moved, the"
      echo "      ablation broke the program instead of restoring the leak)"
    fi
  else
    bad "the ablated compiler did not build"
    sed 's/^/     /' "$work/ablated.build.log" | head -20
  fi
fi

# --------------------------------------------------------------------
echo
echo "== and the surplus argument of a spine carries its class too =="
# --------------------------------------------------------------------
# The OTHER axis from 460 and 461. Those two are about a lambda applied
# where it stands and about which of a curried chain's parameters is
# stored; this is the same one-parameter lambda storing its own
# argument, reached through the two application paths that are not
# `walkAppChain`'s own - `emitOverApplied`'s surplus and `cast`'s.
surplus="$repo_root/tests/stdlib/462-surplus-closure-arg.ax"
surplus_want="$(tr -d '[:space:]' < "$repo_root/tests/stdlib/462-surplus-closure-arg.exit")"

run_surplus() {  # <compiler> -> exit status
  ( "$1" run "$surplus" ) >"$work/surplus.$$" 2>&1
  printf '%s' "$?"
}

rc_s="$(run_surplus "$axc")"
if [[ "$rc_s" == "$surplus_want" ]]; then
  ok "462-surplus-closure-arg exits $rc_s - the control, the over-applied path and the cast spine"
else
  bad "462-surplus-closure-arg exits $rc_s, wanted $surplus_want"
  echo "     the compiler under test is $axc"
fi

# THE ABLATION, in two halves, because the fix is in two places and a
# single one would leave the other unproven. Each is planted on its own
# COPY of the tree, for the reason the ablation above states.
#
# The CHECKER half is the discriminating one: reverting it strikes out
# term 8 and nothing else, so the arithmetic names the term. The
# EMITTER half cannot be read that way and the honest answer is to say
# so - an uncounted park is not a value that reads oddly, it is a
# pointer whose block has been handed to someone else, and with two
# such parks in one process the blocks recycle into each other until a
# header read lands outside the heap. It exits 139. That is a red, and
# it is the same red `461` records for the compiler one commit back.
ablate_and_run() {  # <name> <relative file> <needle> <replacement> -> exit status, or "" on failure
  local name="$1" rel="$2" needle="$3" repl="$4"
  local tree="$work/abl-$name"
  rm -rf "$tree"; mkdir -p "$tree"
  cp -R "$repo_root/self_host" "$repo_root/stdlib" "$tree/" || return 1
  NEEDLE="$needle" REPL="$repl" python3 - "$tree/$rel" <<'PY' || return 1
import os, sys
p = sys.argv[1]
s = open(p).read()
needle, repl = os.environ["NEEDLE"], os.environ["REPL"]
if s.count(needle) != 1:
    sys.stderr.write("not found verbatim (%d matches): %s\n" % (s.count(needle), needle))
    sys.exit(1)
open(p, "w").write(s.replace(needle, repl, 1))
PY
  AXIOM_STDLIB="$tree/stdlib" "$axiom" build "$tree/self_host/main.ax" \
    -o "$work/axc-abl-$name" >"$work/abl-$name.build.log" 2>&1 || return 1
  ( "$work/axc-abl-$name" run "$surplus" ) >"$work/abl-$name.run" 2>&1
  printf '%s' "$?"
}

# The checker half: `cast`'s surplus goes unstamped again.
rc_b="$(ablate_and_run checker self_host/typecheck.ax \
  '(checkCastArgs tc args e 1 (vecLen args))' \
  '(checkArgsFromIndex tc args 1)')" || rc_b=""
if [[ -z "$rc_b" ]]; then
  bad "could not ablate the checker half - nothing was proven"
elif [[ "$rc_b" == "$surplus_want" ]]; then
  bad "the checker-ablated compiler still exits $rc_b - term 8 cannot fail"
elif (( (surplus_want - rc_b) == 8 )); then
  ok "the checker-ablated compiler exits $rc_b - term 8 and nothing else"
else
  bad "the checker-ablated compiler exits $rc_b; wanted $((surplus_want - 8))"
  echo "     $surplus_want - $rc_b = $((surplus_want - rc_b)), so a term other"
  echo "     than the cast spine moved and the ablation is not isolated"
fi

# The emitter half: `emitApplyChain` passes `vecNew` again, which is
# what it did until 2026-08-31, and takes BOTH of its callers with it.
rc_a="$(ablate_and_run emitter self_host/codegen.ax \
  '(emitApplyChainOwned args cg rec i 0 evs snode 0)' \
  '(emitApplyChainOwned args cg rec i 0 vecNew snode 0)')" || rc_a=""
if [[ -z "$rc_a" ]]; then
  bad "could not ablate the emitter half - nothing was proven"
elif [[ "$rc_a" == "$surplus_want" ]]; then
  bad "the emitter-ablated compiler still exits $rc_a - the evidence word is not load-bearing"
elif [[ "$rc_a" == "139" ]]; then
  ok "the emitter-ablated compiler exits 139 - two uncounted parks, a segmentation fault"
else
  ok "the emitter-ablated compiler exits $rc_a rather than $surplus_want"
fi

# --------------------------------------------------------------------
echo
echo "== and the last-step argument goes with a word answer =="
# --------------------------------------------------------------------
# The other half of this gate's subject: an application through a
# closure never released its owned argument at all, where a direct
# call has since MM-LIFE-2g. The rule fires only where all three
# hold - the last step (an intermediate answer is a record by
# construction), an owned argument that is neither static nor
# nullary, and a stamped word answer (`nodeResWord`, which the
# checker proves and defaults to keep). Surplus arguments keep
# theirs: the wrapper both surplus paths enter passes 0.
#
# `tests/stdlib/410-fallible.ax` term `e` is the measurement: a
# message built per malformed record over 10,000 records, flat when
# the argument goes with the call (80 bytes per operation before).
# The ablation below kills the stamp, not the walk: term `e` must go
# back to 0 while every other line of 410 and both exits beside it
# stay exactly where they are - 460's bitmask and 462's exit - or
# the ablation moved something it should not have.
term410="$repo_root/tests/stdlib/410-fallible.ax"
if "$axc" build --input "$term410" --output "$work/fall410" >"$work/fall410.build.log" 2>&1; then
  "$work/fall410" >"$work/fall410.out" 2>&1
  if (( $? != 0 )); then
    bad "410-fallible exits nonzero under test"
  elif ! cmp -s "$work/fall410.out" "$repo_root/tests/stdlib/410-fallible.out"; then
    bad "410-fallible's stdout differs under test"
    diff "$repo_root/tests/stdlib/410-fallible.out" "$work/fall410.out" | head -6 | sed 's/^/     /'
  else
    ok "410-fallible answers its fourteen lines under test, term e flat"
  fi
else
  bad "410-fallible did not build under test"
  sed 's/^/     /' "$work/fall410.build.log" | head -10
fi

argabl="$work/tree-arg"
rm -rf "$argabl"; mkdir -p "$argabl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$argabl/" || {
  echo "FAIL: could not copy the tree to ablate" >&2; exit 1; }
if ! python3 - "$argabl/self_host/typecheck.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
# The stamp write, and only it: `(setNodeResWord e (evResultWord
# funcTy))` occurs once, beside `evStampFill`. With no stamp every
# node reads the zero default and keeps its argument's release.
needle = "(setNodeResWord e (evResultWord funcTy))"
if s.count(needle) != 1:
    sys.stderr.write("resWord stamp not found verbatim (%d matches)\n" % s.count(needle))
    sys.exit(1)
open(p, "w").write(s.replace(needle, "0", 1))
PY
then
  bad "could not ablate the resWord stamp - nothing was proven"
else
  echo "-- rebuilding the compiler from the stamp-ablated tree --"
  if AXIOM_STDLIB="$argabl/stdlib" "$axiom" build "$argabl/self_host/main.ax" \
       -o "$work/axc-argabl" >"$work/argabl.build.log" 2>&1; then
    if "$work/axc-argabl" build --input "$term410" --output "$work/fall410a" >>"$work/argabl.build.log" 2>&1; then
      "$work/fall410a" >"$work/fall410a.out" 2>&1
      if (( $? != 0 )); then
        bad "410-fallible exits nonzero stamp-ablated"
      elif cmp -s "$work/fall410a.out" "$repo_root/tests/stdlib/410-fallible.out"; then
        bad "410-fallible still answers flat stamp-ablated - term e cannot fail"
      else
        # Thirteen of fourteen lines must be untouched: only term e
        # may move, from 1 back to 0. The count is captured first
        # because `diff` exits 1 on differing files, which `pipefail`
        # would otherwise read as the test failing.
        n_move="$(diff "$repo_root/tests/stdlib/410-fallible.out" "$work/fall410a.out" | grep -c '^[<>]' || true)"
        if [[ "$n_move" == "2" ]]; then
          line="$(diff "$repo_root/tests/stdlib/410-fallible.out" "$work/fall410a.out" | grep '^>' | head -1)"
          if [[ "$line" == "> 0" ]]; then
            ok "stamp-ablated term e reads 0, thirteen lines untouched"
          else
            bad "stamp-ablated diff is not term e going 1 -> 0: $line"
          fi
        else
          bad "stamp-ablated 410 differs by more than term e"
          diff "$repo_root/tests/stdlib/410-fallible.out" "$work/fall410a.out" | head -8 | sed 's/^/     /'
        fi
      fi
    else
      bad "410-fallible did not build stamp-ablated"
    fi
    # Isolation, both directions the earlier sections use: the stamp
    # ablation must not move the bitmask or the surplus exit.
    rc460a="$(run_fixture "$work/axc-argabl")"
    if [[ "$rc460a" == "$want" ]]; then
      ok "stamp-ablated 460 still exits $want"
    else
      bad "stamp-ablated 460 exits $rc460a, wanted $want - the ablation is not isolated"
    fi
    ( "$work/axc-argabl" run "$surplus" ) >"$work/argabl-surplus.run" 2>&1
    rc462a="$?"
    if [[ "$rc462a" == "$surplus_want" ]]; then
      ok "stamp-ablated 462 still exits $surplus_want"
    else
      bad "stamp-ablated 462 exits $rc462a, wanted $surplus_want - the ablation is not isolated"
    fi
  else
    bad "the stamp-ablated compiler did not build"
    sed 's/^/     /' "$work/argabl.build.log" | head -20
  fi
fi

echo
if (( failed > 0 )); then
  echo "check-closure-reclaim: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-closure-reclaim: $checks checks - a curried chain's intermediate"
echo "                       record is given back, the one word in each"
echo "                       walker that gives it back brings 32 bytes an"
echo "                       application back when removed, at the byte terms"
echo "                       only, and a SURPLUS argument - the over-applied"
echo "                       path and a cast spine - carries the evidence"
echo "                       class that makes its park a counted share"
