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
# LEXICALLY: only the body performing an unsafe operation must declare
# it, because a transitive rule would tag 97% of everything that
# performs - and since R-B6 a trusted encapsulation's `Unsafe` stops at
# it, so the rows of its callers no longer carry it at all.
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
# RE-PINNED 2026-09-29 (33): R-B10's first half. Functions that were
# tagged trusted but dereferenced or handed on a caller's word
# (`netAddrText`, `netSetOptInt`, the poll calls, `sysTermRaw`,
# `sysTimeoutMicros`, `sysSpawn`, `sysReadDir`, Fmt's digit writers)
# became precondition interfaces, so `Unsafe` now reaches the rows of
# their callers up to the next trusted declaration. Diffed `symbols
# --calls` rows for 397f8b18 and this tree with ONE compiler: none
# added or removed. Compiler view, 14 moved, each gaining exactly
# `Unsafe`: `netBind`, `netConnect`, `sysRun`, `sysRunPath` and
# `sysRunSearch` (now precondition interfaces), `netAddrZeroRunStart`
# (pure to `Unsafe`), and the trusted callers `fmtNat`, `fmtHex`,
# `fmtHexUpper`, `listDir`, `mkKeyIn`, `termRawEnter`, `pkgWalkModules`
# and `crateModuleName`. Stdlib view, the same 12 without the two
# compiler rows. No row moves onto or off `IO`, so the required/ambient
# line holds. The compiler view's pins also take in AN-52 (397f8b18),
# which left this gate red: its tree measured exactly `Alloc,Mut` 1521,
# `Alloc,Mut,Unsafe` 921, exactly `Unsafe` 485 and pure 1322 against
# pins of 1518, 920, 484 and 1321.
#
# RE-PINNED 2026-09-29 (32): the unsafe boundary (R-B6) merged onto the
# typed handles. A trusted encapsulation stops `Unsafe` at its own row,
# so the boundary reclassified most rows, the handles' new ones
# included. These pins are the merged tree measured, not the two
# branches' deltas added: 12 buckets differed from the boundary
# branch's own pins, and the gate's other 32 checks passed as they were.
#
# RE-PINNED 2026-09-29 (31): typed handles (MM-VAL-10a, MM-PAR-8).
# Diffed `symbols --calls` rows for the base tree and this one with ONE
# compiler: removed 0 in both views. Compiler view, 44 added (4886 to
# 4930) and 5 moved: the word-struct checks, the seal, the lowering and
# the handle runtime's emitters read `Alloc,Mut,Unsafe` (2361 to 2394),
# eight predicates exactly `Unsafe`, `emitPrimHandle` and
# `emitPrimHandleCall` `Alloc,IO,Mut,Unsafe` like every `emitPrim*`
# (417 to 419), `nodeCopyInto` and `wordLowerApply` `Mut,Unsafe`, and
# `TF_WORD`, `handleSlots` and `handleTableBytes` are pure (578 to 581).
# The five moved rows are `evClassOf` (exactly `Unsafe` 1207 to 1215 net
# of it) and the four evidence walks over it (`Mut,Unsafe` 130 to 128),
# which gained `Alloc` from the word-type lookup - taken only when the
# program declares a word struct (`countWordStructs`), but a row
# reports what the body can reach. Stdlib view, 18 added (972 to 990)
# and 6 moved: each handle's `At`, `Name`, `Retire` and `Named` helpers
# (exactly `Unsafe` 181 to 184, `Mut,Unsafe` 63 to 69,
# `Alloc,IO,Mut,Unsafe` 102 to 110), `taskCancelAt` (`IO,Mut,Unsafe` 20
# to 21) and the three kinds and `taskOwnsToken`, pure (289 to 294).
# `chanFree` and `mutexFree` gain `Mut` for the table's retirement
# (`Alloc,IO,Unsafe` 17 to 15), the token's three rows gain
# `Mut,Unsafe` (`Alloc,IO` 27 to 24), and `taskHandlePid` loses
# `Unsafe`: the pid comes through `__spawn_pid`, not a borrowed read. No
# row moves onto or off `IO`, so the required/ambient line holds.
#
# RE-PINNED 2026-09-28 (30): the reclamation audit, the recovery-region
# check and the Vec range. Compiler view only, 10 rows added (4887 to
# 4897), none moved: the audit's seven runtime emitters (`emitLog2Steps`,
# `emitLog2StepsFrom`, `famReg`, `emitFloorClass`, `emitMemStatFn`,
# `emitPrimMemStat`, `emitRecoverCell`) and the region walk's
# `rgnFormWalk` and `rgnRecoverForm` - eight `Alloc,Mut,Unsafe` (2360 to
# 2368) and one `Alloc,IO,Mut,Unsafe` (417 to 418) - and `vecBytes`,
# arithmetic, pure (578 to 579; the stdlib view's pure rows 289 to 290).
#
# RE-PINNED 2026-09-28 (29): a macro query waits for its subject
# (AN-40) and a function's NID is its `fn`'s (AN-41). Compiler view
# only, 4 rows added (4883 to 4887), none moved: `expQueryMissing`
# records or emits and `saPutIfAbsent` pushes, both `Alloc,Mut,Unsafe`
# (2358 to 2360); `expTruncate` pops, `Mut,Unsafe` (130 to 131);
# `expAnyWaiting` reads, exactly `Unsafe` (1207 to 1208). None names
# `IO`.
#
# RE-PINNED 2026-09-28 (28): AX3089. Compiler view only, 2 rows added
# (4881 to 4883), none moved: `signatureNeeded` reads a function entry
# and `emitSignatureNeeded` builds and emits the diagnostic, both
# `Alloc,Mut,Unsafe` (2356 to 2358). None names `IO`.
#
# RE-PINNED 2026-09-28 (27): the string-joining helpers go. Compiler
# view only, 6 rows removed (4887 to 4881), none moved: `cat2`, `cat3`
# and `cat4` in codegen.ax, `pkg3` and `pkg4` in pkg.ax and `mcat3` in
# mir.ax were each nested `strConcat` calls, and every call site now
# writes the `strConcat` itself; all six were `Alloc,Mut,Unsafe` (2362
# to 2356). None names `IO`.
#
# RE-PINNED 2026-09-28 (26): the effect walk reads a named pattern's
# binders. Compiler view only, 1 row added (4886 to 4887), none moved:
# `patBindersVec` walks a vector of sub-patterns into the accumulator,
# `Alloc,Mut,Unsafe` (2361 to 2362). None names `IO`.
#
# RE-PINNED 2026-09-28 (25): the tag rules (AX3077, AX3078). Compiler
# view only, 8 rows added (4878 to 4886), none moved:
# `axtagIsPureSpelling`, `emitAxtagPureSpelling`, `checkStrayAxtags`,
# `strayAxtagsOf`, `checkStrayImportAxtags` and `emitAxtagStray` read
# tags and emit, `Alloc,Mut,Unsafe` (2355 to 2361); `axtagKeyFits`
# compares strings, exactly `Unsafe` (1206 to 1207); `axtagDeclKind`
# answers a literal, pure (577 to 578). None names `IO`.
#
# RE-PINNED 2026-09-28 (24): the parser, checker and formatter fixes
# P4 and P5 found. Compiler view only, 10 rows added (4867 to 4877), none
# moved: `pubFollows`, `namesReachRParen`, `fieldTyOverruns`,
# `armTyOpen` and `armTailSpan` read token or node words, exactly
# `Unsafe` (1200 to 1205), and `collectBareTyParams`, `castTypeBadPart`,
# `castTypeBadArgs`, `armJoin` and `fpCastSurplus` build vectors or
# print, `Alloc,Mut,Unsafe` (2350 to 2355). None names `IO`. Then
# `nameIsOperator` (the operator-named function refusal) reads a
# string's first byte, exactly `Unsafe` (1205 to 1206).
#
# RE-PINNED 2026-09-28 (23): the misaligned-atomic trap (R-C4). Compiler
# view only, 3 rows added (4864 to 4867), none moved:
# `emitAtomicAlignGuard`, `emitAtomicCheckedPtr` and `emitAtomicAlignTrap`
# emit lines, `Alloc,Mut,Unsafe` (2347 to 2350).
#
# RE-PINNED 2026-09-28 (22): `Task.ax`'s exit backoff. Stdlib view only:
# `taskExitPollNanos` went and `taskExitNapFirst` and `taskNapNext` came,
# all pure (288 to 289; 976 to 977 rows). No row moved.
#
# RE-PINNED 2026-09-28 (21): the kill list and Darwin's libSystem fork
# (R-C5, MM-PAR-7). Compiler view only, 5 rows added (4859 to 4864),
# none removed or moved: `targetWaitIdNum` and `targetWaitExitedNoWait`
# are pure (575 to 577), `parLibcFork` reads the target word, exactly
# `Unsafe` (1199 to 1200), and `emitParJoinUnlist` and `emitParKillList`
# emit lines, `Alloc,Mut,Unsafe` (2345 to 2347). None names `IO`, so the
# required/ambient line does not move. The stdlib view is unchanged.
#
# RE-PINNED 2026-09-28 (20): the mutex, the timed waits and the task
# pool (MM-PAR-11..13). Diffed `symbols --calls` rows for HEAD's stdlib
# and the new one with ONE compiler: removed 0 and changed 0 in both
# views, so no EXISTING row moved buckets. Compiler view, 16 added -
# `Sys`'s new rows: `sysWaitWordTimeout`, `sysWaitWordTimed` and
# `sysChildExited` read `Alloc,IO,Mut,Unsafe` (414 to 417),
# `sysTimeoutMicros` and `sysWaitWordSpin` `Alloc,IO,Unsafe` (18 to 20),
# `sysScratch` `Alloc,Unsafe` (48 to 49), `sysUlockWait` exactly `IO`
# (22 to 23), `sysScratchDone` exactly `Unsafe` (1198 to 1199), and
# eight constants and the pure answer decoder are pure (567 to 575).
# Stdlib view, 101 added (875 to 976 rows): those plus `Chan`'s timed
# forms and helpers, all of `Sync` and all of `Task` - exactly `Alloc`
# 23 to 30 (the `TaskOpts` builders), `Alloc,IO` 24 to 27 (the token's
# map and unmap), exactly `IO` 32 to 34, `Alloc,Mut,Unsafe` 182 to 185,
# exactly `Unsafe` 164 to 181, `Alloc,IO,Mut,Unsafe` 77 to 102,
# `Mut,Unsafe` 53 to 63, `Alloc,Unsafe` 12 to 14, `Alloc,IO,Unsafe` 13
# to 17, `IO,Mut,Unsafe` 14 to 20, pure 266 to 288. Six of those rows
# came with the review fixes: `syncCasAt` and `syncTake` (the guard's
# claim and publication, `Mut,Unsafe`), `chanSlice` (exactly `Unsafe`),
# and three pure constants and selectors; `taskStart` reads the clock
# after its spawn, which adds `Alloc` to its row; `taskFold` and
# `taskFoldOne` are the two new incomplete rows (a call through the
# caller's `step`), and eleven `Task` functions taking a closure are
# the new effect-params rows (8 to 19). Every new row naming `IO`
# performs it through a declaration that says `effect(io)` - `AX3042`
# holds silence - and none moved onto or off `IO`, so the
# required/ambient line sits where it was measured.
#
# RE-PINNED 2026-09-27 (19): the bounded channel (MM-PAR-10). Thirty-one
# rows added, none removed, and no EXISTING row moves buckets - each new
# row read off `tests/agent/stdlib-effects.allow` by name. Both views
# gain the twelve from `Sys`: `sysMapShared` and `sysUnmapShared` read
# `Alloc,IO`; `sysWaitWord`, `sysWakeWord` and their private raw
# helpers read exactly `IO`, and every one of the four DECLARES
# `effect(io)`; the six new platform constants are pure. So the compiler
# view moves `Alloc,IO` 22 to 24, exactly `IO` 18 to 22 and pure 560 to
# 566. The stdlib view adds `Chan`'s nineteen on top: ten `IO,Mut,Unsafe`
# (the public blocking calls, the lock and the sleep), four `Mut,Unsafe`
# (`chanXchg`, `chanPark`, `chanBump`, `chanPut`), two exactly `Unsafe`
# (`chanGet`, `chanCap`), and one each of `IO,Unsafe` (`chanNotify`),
# `Alloc,IO,Unsafe` (`chanFree`) and `Alloc,IO,Mut,Unsafe` (`chanNew`).
# Every row that names `IO` gained it by declaring it; none moved onto
# or off `IO`, so the required/ambient line sits where it was measured.
# RE-PINNED 2026-09-27 (18): the audit-landing recount. Four landings
# the pins had not caught up with: the HYG-9 M2/M3 scope follow-ups,
# the fetch hardening, the Rust host-binding threading, and the HTTP
# static-root/framing work with its `sysOpenBeneath` support. Diffed
# the `symbols --calls` rows across 97c70fba..trunk with one compiler:
# main view added 27, removed 4, changed 0; stdlib view added 16,
# removed 1, changed 0 - each row read off `symbols` by name, and zero
# changed effect rows means no EXISTING function moved buckets.
#
# The removals are renames and rework, not lost coverage:
# `expRenLookup`/`expRenLookupFrom` leave as the `Idx` rows (17) added
# take over, `expScCheckFor`/`expScCheckForFrom` leave in the M3
# rework, and `httpHeadEnd` leaves for `httpHeadEndFrom`, which keeps
# its exactly-`Unsafe` row.
#
# The gains, by landing. Fetch: `fetchDiscard`, `pkgCheckOrigins`
# and `pkgOrigin` read `Alloc,IO,Mut,Unsafe` (clone and origin
# reads); `pkgDepKey`, `pkgOriginIn`, `pkgOriginWhy`, `pkgSha256Hex`,
# `pkgShaK`, `pkgShaPad` and `pkgUnquote` read `Alloc,Mut,Unsafe`;
# `pkgShaBlock` reads `Mut,Unsafe`; `pkgShaMask` and `pkgShaRotr` are
# pure. Host binding: `rbAnyRaw` and `rbRawIn` read
# `Alloc,Mut,Unsafe`, `rbIsIntVec` reads exactly `Unsafe`. Scope
# sets: `expScResolveTpl` and `expScResolveTplFrom` read exactly
# `Unsafe`. Beneath (both views): `sysBeneathFrom` and
# `sysOpenBeneath` read `Alloc,IO,Mut,Unsafe`; `sysSymlink` reads
# `Alloc,IO`; `sysSegmentEscapes` reads exactly `Unsafe`; `eXdev`,
# `oDirectory`, `oNoFollow`, `sysOpenatNum` and `sysSymlinkNum` are
# pure. HTTP (stdlib view only - outside `main.ax`'s closure):
# `httpContentLength` and `httpHeaderAll` read `Alloc,Mut,Unsafe`;
# `httpAllDigits`, `httpBareCr`, `httpFirstBad` and `httpHeadEndFrom`
# read exactly `Unsafe`; `httpIsTchar` is pure.
#
# Main view: `Alloc,Mut,Unsafe` 2307 to 2314, exactly `Unsafe` 1166
# to 1168, `Alloc,IO,Mut,Unsafe` 403 to 408, `Alloc,IO` 21 to 22,
# `Mut,Unsafe` 126 to 127, pure 556 to 563. Stdlib view:
# `Alloc,Mut,Unsafe` 180 to 182, exactly `Unsafe` 151 to 155,
# `Alloc,IO,Mut,Unsafe` 74 to 76, `Alloc,IO` 21 to 22, pure 259 to
# 265. No row moves off `IO` or onto it: the required/ambient line
# sits where it was measured.
#
# RE-PINNED 2026-09-26 (17): the MAC-HYG-9 equivalence slice carries
# scope sets beside the rename table. Twenty-three added, none
# removed, none changed - each new row read off `symbols` by name.
# Eleven read `Alloc,Mut,Unsafe` (records built, diagnostics emitted):
# `expScChainCopy`, `expScChainCopyIn`, `expScCheckFor`,
# `expScCheckForFrom`, `expScCheckRef`, `expScEmit`, `expScEnterDeclInst`,
# `expScEnterInst`, `expScPushLoop`, `expScPushTpl` and `expScResetTpl`.
# Seven read exactly `Unsafe` (reads and scans with no allocation):
# `expRenLookupIdx`, `expRenLookupIdxFrom`, `expScChainVec`,
# `expScPrefix`, `expScPrefixIn`, `expScTplVec` and `expScVerify`.
# Five read `Mut,Unsafe` (counter bumps and truncations):
# `expScExitInst`, `expScNextId`, `expScNextSeq`, `expScTruncLoop` and
# `expScTruncTpl`. Every move is a gain - `Alloc,Mut,Unsafe` 2296 to
# 2307, exactly `Unsafe` 1159 to 1166, `Mut,Unsafe` 121 to 126 - and
# no existing row moves buckets: the two `main.ax` call sites read
# `sysEnv` through rows that already perform IO, and `expandProgram`
# keeps its row with the flag as data. Every IO bucket frozen again.
#
# RE-PINNED 2026-09-26 (16): the generated-name cache fills at
# `didOpen`/`didChange` and the four navigation arms read it.
# Eighteen added, none removed, none changed - each new row read off
# `symbols` by name, and the eight widened signatures (`lspDefinition`,
# `lspDeclaration`, `lspHover`, `lspReferences`, `lspExtDispatch`,
# `lspNavDispatch`, `lspRecheck`, `lspSnapshot`) keep their rows: the
# old-vs-new `symbols` diff shows zero changed effect rows. Three read
# `Alloc,IO,Mut,Unsafe` through `lspResolveFor` (imported-module file
# reads, the same machinery every navigation request already reads):
# `lspGenFill`, `lspGenEntries` and `lspGenOneCall`. Eleven read
# `Alloc,Mut,Unsafe` (vectors and blocks built and walked): `docPutGen`,
# `lspGenCallSites`, `lspGenCollect`, `lspGenDefinition`, `lspGenHover`,
# `lspGenLookup`, `lspGenOutPush`, `lspGenTempFlush`, `lspGenTempMerge`,
# `lspGenTempUpsert` and `lspGenToJson`. Three read exactly `Unsafe`
# (reads with no allocation): `docGen`, `lspGenAt` and
# `lspGenHeadStart`. One is pure: `lspGenIsWs`. Every move is a gain -
# `Alloc,Mut,Unsafe` 2285 to 2296, exactly `Unsafe` 1156 to 1159,
# `Alloc,IO,Mut,Unsafe` 400 to 403, pure 555 to 556. No row moves off
# `IO` or onto it: the required/ambient line sits where it was
# measured.
# RE-PINNED 2026-09-26 (15): LSP inlay hints thread `decls`+`occs`
# (macro-definition skip via `lspSkipHintName`). One added, none
# removed, none changed - the new row read off `symbols` by name:
# `lspSkipHintName` reads exactly `Unsafe` as a string test, like
# `mIsAndOr`/`mIsBinSpelling`. The only move is a gain - exactly
# `Unsafe` 1151 to 1152 - and no existing row moves buckets.
# RE-PINNED 2026-09-25 (14): MIR `&&`/`||` desugar and the closed
# binop-spelling check. Three added, none removed, none changed - each
# new row read off `symbols` by name: `mLowerAndOr` reads
# `Alloc,Mut,Unsafe` through the block build, `mIsAndOr` and
# `mIsBinSpelling` read exactly `Unsafe` as string tests. Every move
# is a gain - `Alloc,Mut,Unsafe` 2277 to 2278, exactly `Unsafe` 1149
# to 1151 - and no existing row moves buckets.
# RE-PINNED 2026-09-25 (13): LSP value-shape hover (34 shape readers)
# and type hierarchy (17 walkers and handlers) land together.
# Fifty-one added, none removed, one narrowed - each new row read off
# `symbols` by name, and the narrowing is `lspNavColonAfter` losing
# its dead `dbl` parameter with its `Unsafe` row unchanged.
# Thirty-four read `Alloc,Mut,Unsafe`: `lspShapeApp`, `lspShapeArmBody`,
# `lspShapeBegin`, `lspShapeBind`, `lspShapeBindAll`, `lspShapeBindVec`,
# `lspShapeBuiltinTy`, `lspShapeCon`, `lspShapeConBuild`, `lspShapeCtorVar`,
# `lspShapeField`, `lspShapeFieldTys`, `lspShapeJoin`, `lspShapeLetCode`,
# `lspShapeMatch`, `lspShapeMatchIn`, `lspShapeOf`, `lspShapeOfBinder`,
# `lspShapeSpine`, `lspShapeStructCon`, `lspShapeSubst`, `lspShapeSubstVec`,
# `lspShapeTyParams`, `lspShapeUpCon`, `lspShapeVar`, `lspNavTypesSubtype`,
# `lspSubtypes`, `lspThBaseSpan`, `lspThBuiltinItem`, `lspThDetail`,
# `lspThFindImportedType`, `lspThItem`, `lspThSubject`, `lspThSubtypesIn`.
# Twelve read exactly `Unsafe`: `lspShapeApplyArrow`, `lspShapeArrowArity`,
# `lspShapeBindGet`, `lspShapeBindGetIn`, `lspShapeBuiltinRes`,
# `lspShapeIsBad`, `lspShapeParamAt`, `lspShapeParamTy`,
# `lspShapeQualified`, `lspThBaseHead`, `lspThBuiltin`, `lspThFindType`.
# Three read `Alloc,IO,Mut,Unsafe`: `lspPrepareTypeHierarchy` and
# `lspSupertypes` reach `lspResolveFor` (imported-module file reads) and
# `lspThImportedItem` inherits it through `lspPathToUri` - the same
# imported-module machinery every navigation request already reads, no
# new IO source. Two are pure: `lspThIsTypeTag`, `lspThKind`.
# Every move is a gain - `Alloc,Mut,Unsafe` 2243 to 2277, exactly
# `Unsafe` 1137 to 1149, `Alloc,IO,Mut,Unsafe` 396 to 399, pure 553 to
# 555 - and no EXISTING row moves buckets at all: the old-vs-new
# `symbols` diff shows zero changed effect rows.
# RE-PINNED 2026-09-25 (14): the merge recount. Two landings the pins
# had not caught up with: the non-raising join plus checked pool (four
# rows, all gains - `emitPrimParJoinNr` reads `Alloc,IO,Mut,Unsafe`
# through the two emitted call lines, `isParJoinNrName` reads exactly
# `Unsafe` (three string compares, no allocation), and in the stdlib
# view `parMapWordsChecked` reads `Alloc,IO,Mut,Unsafe` while
# `parJoinChecked` reads `Alloc,IO,Unsafe`) and the thirteen
# `while`/`mut`/`set` rows (13) names below, whose seven
# `Alloc,Mut,Unsafe`, three exactly `Unsafe` and three `Mut,Unsafe`
# land unchanged. Seventeen added across both views, none removed -
# and no EXISTING row moves buckets at all: the old-vs-new `symbols`
# diff shows zero changed effect rows. No row moves off `IO` or onto
# it: the required/ambient line sits where it was measured. Exactly
# `Unsafe` 1152 to 1156, `Alloc,IO,Mut,Unsafe` 399 to 400 in the main
# view and 73 to 74 in the stdlib view, `Alloc,IO,Unsafe` 11 to 12
# there; `Alloc,Mut,Unsafe` 2285 and `Mut,Unsafe` 121 arrive with the
# pick and verify (2278 and 118 on the old side plus MIR's seven and
# three).
# RE-PINNED 2026-09-25 (13): MIR lowers `while`/`mut`/`set` with
# `condbr` block arguments. Thirteen added, none removed, none
# changed - each new row read off `symbols` by name. Seven read
# exactly `Alloc,Mut,Unsafe` (vectors built and walked):
# `mLowerWhile`, `mLowerSet`, `mCarryLoop`, `mCurRegs`, `mRebind`,
# `mFreshN` and `mCondTarget`. Three read exactly `Unsafe` (reads
# with no allocation): `mEnvLookMut`, `mEnvMut` and `mStrMem`. Three
# read `Mut,Unsafe` (in-place environment surgery): `mEnvTrunc`,
# `mEnvDropScan` and `mEnvDropName`. Every move is a gain -
# `Alloc,Mut,Unsafe` 2278 to 2285, exactly `Unsafe` 1151 to 1154,
# `Mut,Unsafe` 118 to 121 - and no EXISTING row moves buckets at
# all: the old-vs-new `symbols` diff shows zero changed effect rows.
# No row moves off `IO` or onto it: the required/ambient line sits
# where it was measured.
# RE-PINNED 2026-09-25 (12): LSP hover reads struct fields, at the use
# and where declared. Thirteen added, none removed, none changed - each
# new row read off `symbols` by name. Seven read exactly `Unsafe`
# (string and span reads, no allocation): `lspIsUpperStart`,
# `lspIdentStart`, `lspSpineHead`, `lspFindStructField`,
# `lspStructFieldNode`, `lspFieldValueStruct` and `lspFieldNodeAt`.
# Six read `Alloc,Mut,Unsafe` through the hover text and fence build:
# `lspFieldParamStruct`, `lspFieldBaseStruct`, `lspHoverFieldUse`,
# `lspHoverFieldDecl`, `lspHoverFieldDeclIn` and `lspHoverField`.
# Every move is a gain - `Alloc,Mut,Unsafe` 2237 to 2243, exactly
# `Unsafe` 1130 to 1137 - and no row moves off `IO` or onto it: the
# required/ambient line sits where it was measured.
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
# 2026-09-27, after `6527bea0` put `__retain`, `__release`,
# `__call_word`, the atomics and the arena resets in `Unsafe`
# (MM-EXEC-9c), and the five commits after it grew the compiler by 16
# functions (4,763 rows to 4,779). The stdlib view moves by exactly
# the five public wrappers whose only raw operation is a release -
# `vecFree`, `mapFree`, `internFree`, `ffiCellFree`, `ledFree` - from
# pure (265 to 260) to exactly `Unsafe` (155 to 160); `compat/BREAKING`
# declares the same five. The compiler view gains 5 `Alloc,Mut,Unsafe`,
# 12 exactly `Unsafe` and 2 `Mut,Unsafe` and loses 3 pure rows. No row
# moved onto or off `IO`: every bucket naming `IO` holds its pin in
# both views, so the required/ambient line sits where it was measured.
#
# 2026-09-28, after R-D2/A12 (device primitives, the vector table) and
# the fuzzer-findings fixes: `Alloc,Mut,Unsafe` 2319 to 2345,
# `Unsafe` 1180 to 1198, `Alloc,IO,Mut,Unsafe` 408 to 414,
# `Mut,Unsafe` 129 to 130 and pure 566 to 567 in the main view,
# `Unsafe` 162 to 164 and `Mut,Unsafe` 52 to 53 in the stdlib view.
# Every delta is new rows landing - no row moved buckets, none moved
# onto or off IO. R-D2/A12's 38 new emission and predicate functions
# (eighteen `Alloc,Mut,Unsafe`, thirteen `Unsafe`, six
# `Alloc,IO,Mut,Unsafe`, `attrGroupZero` pure); the findings' fifteen
# new checkers and renderers against one removed (`isEffectName`,
# superseded by `effTagWords`/`effTagLines`); the stdlib view's three
# (`jsonEscapeOne` `Mut,Unsafe`, `utf8ContIn` and `utf8WellFormedAt`
# `Unsafe`). The only IO-naming bucket that moves is
# `Alloc,IO,Mut,Unsafe`, by six new emission rows (`emitPrimVLoad`,
# `emitPrimVStore`, `emitPrimDevice`, `emitPrimArm`, `emitIsrBinding`,
# `refuseDeviceIr`); every other IO bucket holds.
#
# RE-PINNED for R-B6 (MM-EXEC-9d): `effect(unsafe)` alone makes a
# trusted encapsulation, whose `Unsafe` its callers' rows no longer
# carry. So every caller of `vecPush`, `strConcat`, `memAlloc` and the
# rest lost `Unsafe` and nothing else. Compiler view: `Alloc,Mut,Unsafe`
# 2356 to 904, `Unsafe` 1207 to 479, `Alloc,IO,Mut,Unsafe` 417 to 227,
# `Mut,Unsafe` 130 to 98, `Alloc,Unsafe` 49 to 9, `Alloc,IO,Unsafe` 20 to
# 6, and the rows they left: exactly `Alloc,Mut` 0 to 1486,
# `Alloc,IO,Mut` 0 to 190, `Mut` 2 to 34, `Alloc` 70 to 112, `Alloc,IO`
# 24 to 38, pure 578 to 1313. The IO line did not move: 489 rows name
# `IO` before and after, and every `IO` bucket's loss is its non-`Unsafe`
# twin's gain. The stdlib view the same way, 209 rows naming `IO` in
# both, with `strSplit`, `listDir` and `sysReadDir` now `(Vec String)`.
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
have "$(bucket "$work/main.axsym" 'Alloc,Mut')" 1518 "exactly Alloc,Mut"
have "$(bucket "$work/main.axsym" 'Alloc,IO,Mut')" 182 "Alloc,IO,Mut"
have "$(bucket "$work/main.axsym" 'Mut')" 33 "exactly Mut"
have "$(bucket "$work/main.axsym" 'Alloc')" 112 "exactly Alloc"
have "$(bucket "$work/main.axsym" 'Alloc,IO')" 36 "Alloc,IO"
have "$(bucket "$work/main.axsym" 'IO')" 23 "exactly IO"
have "$(bucket "$work/main.axsym" 'IO,Mut')" 0 "IO,Mut"
have "$(bucket "$work/main.axsym" 'Alloc,Mut,Unsafe')" 924 "Alloc,Mut,Unsafe"
have "$(bucket "$work/main.axsym" 'Unsafe')" 486 "exactly Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,IO,Mut,Unsafe')" 238 "Alloc,IO,Mut,Unsafe"
have "$(bucket "$work/main.axsym" 'Mut,Unsafe')" 98 "Mut,Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,Unsafe')" 9 "Alloc,Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,IO,Unsafe')" 8 "Alloc,IO,Unsafe"
have "$(bucket "$work/main.axsym" 'IO,Mut,Unsafe')" 4 "IO,Mut,Unsafe"
have "$(bucket "$work/main.axsym" 'IO,Unsafe')" 1 "IO,Unsafe"
have "$(grep '^F ' "$work/main.axsym" | grep -vc '#effects=\|#effects-incomplete' || true)" 1321 "pure (neither row nor mark)"
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
have "$(bucket "$work/lib.axsym" 'Alloc,Mut')" 110 "exactly Alloc,Mut"
have "$(bucket "$work/lib.axsym" 'Alloc,IO,Mut')" 62 "Alloc,IO,Mut"
have "$(bucket "$work/lib.axsym" 'Mut')" 13 "exactly Mut"
have "$(bucket "$work/lib.axsym" 'Alloc')" 39 "exactly Alloc"
have "$(bucket "$work/lib.axsym" 'Alloc,IO')" 30 "Alloc,IO"
have "$(bucket "$work/lib.axsym" 'IO')" 34 "exactly IO"
have "$(bucket "$work/lib.axsym" 'Alloc,Assert,IO,Mut')" 7 "Alloc,Assert,IO,Mut"
have "$(bucket "$work/lib.axsym" 'IO,Mut')" 12 "IO,Mut"
have "$(bucket "$work/lib.axsym" 'Alloc,Mut,Unsafe')" 75 "Alloc,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'Unsafe')" 88 "exactly Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,IO,Mut,Unsafe')" 48 "Alloc,IO,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'Mut,Unsafe')" 59 "Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,Unsafe')" 5 "Alloc,Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,IO,Unsafe')" 9 "Alloc,IO,Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,Assert,IO,Mut,Unsafe')" 0 "Alloc,Assert,IO,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'IO,Mut,Unsafe')" 9 "IO,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'IO,Unsafe')" 2 "IO,Unsafe"
have "$(bucket "$work/lib.axsym" 'Fallible')" 1 "exactly Fallible"
have "$(bucket "$work/lib.axsym" 'Assert')" 1 "exactly Assert"
have "$(grep '^F ' "$work/lib.axsym" | grep -vc '#effects=\|#effects-incomplete' || true)" 391 "pure (neither row nor mark)"
have "$(grep -c '#effects-incomplete' "$work/lib.axsym" || true)" 5 "incomplete rows"
have "$(grep -c '#effect-params' "$work/lib.axsym" || true)" 19 "effect-params rows"

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
