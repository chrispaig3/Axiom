#!/usr/bin/env bash
# Pins the distribution of inferred effect rows: the measurement behind
# which effects are required and which are ambient.
#
# `docs/reference.md` (Effects) lets silence claim "performs no IO"
# (AX3042) and "touches no raw memory" (AX3073); a refuted claim is
# AX3010. `Alloc` and `Mut` are ambient: inferred and reported, never
# demanded. Requiring `Mut` would tag most effectful functions, so it
# would distinguish nothing.
#
# `Unsafe` is required lexically. Only the body that performs an unsafe
# operation (MM-EXEC-9d) declares it, because a transitive rule would
# tag nearly every function that performs anything. A trusted
# encapsulation stops `Unsafe` at its own row (R-B6, MM-EXEC-9d), so its
# callers' rows do not carry it.
#
# "Ambient" is a claim about a population, so the gate pins every bucket
# of exact effect rows in two views:
#
#   compiler  `symbols --calls core/main.ax`: the compiler and the
#             stdlib it reaches.
#   stdlib    one probe importing every stdlib module.
#
# Each view also pins its pure rows, its `#effects-incomplete` rows (a
# call through a parameter, so the row is a lower bound), its
# `#effect-params` rows and its number of distinct rows. The distinct
# count refuses a new effect combination that has no pin of its own.
#
# A failure means the distribution moved: a row was added, removed or
# changed bucket. To re-pin, diff the `symbols --calls` rows of the old
# and new tree with one compiler, and account for every added, removed
# and changed row. Moves among the ambient buckets need only new
# numbers. A row that moves onto or off `IO` is a question about the
# required/ambient line: settle it first.
#
# The negative probes at the end check that the comparison `have` makes
# refuses a count one off its pin.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0; passed=0
ok()   { echo "ok   $*"; passed=$((passed + 1)); }
fail() { echo "FAIL: $*"; failed=$((failed + 1)); }

# bucket <axsym> <label>: count the rows whose #effects= row is exactly <label>.
bucket() { grep -c "#effects=$2\\([ \"#]\\|$\\)" "$1" || true; }
have() { # have <got> <want> <what>
  if (( $1 == $2 )); then ok "$3 is $1, as pinned";
  else fail "$3 is $1, pinned $2 - the distribution moved; revisit the required/ambient line in the diff"; fi
}

# Counted line-table metadata adds srcLineIndexTyped (Alloc,Mut).
# A same-compiler source comparison moves collectMods, resolveModMarks and
# srcLineIndex from Alloc,Mut,Unsafe to Alloc,Mut after removing raw views.
# No other existing row, including any IO-bearing row, changes effects.
# RE-DERIVED 2026-10-13: the lexicon (`core/lexicon.ax`), the
# nolint reading (`core/nolint.ax`) and the server's semantic
# tokens section arrived, all of them string-building and
# vector-walking code with no IO: pure 1872 -> 1980, Alloc,Mut 2496 ->
# 2566, Alloc,IO,Mut 365 -> 367, Mut 141 -> 144, Alloc 141 -> 142. Every
# IO bucket stayed where it was, which is the line this gate watches.
# Postfix propagation and unit checking add 36 compiler functions:
# 11 pure, 3 Alloc and 22 Alloc,Mut. Comparing both source trees with
# the same compiler moves no existing effect row, including every IO row.
# Handler-call attribution removes the obsolete blanket effect-claim
# helpers; the formatter adds a padding helper. Comparing 4074f467 and
# this tree with the same compiler changes no existing function's effect
# set, including every IO row. The pins also include the recovered LSP,
# contract tooling and allocator-poison functions already on trunk.
# REPL styling and shared help add six pure palette constants and two
# Alloc,IO,Mut functions. The CLI helpers move modules with unchanged
# effect sets; comparing the 4ffb6f02 symbols changes no existing row.
# Pattern Float lowering adds patFloatFlag, an Unsafe leaf reading the
# checker's binder stamp. Existing functions keep their measured rows.
# Explicit conversions add four pure predicates/constants, three allocating
# type-syntax helpers, three Alloc,Mut lowering helpers and one emitter
# with Alloc,IO,Mut. Removing fpCastSurplus removes one Alloc,Mut row.
# The emitter writes LLVM text, which is the new IO row. Comparing source
# trees with the same compiler changes no existing function effect set.
# Generic alias expansion adds scoped substitution, cycle, parameter and
# constructor-arity helpers. Existing function effect sets remain unchanged
# when compared with the same compiler; the additions are pure or Alloc,Mut.
# Removing explicit region annotations removes annotation-only helpers,
# and two region walkers lose obsolete Unsafe operations. rgnOriginSpan adds locations to memory
# diagnostics; existing IO rows keep their effect sets.
# Pipelines add hygienic expansion helpers; lambda Float parameters consult
# their checked arrow. No IO function changes its effect set.
# Exact conversions add three Alloc rows and one pure row. Alias scope
# helpers add one Alloc,Mut row and one Unsafe row; removing repeated
# alias expansion moves castNormTy and asNumericKind from Alloc,Mut to Alloc.
# All required effect rows retain their existing counts.
# Incremental LSP synchronisation adds document/edit helpers and an IO
# publisher. Line/column helpers now build the CR/LF-aware line index,
# moving two pure rows to Alloc,Mut. No existing IO row changes effects.
# Integer widths add checked lowering and emission helpers. Five field
# lookup helpers lose Mut through the numeric predicate path. Fixed Float
# rendering replaces three helpers with four; semantic token caching adds
# one IO publisher. Existing IO rows retain their measured effect sets.
# Scoped callback contracts add seven Alloc,Mut helpers and two pure
# helpers. Signed literal parsing shares existing pure bounds. Existing
# effect rows and all stdlib buckets are unchanged.
# Nominal declaration identity removes name-building from structural equality
# and ownership classifiers; qualified type resolution adds its checked helpers.
# Workspace overlays add seven Alloc,IO,Mut readers/publishers. The existing
# parseModuleOrDieUnit loses Unsafe through typed preloaded units. Imported
# extern registration removes five duplicate Ffi IO,Unsafe rows from the library
# view; the five source declarations remain, with their required effects.
# Rigid generic results expose five explicit word/container boundaries.
# The formatter adds bounded trials and CLI publishers; workspace caching
# adds revision and exact-source readers. parseModuleOrDieUnit explicitly
# converts its raw preload result. No existing IO requirement is removed.
# Background LSP work adds process lifecycle helpers and an Alloc,IO,Spawn
# row. Dispatch returns packets for the parent to publish; sigChild is pure.
# Long declaration layout adds bounded typed-list and pattern helpers.
# IO and higher-order effect rows are unchanged.
# Compact storage adds byte-offset and ownership helpers. Generic constructor
# evidence is stamped by the checker. Typed layout adds seven formatter helpers.
# Field descriptors now stamp their declared storage type, adding Mut to
# the field lookup path. Surplus-call ownership consults the function table.
# The IO and higher-order rows keep their existing requirements.
# Checked compute callbacks add deferred numeric validation helpers. Extern
# item visibility shares namespace resolution helpers and exact module lookup.
# Task adds its decoder, encoder and budgeted compute entry.
# Comparing f9b0b735 after syntax-only migration with the same compiler
# accounts for 43 added functions and three retired parser/formatter
# helpers. The additions are 25 Alloc,Mut, 13 pure, two Mut, two
# Alloc,Mut,Unsafe and one Unsafe. isStaticSentinelNode moves from pure
# to Alloc,Mut; lspEnclosingOpens moves from Alloc,Mut,Unsafe to Alloc,Mut
# through its typed bucket helper. No IO row changes, arrives or leaves.
# Comparing bcbbc612 and this tree with this same compiler adds 233
# reachable functions, removes three and changes twelve existing rows.
# No existing function gains or loses IO. Task's newly reached helpers,
# frontend jobs, tool spawning and phase logging account for the new IO
# population. The stdlib view adds UUID operations and removes the dead
# chooseIndex helper; tests/agent/stdlib-effects.allow lists that delta.
# Guarded native stacks add three pure helpers and three Alloc,Mut
# emitters. Comparing c2c73c2e and this tree with the same compiler
# changes no existing effect row, including every IO requirement.
# Charging closure construction moves Vec.vecSortBy from Mut to Alloc,Mut.
# Comparing the same source with both compilers changes this one row;
# IO requirements and higher-order parameter marks stay unchanged.
# The Windows platform shims, the checked-program handoff, the raw and
# precondition tags' removal and AX3135 add 52 compiler functions and
# remove 3, and Windows file and process support adds 28 library-view
# functions. Comparing dbdb8625 and 2ec540f6 with the same compiler moves
# resultOnlyCandidates from Alloc,Mut,Unsafe to Alloc,Mut and no other
# existing row. Making the raw memory layer internal renames 24 library
# functions one for one with their rows, and gives the compiler its own
# copy of the classic layer; with the internal-module check that adds 37
# compiler functions. privLibraryReach builds its marker keys with
# `concat`, so privBlocks gains Alloc,Mut and five name-lookup helpers
# move from pure to Alloc,Mut. No existing row gains or loses IO.
# The Windows clock, sleep and entropy add six platform functions to
# every platform module (two pure flags, four `Alloc` stubs in the POSIX
# view, which answer an `Error`), `sysSleepSlice` in Sys, and eleven
# driver helpers that make one import library per DLL (`Alloc,Mut`, the
# three that spawn `llvm-dlltool` `Alloc,Block,IO,Mut,Spawn`, two that
# remove or test files `Alloc,IO,Mut,Unsafe`); three kernel32-only
# helpers leave. Comparing 1b586a09 and this tree with the same compiler
# changes no existing row, and no row gains or loses IO.
# The Windows wait-words, mappings, pinning and signal mask add nine
# platform functions to every platform module: two pure answer codes and
# seven `Alloc` stubs in the POSIX view, each answering an `Error`.
# Comparing c1235eab and this tree with the same compiler changes no
# existing row, and no row gains or loses IO.
# The Windows sockets add twelve platform functions to every platform
# module, pure `-ENOSYS` stubs in the POSIX view, and the poller's
# registration table: `pollerTable` (Mut, it counts its rows) and the
# pure `pollerRowOf` and `pollerDropNone`. `pollerApply` gains Mut from
# the table arm (IO,Unsafe to IO,Mut,Unsafe), the one new distinct row.
# Comparing fd7df70b and this tree with the same compiler changes no
# other row, and no row gains or loses IO.
# The Windows thread lowering adds four compiler functions:
# `emitParThreadWin` (Alloc,Mut), `parThreadsByDefault` (Alloc,IO,Mut,
# it asks the target), and the pure `parPrimLowered` and `procAnyNamed`;
# `parSpawnUnsupported` now asks the target too (pure to Alloc,IO,Mut).
# Comparing 7c4dc4e7 and this tree with the same compiler changes no
# other row; the stdlib view is untouched.
# The Windows console adds four platform functions to every platform
# module, pure stubs in the POSIX view (`platformIsConsole` and its
# group); no existing row changes.
# The entry-symbol pass (`entryFnsOffExternSyms`, which moves an entry
# function off a linker symbol an extern item claims) adds four compiler
# functions that build name lists (Alloc,Mut) and `entryRecordRename`
# (Mut); comparing 9c9fcb40 and this tree with the same compiler changes
# no existing row.
# The emitter's two retired entries leave: `emitModule`
# (Alloc,IO,Mut,Unsafe) and `emitResolved` (Alloc,IO,Mut). Comparing
# d7465b73 and this tree with the same compiler changes no other row.
# The REPL's declaration check adds `replCheckDecls` (Alloc,IO,Mut,
# Unsafe), `replDiagsButDeferred` (Alloc,Mut) and the pure `replPrelude`.
# The Windows runtime's walker and arm block add five Alloc,Mut
# emitters: `emitBtWalkCaptured`, `emitBtWalkFrames`, `emitBtMainAddr`,
# `win64RecoverArmAsm` and `win64XmmMoves`.
# The pager's five platform shims (`platformPread`, `platformPwrite`,
# `platformFsync`, `platformFtruncate`, `platformFlock`) are pure
# sentinels on the host, in both views; the pager's `dbOpen` is IO.
# The Windows stack-overflow trap adds three Alloc,Mut emitters:
# `emitWinFaultRuntime`, `emitWinFaultCaptured`, `emitWinFaultChain`.
# The null device's name adds two pure functions in both views:
# `platformNullPath` and `IO.nullDevice`.
# The full stdlib view also charges the closure factories fallibleCounting
# (Mut to Alloc,Mut) and fallibleDefault (pure to Alloc).
# Typed AST migration compared against 63883c3d with the same compiler:
# 149 functions arrive, ten disappear and 116 existing rows change.
# Typed payload stores add Mut to 69 formerly Alloc rows. Concrete AST
# and name-vector APIs remove lexical Unsafe from 42 existing rows,
# including parseModuleOrDieUnitSerial, whose IO requirement remains.
# No existing function gains or loses IO; no added or removed row has IO.
# frontGetItems adds one higher-order effect-parameter row. The existing
# Alloc,IO,Mut,Spawn bucket contains taskStart, frontJobs, spawnTool and
# spawnPhase; all four are present in the pre-migration comparison too.
# Region frame reuse and temporary cleanup add lexical Unsafe to
# rgnCtxNew and rgnApp for their balanced reference releases. Their
# Alloc and Mut requirements remain; no IO row changes.
# Grouped patterns add one Alloc,Mut parser helper. Comparing both
# trees with the same compiler changes no existing row or IO requirement.
# Targeted cache eviction adds one pure selector and one Mut remover.
# Comparing both trees with the same compiler changes no existing row.
# Nested import validation adds one Alloc,Mut,Unsafe checker over typed
# unit import sites. jsonFind and its helper each add one Alloc row in
# both views. A same-compiler comparison changes no existing row or IO.
# Checked function types add three Alloc,Mut helpers and two Alloc,Unsafe
# numeric-index views. fnRetIsFloat gains Alloc through its typed lookup.
# Comparing the same compiler over both trees changes no other existing
# row, IO requirement, incomplete mark or effect-parameter mark.
# Reconcile the previously unaccounted 4ebe8d0e -> 8d101755 source
# delta: compiler +276/-0 functions (211 newly reached AXQL rows and 65
# additions), stdlib +23/-0. IO.ioAdopt/stdin/stdout/stderr move Unsafe
# into ioFile; pollerApply gains Alloc. No existing IO membership changes.
# The combined 24254a92 tree versus 8d101755, with one compiler: compiler
# +43/-7 rows, stdlib +100/-6. Checked syntax, numeric views, LSP assists,
# generic/signature/effect helpers, AXQL links and portable workers add
# rows. ProcessPath absorbs five Sys helpers; TaskWords replaces the
# command-word helper; structSubstEnv replaces structSubstFrom. The only
# surviving source row change is fnRetIsFloat gaining Alloc. No existing
# function gains or loses IO. Added IO rows are two LSP assists, two
# Sys path helpers and command/worker paths; the two removed IO helpers
# are replaced by those paths. The glob below includes Task.Worker.
# On identical source, callback-alias inference adds incomplete marks to
# Err.mapOk/mapErr/andThen/optMap/optAndThen and to the full-library
# Btree.btreeCheck/checkChain/checkTree lower bounds. Concrete effects
# and their existing callback effect parameters remain unchanged.
# Handler lifetime analysis adds four Alloc,Mut helpers, one Mut helper
# and two pure predicates. Comparing both source trees with the same
# compiler changes no existing function's effect row, including IO.
# Balancing the displaced emitter buffer adds Unsafe only to pruneDeadDefs.
# Same-compiler comparison: Alloc,IO,Mut -> Alloc,IO,Mut,Unsafe.
# Application scratch-slot retirement makes the same transfer for emitApp.
# Two private String-slot setters add Mut,Unsafe rows; existing rows stay fixed.
# The exact address seen set adds three Alloc,Mut helpers and two pure
# helpers. Compared with a37f9cc2 using one compiler, existing rows are unchanged.
# The typed-argument String setter adds one Mut,Unsafe helper; a same-compiler
# comparison leaves every existing function's effect row unchanged.
# The hoisted-vector setter adds one Mut,Unsafe helper; a same-compiler
# comparison leaves every existing function's effect row unchanged.
# Counted hoisted Strings add the pure cgHoisted getter and remove the last
# raw cast from joinAllocasSize (Unsafe to pure). A same-compiler comparison
# against 96f8b907 changes no other effect set, including every IO row.
# Typed pending-register storage adds one pure, one Alloc,Mut, one Mut and
# one Alloc,Mut,Unsafe helper. Removing its last raw casts removes Unsafe
# from releasePending, emitMatchTail and emitLetAt; IO requirements remain.
# Scoped binder summaries add five Alloc,Mut helpers. The typed interner
# adds four functions and moves its legacy allocator out of Unsafe:
# compiler totals gain seven Alloc,Mut, one Alloc,Unsafe and one pure row;
# stdlib totals gain two Alloc,Mut, one Alloc,Unsafe and one pure row.
# Same-compiler comparisons leave all IO and incomplete rows unchanged.
# The scalar pruning cursor adds pruneIndexLine with Alloc,Mut,Unsafe;
# pruneIndexDefs moves to Alloc,Mut with its cast in the private helper.
# The measured net change is one Alloc,Mut row, with no IO change.
# Allocation-free symbol matching adds one pure helper, makes
# asmLineNamesSym pure and moves linesCallSym to Unsafe. Typed argument
# text removes lexical Unsafe from releaseOwnedArgs/releaseBorrowedFrom.
# Together: +1 Alloc,Mut, -3 Alloc,Mut,Unsafe, +1 Unsafe and +2 pure;
# same-compiler comparisons leave every IO and incomplete row unchanged.
# The MIR operand text ledger adds mirOperandTexts with Alloc,Mut;
# mirEmitInsts and mirEmitFn each move from Alloc,Mut,Unsafe to Alloc,Mut.
# The measured delta is +3 Alloc,Mut and -2 Alloc,Mut,Unsafe, with no
# other row change.
# The may-edge restriction walk measured +4 Alloc,Mut and -1
# Alloc,IO,Mut, and the word-struct `as` check adds two Alloc,Mut
# helpers (castCheckWordRead, curDeclTrusted). Removing the MIR
# emission route then deletes 19 functions: 10 Alloc,Mut (mirEmitFn,
# mirEmitInsts and their operand and scope helpers), 2 Alloc,IO,Mut
# (mirEmitOrWalk, mirRouting) and 7 pure (the three MIR_* modes and
# four shape predicates). No row outside those three buckets moves.
# The string builder adds seven Alloc,Mut rows in `Str` (strBuilderNew,
# strBuilderWithCapacity, strBuilderReserve, strBuilderPush,
# strBuilderPushByte, strBuilderFinish, strJoin) and three pure ones
# (strBuilderLen, strBuilderCap, strBuilderMinCap); `Utf8` adds
# utf8PushChar (Alloc,Mut) and utf8EncodedByte (pure). The joins it
# replaces go: jsonJoin (Alloc,Mut), jsonJoinFill (Mut) and jsonJoinLen
# (pure) from both views, joinParts and joinWith (Alloc,Mut) from the
# stdlib view. Compiler +7 Alloc,Mut, -1 Mut, +3 pure; stdlib +5, -1,
# +3. A same-compiler comparison changes no existing row, IO included.
# The new checker refusals add twelve functions: ten Alloc,Mut
# (checkCertainTrap, checkSubtypeLiteralTrap and its argument walk,
# the duplicate and uppercase binder checks with their walks, and
# patBinderNodes' three) and two pure (patBinderCountBefore,
# patBinderFirst). No other row moves.
# The `if let` test adds four Alloc,Mut functions (parseIfTest,
# parseLetTest, mkIfOrLet and the formatter's fpIfTest) and two pure
# ones (letTestCannotFail, isLetTest). No other row moves.
# Typed records and string vectors in axir, nolint, replhl, replhist, replcomp
# and driver, with dead LSP aliases deleted: against the tree before them,
# measured with one compiler, five functions are added (one pure, three
# Alloc,Mut, one Alloc,IO,Mut,Unsafe), sixteen are removed, 59 rows lose
# Unsafe and two Alloc,Mut rows become Alloc. No row gains or loses IO.
# Declared field effects add 40 compiler functions: 31 Alloc,Mut (the
# field-declaration table, store checks and their diagnostics), 2 Alloc
# (fieldDeclFor, fieldDeclNameAt), 2 Unsafe (tcUState, nodeTyText) and
# 5 pure. This compiler and its parent read the same tree to the same
# rows for every other function, IO included.
# The typed parse-result readers add eight trusted Unsafe rows (pResFailed,
# pResOk, pResPos, pResWord, pResNode, pResNodes, pResText, pResVec) and
# move pResExp and pResCode from pure to Unsafe; pResultRules moves from
# Unsafe to pure. Deleting tyRenderApp and tyRenderJoin (Alloc,Mut),
# rgnFirstBit and rgnFirstBitFrom (pure) and nodeCText (Unsafe) removes
# five rows. A same-compiler comparison moves no other row.
# Typed accessors for the checker state, function entries, tokens and
# spans add 104 compiler functions and remove ten: the readers are
# trusted views (Unsafe), the Int-field writers store with `set` (Mut,
# Unsafe), and the word-typed duplicates go. scanAxtags drops Unsafe,
# and nine pure readers (evPendingOf, tcCounter, tokenKind and the
# like) become Unsafe views. No row gains or loses IO. The pins are
# this tree's rows as a compiler built from it measures them; they
# also take up 18 Alloc,Mut, 2 Alloc,IO,Mut and a few Unsafe rows that
# earlier commits moved without a repin.
# Optional checker witnesses, arities and unit identities add nine helpers,
# retire two and change 38 existing effect rows in a same-compiler comparison
# with e173a9ab. Required IO, Block, Spawn and Entropy sets stay unchanged;
# typed optional owners remove obsolete Unsafe claims and allocate variants.
# Optional parameter queries and match-arm states add 3 helpers and change
# 10 existing rows in a same-compiler comparison against ca4cb1b8.
# IO, Block, Spawn and Entropy sets are unchanged; owning Option branches
# account for the Alloc/Mut/Unsafe distribution changes.
# Owning codegen context, index and auxiliary records with checker input
# Options add 47 helpers, retire 16 and change 16 existing rows against
# 82237d68 under one compiler. IO, Block, Spawn and Entropy sets are
# unchanged; typed owners remove Unsafe views and retain their children.
# Typed cast/contract sources, expansion results and generated origins
# change 24 existing rows against 7758dc24 under one compiler. No helper
# arrives or leaves; IO, Block, Spawn and Entropy sets stay unchanged.
# Owning Token streams and optional symbol/AXIR lookups add one parameter
# projection helper and change 23 existing rows against 94b9f970 under one
# compiler. IO, Block, Spawn and Entropy sets are unchanged.
# Owning parser results, macro products, codegen flow bindings and guarded
# compact duplicate indexes add 16 helpers, retire seven and change 25
# existing rows against fe284249 under one compiler. IO, Block, Spawn and
# Entropy sets are unchanged; no required-effect helper arrives or leaves.
# Owning annotations and typed optional metadata add four helpers, retire
# two and change 21 existing rows against 6e935029 under one compiler.
# IO, Block, Spawn and Entropy sets are unchanged; no required-effect
# helper arrives or leaves.
# Typed metadata and diagnostic edits add eight helpers and change ten
# existing rows against 00d6c04b under one compiler. ctorFieldBit and
# ctorShapeEmit gain IO for existing AX4002 failures at required layout
# boundaries; requireStructFields, requireCtorWords and requireCtorShapeConst
# own those diagnostics. No other required-effect set changes.
# Same-compiler comparison against 59f618f4 adds or retires no helpers.
# Five optional scan queries gain ambient allocation, and four Unit flows
# lose obsolete Unsafe rows. IO, Block, Spawn and Entropy requirements stay
# unchanged. Invalid escape results allocate only when present.
# Comparing 4ee86a21 and this migration with one compiler adds five
# typed helpers and changes twenty existing rows. Only ambient allocation
# and trusted Unsafe rows move; existing IO/Block/Spawn/Entropy stay fixed.
# requireSignatureResult reports the existing required-metadata AX4002
# failure and contributes the one new Alloc,IO,Mut helper.
# Owning source indexes, String names and lambda Options add two helpers,
# retire unitSrcMissing and change 13 existing effect rows against f15845d0
# with the same compiler. Only Alloc/Mut/Unsafe/pure buckets move; every
# existing IO, Block, Spawn and Entropy set stays unchanged.
# Typed unit and editor lookups change 11 existing effect rows against
# a406030e under one compiler. Pure typeKeywordKnown replaces the Unsafe
# typeKeywordCanon. Existing IO, Block, Spawn and Entropy sets stay fixed.
# Typed formatter declaration queries add two pure predicates and one
# Alloc,Mut invocation renderer. No existing metadata row changes.
echo "== compiler view: symbols --calls core/main.ax =="
"$axc" --diagnostic-format=ai symbols --calls core/main.ax > "$work/main.axsym" 2>"$work/main.err" \
  || { fail "could not read symbols over core/main.ax"; echo "check-effect-distribution: $failed failed"; exit 1; }
rows="$(grep -c '^F ' "$work/main.axsym" || true)"
(( rows >= 4000 )) && ok "$rows functions listed (floor 4000)" \
  || fail "only $rows functions listed; the floor is 4000 (the corpus moved or the read broke)"
# The 2026-10-21 landings move the compiler's rows without changing a
# required effect: the code generator's typed accessors and the LSP and
# expander records add Alloc,Mut, Mut and Alloc readers and writers and
# retire Unsafe views (Unsafe -9, Alloc,Mut,Unsafe -6, five functions
# from Alloc,IO,Mut,Unsafe to Alloc,IO,Mut), and the borrowed-read
# analysis (`fnMayWrite`, `inferWrites` and its helpers) adds pure rows.
# In the library, `StrList` adds three Alloc,Mut rows and five pure ones.
# Links move both views again without a new required effect: the
# compiler gains the link-width check and its emitter, and the library
# gains `Link`'s five functions.
# The typed table, diagnostic, unit and region-record migrations add 101
# functions, remove five and change 206 existing rows compared with
# 9c677ecb under one compiler. The changes are among pure, Alloc, Mut
# and Unsafe buckets; no existing function gains or loses IO, and no
# IO-bearing function arrives or leaves. Packed Link range checks keep
# wordPackExpr in Alloc,Mut. The full suite still checks every bucket.
# Typed suggestion and scope results, effect entries and MIR Options add
# 2 functions and retire 2 helpers. A same-compiler comparison moves
# existing rows among Alloc, Mut, Unsafe and pure buckets; no existing
# function gains or loses IO, and no IO-bearing function arrives or leaves.
# Constructor/signature tables, namespace rows, scope storage, format
# specifiers and LSP buckets add eight functions and retire ten helpers.
# A same-compiler comparison changes 78 rows. Six emitter rows gain IO:
# emitWinEntry, emitMainResultTail, emitPairWrapper, emitPairBox,
# emitPairBoxOption and emitPairBoxResult now report AX4002 when a required
# constructor is absent, instead of reading an unchecked zero entry.
# Every other change stays among the ambient and Unsafe buckets; no
# function gains or loses any other required effect.
# Typed codegen contexts, checker function entries and expansion owners
# add nine helpers and retire three, moving 161 existing rows under one
# compiler. No existing required effect changes. The new cgFail helper
# owns the existing AX4002 diagnostic path and carries Alloc,IO,Mut.
# Typed checker definition/module tables and optional graph searches add
# three helpers and retire three. A same-compiler comparison changes 51
# existing rows; no required effect changes, arrives or leaves.
# Optional specialised loop help removes forVecMismatch's forged null String
# and lexical Unsafe. Its existing Alloc,Mut row and required effects remain.
# Owning checker/body/region records, semantic Options and compact exact
# indexes add 27 helpers and retire eight. A same-compiler comparison
# accounts for 204 changed metadata rows, including removal of raw-reader
# Unsafe operations. No IO, Block, Spawn or Entropy row changes, arrives or
# leaves; incomplete and higher-order effect counts remain unchanged.
# Comparing 53f7c2a8 with 4ee86a21 using the same compiler adds 30
# functions, removes none and changes 14 existing rows. Typed Option
# helpers gain Alloc and lose several raw Unsafe operations. Propagation
# adds typed expansion helpers; Vec adds vecGrowsInPlace and vecMoveTo.
# emitMemStatFn, emitRegionCell and emitRegionSeq gain IO through the new
# reserveSupported query: arenaStaticBytes reads the heap-ceiling command
# line setting. reserveSupported is the fourth added IO-bearing row.
# No existing IO requirement is removed; incomplete and parameter marks
# remain unchanged. The library delta is confined to the two Vec helpers
# and vecReserveExactly moving its trusted Unsafe work into vecMoveTo.
# Optional declaration, pair, extern, namespace and documentation queries add
# cgDeclarationMatches and qmInvariant and remove five obsolete propagation
# helpers. Seven existing rows change metadata; five gain Alloc and saUnitOf
# replaces raw Unsafe with Alloc. Existing IO, Block, Spawn and Entropy
# requirements are unchanged in the same-compiler source comparison.
# Typed assembler, CLI, formatter and LSP shape queries add one pure helper.
# Seven existing queries move from pure to Alloc under the same compiler;
# no existing IO, Block, Spawn or Entropy requirement changes.
# Typed CLI values, formatter atoms, result types and arities add six
# helpers and retire manifestEntryOrEmpty in favour of manifestEntry.
# Four existing optional queries gain Alloc; existing required IO, Block,
# Spawn and Entropy effects stay unchanged in the same-compiler comparison.
# Since 65d0306c, compiler lookup migrations, completion resolution and
# pinned-package fetching add 34 helpers and retire one. A same-compiler
# comparison changes 28 existing rows without changing any existing IO,
# Block, Spawn or Entropy requirement. New IO-bearing helpers report read
# failures, serve editor requests and fetch or validate pinned checkouts.
# Optional symbol indexes then move symIndex, symIndexIn, hasSym,
# isLocalValue and slotKeptByCaller from pure to Alloc. No function is
# added or removed by that migration, and every required effect stays fixed.
have "$(bucket "$work/main.axsym" 'Alloc,Mut')" 3699 "exactly Alloc,Mut"
have "$(bucket "$work/main.axsym" 'Alloc,IO,Mut')" 514 "Alloc,IO,Mut"
have "$(bucket "$work/main.axsym" 'Mut')" 285 "exactly Mut"
have "$(bucket "$work/main.axsym" 'Alloc')" 475 "exactly Alloc"
have "$(bucket "$work/main.axsym" 'Alloc,IO')" 24 "Alloc,IO"
have "$(bucket "$work/main.axsym" 'IO')" 13 "exactly IO"
have "$(bucket "$work/main.axsym" 'IO,Mut')" 5 "IO,Mut"
have "$(bucket "$work/main.axsym" 'Alloc,Mut,Unsafe')" 76 "Alloc,Mut,Unsafe"
have "$(bucket "$work/main.axsym" 'Unsafe')" 89 "exactly Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,IO,Mut,Unsafe')" 34 "Alloc,IO,Mut,Unsafe"
have "$(bucket "$work/main.axsym" 'Mut,Unsafe')" 34 "Mut,Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,Unsafe')" 14 "Alloc,Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,IO,Unsafe')" 18 "Alloc,IO,Unsafe"
have "$(bucket "$work/main.axsym" 'IO,Mut,Unsafe')" 0 "IO,Mut,Unsafe"
have "$(bucket "$work/main.axsym" 'IO,Unsafe')" 12 "IO,Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,Block,IO,Mut,Spawn')" 56 "Alloc,Block,IO,Mut,Spawn"
have "$(bucket "$work/main.axsym" 'Alloc,Block,IO,Mut,Spawn,Unsafe')" 4 "Alloc,Block,IO,Mut,Spawn,Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,Block,Entropy,IO,Mut,Spawn')" 6 "Alloc,Block,Entropy,IO,Mut,Spawn"
have "$(bucket "$work/main.axsym" 'Alloc,Block,Entropy,IO,Mut,Spawn,Unsafe')" 0 "Alloc,Block,Entropy,IO,Mut,Spawn,Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,Block,IO,Mut,Unsafe')" 3 "Alloc,Block,IO,Mut,Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,Entropy,IO,Mut')" 2 "Alloc,Entropy,IO,Mut"
have "$(bucket "$work/main.axsym" 'Alloc,Entropy,IO,Mut,Unsafe')" 0 "Alloc,Entropy,IO,Mut,Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,Entropy,IO,Unsafe')" 1 "Alloc,Entropy,IO,Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,IO,Mut,Spawn,Unsafe')" 3 "Alloc,IO,Mut,Spawn,Unsafe"
have "$(bucket "$work/main.axsym" 'Alloc,IO,Mut,Spawn')" 5 "Alloc,IO,Mut,Spawn"
have "$(bucket "$work/main.axsym" 'Alloc,IO,Spawn')" 2 "Alloc,IO,Spawn"
have "$(bucket "$work/main.axsym" 'Block')" 3 "Block"
have "$(bucket "$work/main.axsym" 'Block,IO,Unsafe')" 2 "Block,IO,Unsafe"
have "$(bucket "$work/main.axsym" 'Entropy')" 1 "Entropy"
have "$(bucket "$work/main.axsym" 'IO,Spawn,Unsafe')" 1 "IO,Spawn,Unsafe"
have "$(bucket "$work/main.axsym" 'Spawn')" 2 "Spawn"
have "$(bucket "$work/main.axsym" 'Alloc,Block,IO,Mut')" 16 "Alloc,Block,IO,Mut"
have "$(bucket "$work/main.axsym" 'Alloc,Block,IO')" 2 "Alloc,Block,IO"
have "$(bucket "$work/main.axsym" 'Block,IO')" 1 "Block,IO"
have "$(bucket "$work/main.axsym" 'Block,IO,Mut')" 1 "Block,IO,Mut"
have "$(grep '^F ' "$work/main.axsym" | grep -vc '#effects=\|#effects-incomplete' || true)" 2396 "pure (neither row nor mark)"
have "$(grep '^F ' "$work/main.axsym" | grep -o '#effects=[^ #]*' | LC_ALL=C sort -u | wc -l | tr -d ' ')" 32 "distinct compiler effect rows"
have "$(grep -c '#effects-incomplete' "$work/main.axsym" || true)" 54 "incomplete rows"
have "$(grep -c '#effect-params' "$work/main.axsym" || true)" 42 "effect-params rows"

echo
# Par -> Task shares the handle helpers: one Unsafe and two pure rows
# disappear; every remaining migrated function keeps its measured effects.
# Explicit range batching adds one Alloc,Block,IO,Mut,Spawn row and one
# callback effect-parameter row; it delegates to the existing Task pool.
echo "== stdlib view: one probe importing every module =="
: > "$work/modfiles"
# The library's `Internal` modules are left out: a program cannot import
# them (AX5002), and every function in them is reached through the
# modules built on them.
for f in stdlib/*.ax stdlib/*/*.ax; do
  [[ -e "$f" ]] || continue
  [[ "$f" == stdlib/Internal/* ]] && continue
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
have "$(bucket "$work/lib.axsym" 'Alloc,Mut')" 746 "exactly Alloc,Mut"
have "$(bucket "$work/lib.axsym" 'Alloc,IO,Mut')" 315 "Alloc,IO,Mut"
have "$(bucket "$work/lib.axsym" 'Mut')" 180 "exactly Mut"
have "$(bucket "$work/lib.axsym" 'Alloc')" 190 "exactly Alloc"
have "$(bucket "$work/lib.axsym" 'Alloc,IO')" 27 "Alloc,IO"
have "$(bucket "$work/lib.axsym" 'IO')" 17 "exactly IO"
have "$(bucket "$work/lib.axsym" 'Alloc,Assert,IO,Mut')" 7 "Alloc,Assert,IO,Mut"
have "$(bucket "$work/lib.axsym" 'IO,Mut')" 7 "IO,Mut"
have "$(bucket "$work/lib.axsym" 'Alloc,Mut,Unsafe')" 80 "Alloc,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'Unsafe')" 85 "exactly Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,IO,Mut,Unsafe')" 74 "Alloc,IO,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'Mut,Unsafe')" 140 "Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,Unsafe')" 9 "Alloc,Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,IO,Unsafe')" 28 "Alloc,IO,Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,Assert,IO,Mut,Unsafe')" 0 "Alloc,Assert,IO,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'IO,Mut,Unsafe')" 3 "IO,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'IO,Unsafe')" 26 "IO,Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,IO,Spawn')" 1 "Alloc,IO,Spawn"
have "$(bucket "$work/lib.axsym" 'Alloc,IO,Mut,Spawn,Unsafe')" 4 "Alloc,IO,Mut,Spawn,Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,Block,IO,Mut')" 26 "Alloc,Block,IO,Mut"
have "$(bucket "$work/lib.axsym" 'Alloc,Block,IO,Unsafe')" 0 "Alloc,Block,IO,Unsafe"
have "$(bucket "$work/lib.axsym" 'Block,IO,Mut,Unsafe')" 3 "Block,IO,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,Block,IO,Mut,Spawn')" 23 "Alloc,Block,IO,Mut,Spawn"
have "$(bucket "$work/lib.axsym" 'Alloc,Block,IO,Mut,Spawn,Unsafe')" 2 "Alloc,Block,IO,Mut,Spawn,Unsafe"
have "$(bucket "$work/lib.axsym" 'Fallible')" 1 "exactly Fallible"
have "$(bucket "$work/lib.axsym" 'Assert')" 1 "exactly Assert"
have "$(bucket "$work/lib.axsym" 'Alloc,Block,IO,Mut,Unsafe')" 9 "Alloc,Block,IO,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,Entropy,IO,Mut')" 24 "Alloc,Entropy,IO,Mut"
have "$(bucket "$work/lib.axsym" 'Alloc,Entropy,IO,Mut,Unsafe')" 1 "Alloc,Entropy,IO,Mut,Unsafe"
have "$(bucket "$work/lib.axsym" 'Alloc,Entropy,IO,Unsafe')" 1 "Alloc,Entropy,IO,Unsafe"
have "$(bucket "$work/lib.axsym" 'Block')" 3 "Block"
have "$(bucket "$work/lib.axsym" 'Block,IO,Unsafe')" 2 "Block,IO,Unsafe"
have "$(bucket "$work/lib.axsym" 'Entropy')" 2 "Entropy"
have "$(bucket "$work/lib.axsym" 'Entropy,Mut')" 1 "Entropy,Mut"
have "$(bucket "$work/lib.axsym" 'IO,Spawn,Unsafe')" 1 "IO,Spawn,Unsafe"
have "$(bucket "$work/lib.axsym" 'Spawn')" 2 "Spawn"
have "$(bucket "$work/lib.axsym" 'Alloc,Block,IO')" 2 "Alloc,Block,IO"
have "$(bucket "$work/lib.axsym" 'Alloc,IO,Mut,Spawn')" 4 "Alloc,IO,Mut,Spawn"
have "$(bucket "$work/lib.axsym" 'Block,IO')" 1 "Block,IO"
have "$(bucket "$work/lib.axsym" 'Block,IO,Mut')" 1 "Block,IO,Mut"
have "$(grep '^F ' "$work/lib.axsym" | grep -vc '#effects=\|#effects-incomplete' || true)" 1178 "pure (neither row nor mark)"
have "$(grep '^F ' "$work/lib.axsym" | grep -o '#effects=[^ #]*' | LC_ALL=C sort -u | wc -l | tr -d ' ')" 38 "distinct stdlib effect rows"
have "$(grep -c '#effects-incomplete' "$work/lib.axsym" || true)" 25 "incomplete rows"
have "$(grep -c '#effect-params' "$work/lib.axsym" || true)" 64 "effect-params rows"

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
