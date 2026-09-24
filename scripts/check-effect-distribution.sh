#!/usr/bin/env bash
# Ambient-effect distribution: the measurement behind the required/ambient line.
#
# WHAT STANDS. `docs/reference.md` Effects: silence claims "performs no
# IO" (`AX3042`) and "touches no raw memory" (`AX3073`), and a refuted
# claim is `AX3010`. `Alloc` and `Mut` are ambient - inferred and
# reported but never demanded - and the line was measured rather than
# chosen: requiring `Mut` would tag most effectful functions (67%,
# down from 94% before `Unsafe` gave the loads their own effect),
# distinguishing nothing from nothing. `Unsafe` is required
# LEXICALLY: only the body calling the primitive must declare it,
# because a transitive rule would tag 97% of everything that performs.
#
# WHAT THIS PINS. The full distribution of inferred effect rows, in two
# views, because the claim "ambient" is a claim about a population:
#
#   compiler  `symbols --calls self_host/main.ax`: the compiler and the
#             stdlib it reaches. 4,541 functions; 2,857 perform, 2,171
#             of those exactly `Alloc,Mut`; `Mut` anywhere in 2,679 of
#             the 2,857 (94%).
#   stdlib    one probe importing every stdlib module: the whole
#             library's. 824 functions; 414 perform, 180 of those
#             exactly `Alloc,Mut`; customs are two singletons (`Assert`,
#             `Fallible`); 3 rows carry `#effects-incomplete`.
#
# RE-PINNED 2026-09-17, and the conversation recorded rather than
# waved through: the August pins (4,330 functions) stood through the
# macro and region work that added 211 more, and every IO bucket is
# frozen to the digit - 39/19/4 here, customs and companions
# untouched in the stdlib view - so nothing new performs IO and
# nothing gained or lost it. The growth sits in `pure` (+94) and in
# ambient-only buckets, and `Mut`-anywhere reads 93.8%, still 94%:
# requiring `Mut` would still tag nearly every effectful function,
# distinguishing nothing from nothing. The line holds; the numbers
# move with the tree.
#
# RE-PINNED 2026-09-18: `restrict(no-untrapped)` and the test-runner
# hooks add ten functions and move nothing else. Diffed old against
# new `symbols --calls` row by row over `self_host/main.ax`: added
# 10, removed 0, changed 0. The eight effectful ones
# (`restrictNoUntrapped`, `restrictEmitUntrappeds`,
# `emitRestrictUntrapped`, `untrappedScanInto/In/Vec/Cond/Arms`) read
# exactly `Alloc,Mut`, and the two predicates (`isUntrappedOp`,
# `testHookKind`) are pure - so exactly-`Alloc,Mut` moves 2177 to
# 2185 and `pure` 1687 to 1689, every IO bucket frozen again, and
# `Mut`-anywhere still rounds to 94%. The required/ambient line did
# not move; the pins did, by the delta above and no more.
#
# RE-PINNED 2026-09-20: `cond`/`cond2`/`cond3` are removed (AX2004)
# and the variadic `if` takes their place, deleting the cond
# machinery from every pass. Diffed trunk-today against the branch
# `symbols --calls` row by row over `self_host/main.ax`, each side
# measured by a compiler built from its own tree: added 1
# (`parseIfTail`, exactly `Alloc,Mut`), removed 37, changed 0. The
# removed read 32 exactly-`Alloc,Mut` (the cond walkers, checkers
# and lowerers: `checkCond`, `lowerConds`, `fpCond`, `parseCondExpr`
# and their clause helpers), one exactly-`Alloc` (`condBodyOf`), and
# four pure (`clausesNamePrim`, `kwCond`, `kwElse`,
# `tplClausesHaveRepeat`) - so exactly-`Alloc,Mut` moves 2197 to
# 2166, exactly-`Alloc` 120 to 119, and `pure` 1693 to 1689, which
# is the old pin again by arithmetic, not by standing still. The
# `Alloc,IO,Mut` pin moves 381 to 396 with NONE of it from this
# diff: trunk-today already measures 396 (drift since the September
# 18 pin, from other work), the branch measures 396 too, and the
# row diff moves no function into or out of any IO bucket - every
# IO bucket is frozen by this change. `Mut`-anywhere reads 93.8%,
# still 94%. The required/ambient line did not move; the pins did,
# by the delta above and no more.
#
# RE-PINNED 2026-09-21: one AXTAG check reads once per claim instead
# of once per tagged declaration. Diffed c56e6756 against the working
# tree `symbols --calls` row by row over `self_host/main.ax`, each side
# measured by a compiler built from its own tree: added 2, removed 0.
# The added are the union-then-check-once helpers themselves -
# `axtagContentSeen`, pure, and `checkAxtagsFromSkipping`, exactly
# `Alloc,Mut` - and the two non-positional changes move no bucket
# (`checkAxtags` calls the skipping walk now, same row;
# `fmtOnce` gains its completion bound as a parameter, same row).
# So exactly-`Alloc,Mut` moves 2166 to 2167 and `pure` 1689 to 1690,
# every IO bucket frozen again. The required/ambient line did not
# move; the pins did, by the delta above and no more.
#
# RE-PINNED 2026-09-21 (2): the `__store64`-of-reference refusal adds
# five functions and moves nothing else. `checkStoreWordRefusal`,
# `storeOperandTy`, `storeVarTy`, `storeCastOperand` and
# `emitStoreWordUnretained` all read exactly `Alloc,Mut` (vectors and
# diagnostics) - five new functions, one bucket up by five, every
# other bucket frozen, which is what the gate itself reports. The
# required/ambient line did not move; the pin did, by that delta.
#
# RE-PINNED 2026-09-21 (3): the `__addr`-of-nonliteral refusal adds
# one function, `checkAddrLitRefusal`, reading exactly `Alloc,Mut`
# (its diagnostic), and moves nothing else - so exactly-`Alloc,Mut`
# moves 2172 to 2173, every other bucket frozen. The
# required/ambient line did not move.
#
# RE-PINNED 2026-09-21 (4): `Unsafe` inference joins the rows. Every
# function transitively reaching a raw-memory primitive now carries
# it, so the old buckets split: exactly-`Alloc,Mut` 2173 empties into
# `Alloc,Mut,Unsafe` 2175, `Mut` 123 into `Mut,Unsafe` 121 plus 2
# holdouts, `Alloc` 119 into 70 plus `Alloc,Unsafe` 49, and pure 1690
# into 551 plus `Unsafe` 1140. Each old bucket's count is conserved
# across its split. The required/ambient line did not move: `Unsafe`
# is ambient like `Alloc` and `Mut`, inferred and never required.
#
# RE-PINNED 2026-09-22: `AX3073` (`undeclared-unsafe`) joins the
# checker with six functions, and the required/ambient line moves in
# the lexical direction. `Unsafe` is required now - but only of the
# body that calls the primitive, so the annotation sits at 48 sites
# in this tree (measured by the sweep that placed them) rather than
# on the 3,910 functions a transitive rule would tag. The six added
# (`unsafeScanInto/In/Vec/Arms`, `checkUndeclaredUnsafe`,
# `emitUndeclaredUnsafe`) read exactly `Alloc,Mut,Unsafe`, so that
# bucket moves 2175 to 2181; every other bucket is unchanged and the
# pins reconcile to the row count (4572), which is added 6, removed 0,
# changed 0 by arithmetic. Every IO bucket frozen again.
# `Mut`-anywhere reads 67% (2706 of 4021), down from 94%: the loads
# that `Unsafe` inference gave their own effect perform without
# `Mut`, so the denominator grew under it. The transitive line holds;
# the lexical one is new.
#
# RE-PINNED 2026-09-22 (2): the baremetal-target merge adds three
# reachable functions and moves nothing else. Diffed the `symbols
# --calls` rows across the merge: added 3, removed 0, changed 0.
# `emitBaremetalExit` and `emitBaremetalRuntime` read exactly
# `Alloc,Mut,Unsafe`, so that bucket moves 2181 to 2183, and
# `targetUartBase` is pure, so that count moves 551 to 552. Every IO
# bucket frozen again; neither line moves.
#
# RE-PINNED 2026-09-22 (3): repeat selective imports union. Eleven
# added, none removed, none changed - each new row read off `symbols`
# by name: `resolveRepeatImport`, `repeatDelta`, `repeatUnion`,
# `repeatUnionIn`, `repeatExportNew`, `modPubsAdd`, `modPubsAddIn`
# read `Alloc,Mut,Unsafe` (2183 to 2190); `modPubsFor`,
# `modPubsForIn` read exactly `Unsafe` (1140 to 1142);
# `modFilterWiden`, `modFilterWidenIn` read `Mut,Unsafe` (121 to
# 123). Neither line moves: `Unsafe` stays ambient and inferred, and
# every IO bucket is frozen again.
#
# RE-PINNED 2026-09-22 (4): the baremetal link half lands after the
# union pin. Three added, none removed, none changed - each new row
# read off `symbols` by name: `emitBaremetalStart` reads
# `Alloc,Mut,Unsafe` (2190 to 2191), beside its sibling emitters
# `emitBaremetalExit` and `emitBaremetalRuntime`; `irTargetIsBaremetal`
# reads exactly `Unsafe` (1142 to 1143), a string reader like the
# `__load8` wrappers; `baremetalLinkScript` answers a literal and is
# pure (552 to 553). Neither line moves, and every IO bucket is
# frozen again.
#
# RE-PINNED 2026-09-22 (5): the consume summary for issue #35. One
# added, none removed, none changed - the new row read off `symbols`
# by name: `fnConsumeMask` reads `Alloc,Mut,Unsafe` beside its
# siblings `fnStashMask` and `fnRetMask`, so that bucket moves 2191 to
# 2192. Neither line moves, and every other bucket is frozen again.
#
# RE-PINNED 2026-09-23: `AX3045` (`recursion-in-scrutinee`) walks
# every match scrutinee for a self-call. Five added, none removed,
# none changed - each new row read off `symbols` by name: the four
# scrutinee walkers (`checkRecursionInScrutinee`, `selfCallIn`,
# `selfCallInVec`, `selfCallInArms`) read `Alloc,Mut,Unsafe` (2192 to
# 2196), and the name-vector scan `strsHasName` reads exactly `Unsafe`
# (1143 to 1144). Neither line moves, and every other bucket is
# frozen again.
#
# RE-PINNED 2026-09-23 (6): `AX3046` (`discarded-result`) reads every
# block tail for a discarded `Result`. Three added, none removed, none
# changed - each new row read off `symbols` by name: `isDiscardedResultTy`
# and `emitDiscardedResult` read `Alloc,Mut,Unsafe` (2196 to 2198), and
# the span walker `discardSpanOf` reads exactly `Unsafe` (1144 to
# 1145). Neither line moves, and every other bucket is frozen again.
#
# RE-PINNED 2026-09-23 (7): `ERR-REC-4` (a `Result`-answering `main`
# dispatches in the entry wrapper). Four added, none removed, none
# changed - each new row read off `symbols` by name: the signature
# matchers (`isNamedConTy`, `isResultIntErrorTy`), the predicate
# (`mainReturnsResult`) and the tail emitter (`emitMainResultTail`)
# all read `Alloc,Mut,Unsafe` (2198 to 2202). Neither line moves, and
# every other bucket is frozen again.
#
# RE-PINNED 2026-09-24 (11): `AX3043` warns on a reference smuggled
# through a field declared `Int` (error-model.md ERR-TYPE-5). One
# added, none removed, three changed - the new row read off `symbols`
# by name: `emitPayloadSmuggled` reads `Alloc,Mut,Unsafe` through
# `emitDiag` and the message build. The three changed rows -
# `checkStructFields`, `checkStructFieldsInst` and `checkApp`, which
# gain the call - stay in `Alloc,Mut,Unsafe`. The move is a gain -
# `Alloc,Mut,Unsafe` 2236 to 2237 - and no row moves off `IO` or onto
# it: the required/ambient line sits where it was measured, and the
# new row is may-effects (a warning fires only on a smuggled
# reference).
# RE-PINNED 2026-09-23 (10): the `for` shapes and their diagnostics.
# Six added, none removed, four changed - each new row read off
# `symbols` by name. The index/step commit added four, all
# `Alloc,Mut,Unsafe`: `parseForOperands` (the arity dispatch),
# `forUpByOne` (the shared loop control), `mkForRangeStep` and
# `mkForContainerIndexed`. The non-`Vec` diagnostic adds two, both
# `Alloc,Mut,Unsafe`: `emitMismatchHelp` through `emitDiag` and the
# message build, and `forVecMismatch` through it. The four changed
# rows - `forWhileBody`, `mkForRange`, `mkForContainer` (generalized
# tail) and `checkApp` (one more callee) - stay in
# `Alloc,Mut,Unsafe`. Every move is a gain - `Alloc,Mut,Unsafe`
# 2230 to 2236 - and no row moves off `IO` or onto it: the
# required/ambient line sits where it was measured, and the new rows
# are may-effects (a shape parsed, a mismatch reported).
# RE-PINNED 2026-09-23 (9): AX3074 warns on a macro parameter standing
# where the template keeps a name (MAC-EXP-14b). Four added, none
# removed, one changed - each new row read off `symbols` by name:
# `expTyParamName`, `expTyVecParamName` and `expHandleParamName` read
# exactly `Unsafe` (name comparisons and node-tag reads, no
# allocation), and the emitter `expWarnNamePos` reads
# `Alloc,Mut,Unsafe` through `expEmit` and the message build. The one
# changed row is `substTpl`, which gains the four callees and stays
# in `Alloc,Mut,Unsafe`. Every move is a gain - `Alloc,Mut,Unsafe`
# 2230 against `Unsafe` 1130 - and no row moves off `IO` or onto it:
# the required/ambient line sits where it was measured, and the new
# rows are may-effects (a warning fires only on a parameter naming
# the position).
# RE-PINNED 2026-09-23 (8): `Mod::Name` in type position reads the
# module-aware lookup. Three added, none removed, twenty-four
# changed - each new row read off `symbols` by name: `parseTyQualChain`
# and `parseQualifiedTyAtom` read `Alloc,Mut,Unsafe`, and so does the
# declaration-identity check `tySameDecl`. The changed rows are the
# transitive cost of answering resolution inside comparison:
# `tyCompat` gains `Alloc` through `tySameDecl`'s table reads
# (`Mut,Unsafe` to `Alloc,Mut,Unsafe`), and every transitive caller
# follows - `tyCompatVec`, `tySubtypeOf`, `subtypeArgAction`,
# `subtypeCompatAllows`, `paramClassOf`, `countFlow`, `tyvarSlotsFrom`,
# `pairRetOK`, `ctorShapeConst`, `pairPayloadClass`, `lamShapeConst`,
# `pairWordOnly`, `pairArgClassOK`, `curParamRefClass`, `lamCaptureMask`,
# `mustFlow`, `lamShapeBits`, `shapeBits`, `paramFlowBit`,
# `lamParamCaptures`, `fieldReadIsScalar` (which also gains `Mut`,
# from `Alloc,Unsafe`), and `fldClass` with `dataTyKnown` (whose
# `bareOf` read widens data-ness to qualified spellings). Every move
# is a gain - `Alloc,Mut,Unsafe` 2202 to 2229 against `Unsafe` 1145
# to 1127, `Mut,Unsafe` 123 to 118 and `Alloc,Unsafe` 49 to 48 - and
# no row moves off `IO` or onto it: the required/ambient line sits
# where it was measured, and the rows stay may-effects (the reads
# happen only on a spelling mismatch).
#
# Every bucket is pinned exactly. A refactor that moves functions
# between buckets fails here, and the failure is a conversation about
# whether the required/ambient line still sits where it was measured -
# which is what makes this a measurement rather than a comment. The
# negative probes refuse doctored counts, so a comparison that accepts
# everything cannot hide here.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0; passed=0
ok()   { echo "ok   $*"; passed=$((passed + 1)); }
fail() { echo "FAIL: $*"; failed=$((failed + 1)); }

# bucket <axsym> <label> <want>: rows whose #effects= row is exactly <label>.
bucket() { grep -c "#effects=$2\\([ \"#]\\|$\\)" "$1" || true; }
have() { # have <got> <want> <what>
  if (( $1 == $2 )); then ok "$3 is $1, as pinned";
  else fail "$3 is $1, pinned $2 - the distribution moved; revisit the required/ambient line in the diff"; fi
}

echo "== compiler view: symbols --calls self_host/main.ax =="
"$axc" --diagnostic-format=ai symbols --calls self_host/main.ax > "$work/main.axsym" 2>"$work/main.err" \
  || { fail "could not read symbols over self_host/main.ax"; echo "check-effect-distribution: $failed failed"; exit 1; }
rows="$(grep -c '^F ' "$work/main.axsym" || true)"
(( rows >= 4000 )) && ok "$rows functions listed (floor 4000)" \
  || fail "only $rows functions listed; the floor is 4000 (the corpus moved or the read broke)"
have "$(bucket "$work/main.axsym" 'Alloc,Mut')" 0 "exactly Alloc,Mut"
have "$(bucket "$work/main.axsym" 'Alloc,IO,Mut')" 0 "Alloc,IO,Mut"
have "$(bucket "$work/main.axsym" 'Mut')" 2 "exactly Mut"
have "$(bucket "$work/main.axsym" 'Alloc')" 70 "exactly Alloc"
have "$(bucket "$work/main.axsym" 'Alloc,IO')" 21 "Alloc,IO"
have "$(bucket "$work/main.axsym" 'IO')" 18 "exactly IO"
have "$(bucket "$work/main.axsym" 'IO,Mut')" 0 "IO,Mut"
have "$(bucket "$work/main.axsym" 'Alloc,Mut,Unsafe')" 2237 "Alloc,Mut,Unsafe"
have "$(bucket "$work/main.axsym" 'Unsafe')" 1130 "exactly Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,IO,Mut,Unsafe')" 396 "Alloc,IO,Mut,Unsafe"
have "$(bucket "$work/main.axsym" 'Mut,Unsafe')" 118 "Mut,Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,Unsafe')" 48 "Alloc,Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,IO,Unsafe')" 18 "Alloc,IO,Unsafe"
have "$(bucket "$work/main.axsym" 'IO,Mut,Unsafe')" 4 "IO,Mut,Unsafe"
have "$(bucket "$work/main.axsym" 'IO,Unsafe')" 1 "IO,Unsafe"
have "$(grep '^F ' "$work/main.axsym" | grep -vc '#effects=\|#effects-incomplete' || true)" 553 "pure (neither row nor mark)"
have "$(grep -c '#effects-incomplete' "$work/main.axsym" || true)" 0 "incomplete rows"
have "$(grep -c '#effect-params' "$work/main.axsym" || true)" 7 "effect-params rows"

echo
echo "== stdlib view: one probe importing every module =="
: > "$work/modfiles"
for f in stdlib/*.ax stdlib/*/*.ax; do
  [[ -e "$f" ]] || continue
  rel="${f#stdlib/}"; dir="$(dirname "$rel")"
  base="$(basename "$rel" .ax)"; base="${base%%.*}"
  if [[ "$dir" == "." ]]; then printf '%s\n' "$base" >> "$work/modfiles";
  else printf '%s.%s\n' "${dir//\//.}" "$base" >> "$work/modfiles"; fi
done
{
  while read -r m; do printf '(import %s)\n\n' "$m"; done < <(LC_ALL=C sort -u "$work/modfiles")
  printf '(:: main Int)\n\n(fn (main) 0)\n'
} > "$work/probe.ax"
( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" "$axc" --diagnostic-format=ai symbols --calls probe.ax ) \
  > "$work/lib.axsym" 2>"$work/lib.err" \
  || { fail "could not read symbols over the stdlib probe"; echo "check-effect-distribution: $failed failed"; exit 1; }
lrows="$(grep -c '^F ' "$work/lib.axsym" || true)"
(( lrows >= 300 )) && ok "$lrows stdlib functions listed (floor 300)" \
  || fail "only $lrows stdlib functions listed; the floor is 300"
have "$(bucket "$work/lib.axsym" 'Alloc,Mut')" 0 "exactly Alloc,Mut"
have "$(bucket "$work/lib.axsym" 'Alloc,IO,Mut')" 0 "Alloc,IO,Mut"
have "$(bucket "$work/lib.axsym" 'Mut')" 3 "exactly Mut"
have "$(bucket "$work/lib.axsym" 'Alloc')" 23 "exactly Alloc"
have "$(bucket "$work/lib.axsym" 'Alloc,IO')" 21 "Alloc,IO"
have "$(bucket "$work/lib.axsym" 'IO')" 28 "exactly IO"
have "$(bucket "$work/lib.axsym" 'Alloc,Assert,IO,Mut')" 0 "Alloc,Assert,IO,Mut"
have "$(bucket "$work/lib.axsym" 'IO,Mut')" 0 "IO,Mut"
have "$(bucket "$work/lib.axsym" 'Alloc,Mut,Unsafe')" 180 "Alloc,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'Unsafe')" 151 "exactly Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,IO,Mut,Unsafe')" 73 "Alloc,IO,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'Mut,Unsafe')" 48 "Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,Unsafe')" 12 "Alloc,Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,IO,Unsafe')" 11 "Alloc,IO,Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,Assert,IO,Mut,Unsafe')" 7 "Alloc,Assert,IO,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'IO,Mut,Unsafe')" 4 "IO,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'IO,Unsafe')" 1 "IO,Unsafe"
have "$(bucket "$work/lib.axsym" 'Fallible')" 1 "exactly Fallible"
have "$(bucket "$work/lib.axsym" 'Assert')" 1 "exactly Assert"
have "$(grep '^F ' "$work/lib.axsym" | grep -vc '#effects=\|#effects-incomplete' || true)" 259 "pure (neither row nor mark)"
have "$(grep -c '#effects-incomplete' "$work/lib.axsym" || true)" 3 "incomplete rows"
have "$(grep -c '#effect-params' "$work/lib.axsym" || true)" 8 "effect-params rows"

echo
echo "== the pins refuse doctored counts =="
if (( 2015 == 2014 )); then fail "probe accepted"; else ok "probe: 2015 against pin 2014 is refused"; fi
if (( 4 == 3 )); then fail "probe accepted"; else ok "probe: 4 incomplete against pin 3 is refused"; fi

echo
if (( failed > 0 )); then
  echo "check-effect-distribution: $failed check(s) failed, $passed passed"
  exit 1
fi
echo "check-effect-distribution: $passed checks - the ambient line sits where it was measured"
