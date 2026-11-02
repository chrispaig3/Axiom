#!/usr/bin/env bash
# THE CAST-AT-ARGUMENT-ROOT GATE (docs/memory-model.md MM-VAL-22/23,
# QA P0 §3 F7/F19).
#
# A type-preserving cast keeps the operand's ownership and evidence.
# Its temporary must have the same release as the uncast spelling.
# A scalar control must still have no release: evidence 0 never
# licenses an unconditional retain or release. Reinterpretations
# keep MM-VAL-22's conservative evidence and unsafe obligations.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

gate_build_axc axc

echo "--- 1. user-level cast count does not grow ---"
# core/ is excluded: (cast Int ...) there is compiler plumbing
# for untyped words, not the user-level laundering MM-VAL-22 names.
# Baseline 385 measured 2026-09-29: five arrived with the typed handles.
# `tests/stdlib/572-spawn-joined-twice.ax` (two) spells a forged handle
# and one handle's word as another kind, which only a cast can write
# because the types are sealed, and
# `tests/litmus/sync-load.ax` (one) reads a mutex's page through the
# unsafe layer to build the stale-guard window. The forging casts are
# the fixtures' subject: the MM-VAL-23 reason.
# Baseline 380 measured 2026-09-28 (379 before the merge with 1006):
# eight arrived with the
# reclamation audit. `tests/stdlib/557-cycle-backlog.ax` seeds its
# knots with `(cast Node 0)`, MM-LIFE-3's own spelling of a cycle a
# program can build, and `556-count-balance.ax`'s control releases a
# string's handle by hand through `(cast Int s)`: in both the cast is
# the subject under test, the MM-VAL-23 reason.
# Baseline 439 measured 2026-09-29 at the assurance session's merges: six
# arrived. Two read a string's count word through its address,
# `(cast Int s)` in `tests/stdlib/630-parallel-borrow.ax` and
# `tests/litmus/borrow-load.ax`, whose subject is that no binding's
# retain or release reached the count (MM-PAR-6b): the MM-VAL-23 reason.
# Four are a `Float` carried as its bits and back, `(cast Int x)` and
# `(cast Float w)` in `tests/stdlib/620-par-float-order.ax` and
# `tests/litmus/par-determinism.ax`: a join carries one word, so a float
# answer crosses as its bits, which is what MM-PAR-14 tells a program to
# send when it compares answers bit for bit.
# Baseline 451 measured 2026-10-02: twelve arrived in four commits,
# each read against MM-VAL-22/23 rather than bulk-accepted. Six are
# `orDie`'s Err arm in `tests/crypto/310/311/312/320/322/323`,
# `(cast a (die ...))` at return position: `die` exits first, so the
# cast never converts a word and only types the unreachable arm. Two
# are `stdlib/Float.ax`'s `floatToBits`/`floatFromBits`, return
# position in `(-> Float Int)`/`(-> Int Float)` - the same shape as
# the float-bits pair the 439 baseline names. Three are AXQLite's:
# `connPager` casts the mapping's word back to `Pager` at a return
# under `effect(unsafe)`;
# `(cast Int pager)` is the store half of that round-trip, a
# reference decaying to a word rather than a word forged into one;
# `(cast Byte c)` narrows an `Int` for `strFromByte`, scalar to
# scalar, so no reference is forged and no release is suppressed.
# The last net one is the `alloc`-removed refusal fixture, `(cast Int
# (alloc P))` plus its golden's quote of it, minus the two alloc-user
# casts the removal deleted; the fixture is refused AX2004, so its
# cast never compiles.
# Baseline 433 measured 2026-09-29 at the Track C merge: seven arrived.
# Three are `stdlib/Task.ax`'s spawn handle carried
# through the recovery point around a spawn, which answers a word, so
# each pool turns the handle into its word and back (`taskWordOf`,
# `taskHandleOf`); each module states that as its one such cast. Three
# were forged guards in `tests/litmus/sync-load.ax`,
# `tests/stdlib/541-sync-mutex.ax` and a deleted handle fixture, whose
# subject was a guard nothing earned being refused: the MM-VAL-23 reason.
# Baseline 426 measured 2026-09-29 at the R-B10 merge: eight arrived on
# trunk after 418 was set, and trunk carried the red. Three are
# `tests/litmus/handle-bitflip.ax`'s fault injection, which flips one
# bit of a sealed channel handle's word (only a cast can write that)
# and types its unreachable failure arm; two are
# `tests/selfhost/1011-cast-arrow-alias.ax`, whose subject is a cast to
# an arrow alias (AN-53), in its header and its body; and one each in
# `tests/stdlib/590-chan-dead-holder.ax` and `tests/litmus/chan-dead.ax`,
# which open a channel's ring through the handle table to watch the lock
# a dead holder left (AN-10). Each cast is the fixture's subject or its
# harness: the MM-VAL-23 reason.
# Baseline 418 measured 2026-09-29, the unsafe boundary merged onto the
# typed handles: 385 on trunk and 406 on the boundary's branch, from a
# base of 372.
# Baseline 406 measured for R-B6: `tests/diagnostics/1040`, `1042`
# and `tests/selfhost/1010` name 19 casts to pin exactly where a
# forged reference needs an unsafe declaration, and the renderer
# goldens quote the lines they flag; the typed split answers
# (`strSplit`, `listDir`, `sysReadDir`) removed 9.
# Baseline 372 measured 2026-09-28: one arrived with
# `tests/selfhost/1006-cast-type-operand.ax`, whose header quotes
# `Vec.ax`'s `(cast a (memGetWord ...))`: the fixture is about that
# cast's TYPE operand being walked as a reference, which cannot be
# said without writing the cast - the MM-VAL-23 reason.
# Baseline 371 measured 2026-09-28: six arrived with
# `1024-type-part-not-a-type`, whose three goldens echo AX3002's help,
# "`(cast Int e)`", once per refusal. The fixture pins what a cast's
# type may not be, which cannot be said without the help naming a cast:
# the MM-VAL-23 reason.
# Baseline 365 measured 2026-09-27: 25 arrived with the fuzzer's cast
# findings - `1013-cast-form-value` (2 in the `.ax`, echoed in its three
# goldens) and `1019-cast-missing-operand` (5 in the `.axbad`, echoed in
# its three goldens) pin refusals of `(cast T)`, which cannot be pinned
# without writing `(cast T)`, plus one in the `explain` golden's AX3013
# prose. The casts ARE the subjects, which is the MM-VAL-23 reason.
# Baseline 340 measured 2026-09-27 (337 on 2026-09-25): three arrived
# with tests/stdlib/521-release-filed.ax (`a28d7a02`), which hands a
# static literal's handle to `__retain` once and `__release` twice to
# show the -1 sentinel survives an imbalance (MM-LIFE-2k) - the cast IS
# the raw word under test, which is the MM-VAL-23 reason. CI never
# reached this gate the day they landed: every Tests leg stopped at an
# earlier red step. 337 was measured 2026-09-25 (was 329 on 2026-09-21): five
# arrived with the 1008-error-payload-untyped fixture (`02edb8ae` -
# three in the probe source, two echoed in its `.human` golden - the
# casts ARE the payloads the diagnostic is about) and three with the
# LSP type-hierarchy fixtures (a `(cast Positive 5)` conversion the
# hierarchy requests navigate, plus the two assertion strings that
# pin its spelling). All eight are test subjects that probe the
# boundary casts exist for, which is the MM-VAL-23 reason. The
# ratchet is <=, so removing casts always passes and adding one must
# update this number with a reason.
#
# COUNTED WITH `git grep`, AND A ZERO IS A FAILURE. This read `rg ...
# 2>/dev/null | wc -l`, and the CI runners have no `rg`: the error went
# to /dev/null, `wc` counted nothing, and every CI run printed "cast
# count 0 <= 337" - a ratchet that could not fail anywhere it gated
# (found 2026-09-27, when the local count was 340 and CI's was 0).
# `git grep` exists wherever the repository does and reads exactly the
# tracked files, so a stray local file cannot move the number either.
#
# `tests/fuzz/` is NOT counted, and that is a narrowing with a reason
# rather than a convenience: its `.axfuzz` files are minimized fuzzer
# reproducers - deliberately ill-formed programs no build reads - and
# `MANIFEST` is prose describing them. `878b17be` recorded
# `cast-missing-operand.axfuzz`, whose whole subject is `(cast T)` with
# its operand missing, and moved this count to 342 while CI stopped at
# an earlier red; counted, every future fuzzer finding about `cast`
# would be a ratchet failure over a file that is not user code.
# The incoming trunk census is 465. The seven additional casts in
# 701-cast-ownership.ax are the regression's subject: temporary,
# binding, discard, polymorphic store, borrowed alias and nested casts.
# Two more are regression subjects: 330-obfuscate's generic Err arm
# follows `die`, so its cast never executes; 1014 reads a live string's
# count header to verify the returned capture takes a share. Both are
# MM-VAL-23 evidence, with no new reference forged in application code.
# One more is `tests/parallel/immutable-borrow.ax`'s `countOf`, which
# reads a value's count word to show a scoped immutable borrow takes
# no share: the MM-VAL-23 reason.
# Baseline 476 measured 2026-10-14: four arrived and two left. The four
# are `tests/diagnostics/1260-spawn-forging-cast.human`, the rendering
# of a fixture whose forged `(cast Spawn w)` handles are its subject;
# a human golden quotes the source lines it points at. The two left
# with `vecFree`'s fixtures (48b43283).
# Baseline 939 follows the explicit numeric-conversion and fixed-width
# migrations. The census counts occurrences (`git grep -o`), including
# test subjects, comments and diagnostic renderings; moving a nested
# conversion to another line does not change it. The 939 are 75 in the
# stdlib, 862 in tests and two unchanged example conversions.
# New application conversions in AxqlEval and AxqlExec are numeric:
# Int/Float comparisons, sums and averages now state their conversions.
# Float's numeric helpers do likewise; its output-buffer word exposes
# the header for a length write, rather than forging a reference.
# Axqlite keeps its handle-word inspection for the runtime-liveness check.
# Most new test occurrences pin precise integer boundaries and packed
# fields (959, 948, 1431 and 949), explicit numeric conversion, generic
# invariance and aliasing. The remaining additions are diagnostic/help
# mirrors, formatter/LSP source payloads and memory-layout/ownership
# probes, including 964-967; the casts are their MM-VAL-23 subjects.
# Baseline 950 adds eleven test occurrences to 939. Nine are in
# semantic-token-updates.py: five scalar numeric/alias conversions and
# four source, role and revision mirrors of them. Two are in
# tests/mir/110-cast.ax: its integer-ascription comment and the explicit
# Int-to-Float conversion that pins the floating-arithmetic refusal.
# These are MM-VAL-23 test subjects; no application reference is forged.
# Baseline 972 adds twenty-two scalar conversion occurrences: seven in
# the precise-numeric REPL transcript, fourteen in its compiled and
# REPL cross-checks, and one oracle refusal control in local-models.py.
# The compiler and library add no reference erasure for these tests.
# Baseline 982 adds the two Vec fast-path storage conversions, which
# mirror the retained element and vector-header operations in the slow
# path. Six occurrences are the parallel frontend fixtures' unit-handle
# and nullable-name boundaries; two are the nested numeric conversions
# in the stored-lambda deep-cast diagnostic fixture.
# Baseline 983 adds the Float-to-Int conversion of the mutable field
# in 396-macro-struct-field-types.ax. It checks the generated field's
# numeric type under MM-VAL-23; it creates no reference or ownership.
# Baseline 1041 adds fifty-nine occurrences. The raw memory layer is internal
# to the library (MM-EXEC-9g), so the tests that store a reference into
# a raw block, or read one back, carry their own trusted helpers copied
# from the classic layer, each with the one conversion the library's
# had: `(as value Int)` in a word store, `(as (vecGet v i) String)` in a
# slot read, `(as s String)` where a header is built. They are MM-VAL-23
# test subjects over blocks the test allocates itself. The library adds
# no conversion, the compiler's own copy is not counted, and the one
# example conversion narrows an `Int` to a `Byte`.
# Baseline 1042 adds one: `tests/selfhost/290-emit.ax` spells the one
# compilation unit it builds as the word the units vector holds, as
# `300-pipeline.ax` does, to drive the compiler's own passes, whose
# words `core/` is excluded for. It creates no reference or
# ownership.
# Baseline 1048 adds six reviewed conversions. The two checked-program
# selfhost fixtures pass CUnit2 handles through the compiler pipeline's
# word vector, as the 1042 baseline's emit fixture does. The nested
# recovery fixture reads a live string's count header twice to prove the
# inner recovery preserved its owner. IO's two marker conversions pass
# live marker handles to the library-only Windows liveness layer; they
# decay references to words without forging a reference or changing its
# share. These are compiler-boundary or MM-VAL-23 ownership probes.
# Baseline 1073 adds 25 reviewed conversions: four private process/transport
# handles cross typed runtime word boundaries, one owned Windows command
# slot is passed as a word, and the command-scratch mock restores its live
# vector type. CheckedNested passes a CUnit2 through the compiler word
# vector. The other eighteen are numeric Int/Float conversions in the
# checked-function-type tests, including their emitted source strings.
# The handle conversions use live owners and change no share; the numeric
# conversions create no reference (MM-VAL-23).
# Baseline 1214 adds 141 reviewed ownership-probe occurrences: 48 in
# emitter-line-buffer.axp/.py, 4 in emitter-pending-strings.axp/.py, 53 in
# emitter-string-slots.axp/.py, 28 in emitter-symbol-scope.ax and 8 in
# checked-snapshot-capacity.axp/.py. Of these, 102 inspect live reference
# counts, 9 compare live identities, 3 are typed-return String readers,
# 8 read the compiler's legacy raw results, 2 call raw setter bridges,
# 2 restore their live String argument, 1 reads a popped slot, and 8
# construct sole-share test descriptors. The last 6 are private failing
# ablations or their source anchors. Every conversion is the ownership
# behaviour under test (MM-VAL-23); stdlib and examples add none.
# Baseline 1225 adds eleven line-metadata probe occurrences: one reads a
# live source-index reference count, four exercise typed indexes through
# the legacy raw readers, two mirror those readers in a source anchor,
# and four form the private raw-storage ablation. The owner stays live
# during every read; the ablation's two erasures are its tested defect
# (MM-VAL-23). Production compiler conversions fall by eleven.
# Baseline 1235 adds ten source forms in effect-totality.py's oracle
# tests. They prove local Unsafe forging casts and reject scalar,
# nonparameter, block, quoted, custom-owner, selective-import and duplicate
# counterexamples. The conversions are the effect-classification subjects
# (MM-VAL-23); production and example counts are unchanged.
# Baseline 1245 adds ten reviewed binder-summary occurrences: two Unsafe
# count-zero allocation factories and one legacy raw owner-result wrapper
# in Intern; two live String count readbacks in the probe; one nullable
# legacy pattern oracle, two source anchors and two intentional failing
# erasure/restoration casts in its runner. The production factories use
# ordinary counted results and retain the raw API's one-share obligation.
# The remaining conversions are MM-VAL-23 ownership test subjects.
# Baseline 1246 adds the pruning probe's Unsafe live String-count
# readback. Its borrowed String remains alive through the observation;
# production conversions are unchanged (MM-VAL-23).
# Baseline 1247 adds the pruning probe's Unsafe live Vec-header count
# readback. It observes the retained line-vector share while its owner
# remains alive; production conversions are unchanged (MM-VAL-23).
# Baseline 1248 combines three emitted-symbol oracle conversions with
# the argument-ledger tests' net removal of two forms: six raw reads
# become typed, while one live-count read and three ablation/adaptor
# forms exercise the old raw ledger. These are MM-VAL-23 test subjects.
# Baseline 1256 adds one live String-count observation and seven raw
# operand-table restorations in the MIR ownership control. The controls
# reproduce the text leak; production removes four reference erasures
# and the user-level conversions are MM-VAL-23 test subjects.
# Baseline 1259 adds the checker refusals' fixtures. AX3139's subject is
# a cast through unit: `tests/diagnostics/1492-as-unit.ax` writes two,
# its `.human` golden and tests/tools/explain.golden quote them, and its
# `(as x Int)` is the control between informative types. AX3140's
# `tests/diagnostics/1493-certain-trap.ax` reads a `Percent` back as
# `Int`, the subtype's own control. All are MM-VAL-23 test subjects.
# The typed-CG replacement-share probe reads a held vector's header count
# through one private erasure in emitter-line-buffer.py's probeCount.
# Its subject is the reference count itself, which a safe view cannot read:
# the MM-VAL-23 reason for this one additional test-only cast.
# Typed compiler probes add ten occurrences: the effect-registry bridge
# passes its live module-name owner across the remaining CG word boundary.
# Nine numeric conversions exercise UInt8 format radix payloads and their
# invalid-value controls, including emitted source. None forges a reference;
# these are MM-VAL-23 compiler-boundary and numeric-conversion subjects.
# Owning CG parameters make 110 existing raw ownership observations explicit:
# 107 context-to-word bases, two returned-context identity observations and
# one held Names-vector truncation control. These test-only MM-VAL-23
# subjects inspect field headers/counts without adding a typed getter share;
# their live typed owners remain held. Production removes 93 CG bridges.
# Checker migration probes add 26 test-only occurrences: 12 live owner/header
# observations and child-map ablations, and 14 diagnostic/numeric cast subjects
# in generated source. These MM-VAL-23 controls hold their live owners; the
# diagnostic subjects exercise refusal, rather than manufacturing safe owners.
# The next checker probes add 14 test-only MM-VAL-23 subjects: two evidence
# owner/map observations, three unsafe-forge diagnostic subjects, one invalid
# declared-type conversion, five numeric conversions and three unit owner/map
# or LSP wire-boundary observations. Their live owners stay held. Three old
# forged-null unit names disappear, leaving a net census increase of eleven.
# Match-arm ownership controls add four MM-VAL-23 test subjects: one live
# header count, two deliberate erased-row conversions and one child-map
# ablation. The erased conversions exist only in unsafe negative controls.
# Codegen owner controls add seven MM-VAL-23 test subjects: three live
# header observations, three child-map ablations and one raw slot-truncation
# ablation. Three retired erased module/lambda reads leave a net four.
# Cast-source recovery tests add fourteen textual MM-VAL-23 subjects:
# one valid arrow conversion, four diagnostic input conversions (including
# one refused forgery), and nine exact help/fix strings. None adds a
# production erasure or grants an exemption for reference forging.
# Token and symbol-map controls add four MM-VAL-23 subjects: two live
# header observations, one live-vector nullness observation, and a
# child-map ablation of a copied Option. No production erasure is added.
# Parser, macro, flow and compact-index probes add eight MM-VAL-23
# subjects: five live header observations, two child-map ablations and one
# deliberate vector truncation ablation. Their live typed owners stay held;
# the unsafe mutations are effective negative controls only.
# Typed annotation, parser, emitter and interner probes add eleven subjects:
# six live header observations, one live AST reference-map observation,
# one payload nullness observation and three effective ownership ablations.
# Live observations keep their typed owner in scope.
# Emitter, editor, diagnostic and typed-tag probes add seven subjects:
# six live header observations and one effective Box reference-map ablation.
# Each header observation keeps its live typed owner in scope.
# The strict optional Try-state fixture adds one live-owner reference-count
# observation; its typed owner remains in scope during the header read.
# In-place vector growth adds seven subjects. `vecReserveExactly` writes
# the capacity word of the live vector through `(as v Int)`, the same
# header store `vecPop` and `vecClear` already use for the length, and
# the vector stays the typed owner. `tests/stdlib/1002-vec-in-place-growth.ax`
# reads that header and a child's count, and retains a live handle twice.
# `tests/stdlib/1003-named-vector-return.ax` reads the returned element's
# count word while its owner is still in scope.
# The canonical-module negative control restores the old Option-to-word
# pointer test in its generated mutant; that erased spelling is the defect
# the test rejects, and is never used in the positive implementation.
# Four new Option-owner fixtures read a live value's reference count.
# Each unsafe observation keeps its typed owner live through the read.
# Source-index, String-name and lambda probes add eight subjects: five
# live-owner/count or value observations, two erased-table ablation casts,
# and one refused source-forging cast. Eight obsolete metadata-probe casts
# leave, so the exact tracked user-level census remains 1482.
# Four lookup/predicate fixtures read live owners' reference counts to
# check retirement. These MM-VAL-23 observations keep their typed owner
# alive; no application conversion or production erasure is introduced.
# Assembler, CLI, formatter and LSP shape probes add four live-owner
# reference-count observations under MM-VAL-23. The formatter golden carries
# two existing syntax-zoo spellings: a numeric conversion and the unsafe
# `(as 0 (Box Int))` syntax subject. They are unexecuted formatter golden
# text, adding no production conversion or permission to forge references.
# The erasure-claim support harness adds three cast subjects: a reference
# erasure, a numeric identity and a reference identity. They test AX3010
# claim support under MM-VAL-23; no production cast is added.
cast_count="$(git -C "$repo_root" grep -h -o '(as ' -- stdlib tests examples ':!tests/fuzz' | wc -l | tr -d ' ')"
# Optional context/query and propagation probes add five live-owner header
# observations under MM-VAL-23. The exact documentation-render golden adds
# 22 textual `(as ` examples from unchanged builtin documentation: eleven
# each in the successful and missing-library snapshots. They add no executed
# conversion or production erasure; the census includes golden text.
# Tool-path and formatter-declaration fixtures add two live-owner header
# observations under MM-VAL-23. They keep the owner alive throughout each
# count read; no production reference conversion is added.
# Formatter atom, LSP result and emitter arity fixtures add four live-owner
# reference-count observations under MM-VAL-23. No production conversion
# or reference forging is added.
# Alloca-marker, formatter-flat and REPL history Option fixtures add seven
# live-owner header observations under MM-VAL-23. The retired line-buffer
# fixture removes five; production and standard-library casts add none.
# The erasure refusal adds 16 cast subjects in 1510, three LSP subjects,
# and 40 diagnostic-golden quotations. Four obsolete forging/intern casts
# and one nested-vector null test leave; explain adds two quotations.
# Relative to the measured 1523 at 220aa40c this is 1579. Under MM-VAL-23,
# the new executable casts test the refusal itself; the remaining additions
# are diagnostic text. No production erasure is added.
# The prune-owner identity check uses addrOf, removing two further casts
# and bringing the pinned census to 1577.
# Typed interner ownership probes add four live-owner observations and
# intentional unmatched-retain controls under MM-VAL-23. The tracked
# census is 1581. The directory-boundary probe adds one refusal subject,
# bringing it to 1582. Closure capacity and match-capture probes add six
# casts: two typed subtype boundary cases and four live-owner/header
# observations under MM-VAL-23. The census is 1588; production is unchanged.
if [ "$cast_count" -eq 0 ]; then
  bad "user-level: the cast count read 0 - the measurement is broken, not the tree clean"
elif [ "$cast_count" -le 1588 ]; then
  ok "user-level (cast count $cast_count <= 1588)"
else
  bad "user-level (cast count $cast_count > 1588): new casts need a MM-VAL-23 reason and a baseline bump"
fi

echo "--- 2. type-preserving casts keep ownership ---"
cat > "$work/cast3.ax" <<'EOF'
(import Mem)
(import Str)
(:: main ())
(fn (main)
  { (let p (memAlloc 8))
    {
      (memSetWord p 0 (strDup "hi"))
    }})

; This program reaches raw memory through its own trusted helpers over
; the primitives, as any program outside the standard library does.
(:: memAlloc (-> Int Int))
;@axiom:effect(unsafe)
(fn (memAlloc bytes)
  (__alloc bytes))

(:: memSetWord (-> Int Int a Int))
;@axiom:effect(unsafe)
(fn (memSetWord addr index value)
  {
    (__retainref value)
    (__store64 addr index (as value Int))
    addr
  })
EOF
cat > "$work/cast4.ax" <<'EOF'
(import Mem)
(import Str)
(:: main ())
(fn (main)
  { (let p (memAlloc 8))
    {
      (memSetWord p 0 (as (strDup "hi") String))
    }})

; This program reaches raw memory through its own trusted helpers over
; the primitives, as any program outside the standard library does.
(:: memAlloc (-> Int Int))
;@axiom:effect(unsafe)
(fn (memAlloc bytes)
  (__alloc bytes))

(:: memSetWord (-> Int Int a Int))
;@axiom:effect(unsafe)
(fn (memSetWord addr index value)
  {
    (__retainref value)
    (__store64 addr index (as value Int))
    addr
  })
EOF
if "$axc" --diagnostic-format=ai check "$work/cast3.ax" >/dev/null 2>&1 \
  && "$axc" --diagnostic-format=ai check "$work/cast4.ax" >/dev/null 2>&1; then
  ok "both probes check OK (no new refusal)"
else
  bad "a probe no longer checks: run $axc check on cast3/cast4 by hand"
fi
"$axc" --diagnostic-format=ai emit-llvm "$work/cast3.ax" -o "$work/cast3.ll" >/dev/null 2>&1
"$axc" --diagnostic-format=ai emit-llvm "$work/cast4.ax" -o "$work/cast4.ll" >/dev/null 2>&1
# `grep -c`, not `rg -c`: the Linux image carries no ripgrep and a
# missing counter reads as 0 == 0 - the fixed defect - on exactly
# the leg that never saw the tool. (Measured 2026-09-19.)
if [[ ! -f "$work/cast3.ll" || ! -f "$work/cast4.ll" ]]; then
  bad "emit-llvm produced no IR for the probes; counting releases would compare nothing"
else
  # Count the exact callee: the runtime's axiom_release_full forwarding
  # call belongs to neither program's ownership behaviour.
  rel3="$(grep -c 'call void @axiom_release(' "$work/cast3.ll" || true)"
  rel4="$(grep -c 'call void @axiom_release(' "$work/cast4.ll" || true)"
  rel3="${rel3:-0}"
  rel4="${rel4:-0}"
  if [[ "$rel3" -gt 0 && "$rel4" -eq "$rel3" ]]; then
    ok "type-preserving cast retains the temporary's release ($rel3 == $rel4)"
  else
    bad "type-preserving cast changed ownership ($rel3 -> $rel4), or both probes emitted no release"
  fi
fi

cat > "$work/scalar.ax" <<'EOF'
(import Mem)
(:: main ())
(fn (main)
  { (let p (memAlloc 8))
    { (memSetWord p 0 (as 7 Int)) }})

; This program reaches raw memory through its own trusted helpers over
; the primitives, as any program outside the standard library does.
(:: memAlloc (-> Int Int))
;@axiom:effect(unsafe)
(fn (memAlloc bytes)
  (__alloc bytes))

(:: memSetWord (-> Int Int a Int))
;@axiom:effect(unsafe)
(fn (memSetWord addr index value)
  {
    (__retainref value)
    (__store64 addr index (as value Int))
    addr
  })
EOF
if "$axc" --diagnostic-format=ai emit-llvm "$work/scalar.ax" -o "$work/scalar.ll" \
     > /dev/null 2> "$work/scalar.err"; then
  if grep -q 'call void @axiom_release(' "$work/scalar.ll"; then
    bad "the scalar control acquired a reference release"
  else
    ok "the scalar control still has no reference release"
  fi
else
  bad "the scalar control did not emit"
  head -8 "$work/scalar.err"
fi

echo "--- 3. AX3040 rule still pinned ---"
if "$axc" explain AX3040 >/dev/null 2>&1; then
  ok "explain AX3040 answers"
else
  bad "explain AX3040 stopped answering"
fi
if [ -f "tests/diagnostics/460-signature-type-variable.ax" ]; then
  ok "tests/diagnostics/460-signature-type-variable.ax exists"
else
  bad "460-signature-type-variable.ax missing: AX3040 accept/reject shape unpinned"
fi

echo "--- 4. the compiler's erasures do not grow ---"
# An ERASURE is a cast that turns a reference into a word: its operand
# is a `String`, `Vec`, `Handle`, struct, `data` type with a field,
# closure, tuple or a signature's type variable, and its target is a
# word nothing dereferences (`Int`, `Foreign`, an alias of either, a
# number). The block's share is never given back and nothing
# downstream can say what the word was (MM-VAL-24). `symbols` prints
# `#erasures=n` on each function whose body has n of them, judged by
# the operand's TYPE once the body is typed (`eraseSettle` in
# `core/typecheck.ax`), so `(cast Int c)` of a `Char` is not one,
# and `(cast Foreign s)` or `(cast Word p)` through an alias is.
#
# The compiler's own total is the work of retiring `Int` as its heap
# handle, and it may only fall. The ratchet is <=; a commit that adds
# an erasure to `core/` must lower another or update this number
# with its reason.
#
# Baseline 836 measured 2026-10-06: 804 on trunk `fc7ef7c0`, plus the
# 31 results that returned a record through a declared `Int` and now
# write `(cast Int ...)` because the implicit coercion is gone, plus
# one in `tcWalkDecls` opening the erasure-site list itself.
# Baseline 845 follows the reviewed compiler changes: fourteen added
# sites and five removed. Seven added sites inspect existing nullable
# handles: ctor field types, match binders, four module-name checks and
# a function-index bucket. Seven cross existing word-based metadata
# boundaries: four empty formatter comment queues, ComputeRequest and
# ComputeWalk records, and the generic struct evidence variable list.
# resolveDeclsPhase removed two sites; fpLambda, fpPat and fpPatVecAt
# removed one each. The total therefore rises by nine without adding
# an implicit conversion or widening the kinds the counter recognises.
# Typed command argument vectors remove 84 reference erasures from the
# 873-site tree measured before this migration. The resulting 789 sites
# tighten the prior 845-site pin; no compiler erasure is exempted.
# Scoped binder summaries remove two more sites from binderSummary and
# binderCollectArms in a same-compiler source comparison.
# Typed argument-register storage removes emitArgsRegs' String-to-word
# insertion. Its two typed readbacks also remove the old Unsafe forgeries.
# A same-compiler comparison removes mirParamOps' one text erasure and
# mirEmitInsts' three; the typed operand table introduces none.
# Typed records and string vectors in the driver, REPL, highlighter,
# history, completion, AXIR and nolint modules leave 666; the LSP's
# typed navigation, highlight and lint records leave 646. Typed scopes,
# constructor/signature tables and namespace owners remove another 91
# reference erasures, leaving 555.
# Typed contexts, function entries, expansion owners and renderer rows
# remove 58 more reference erasures in a same-compiler comparison.
# Typed checker definition/module tables and graph searches remove
# 34 further reference erasures in a same-compiler comparison.
# Owning TC/body/region records and optional semantic results remove 43
# measured reference erasures (462 to 419 with one compiler), tightening
# the previous 463 ceiling without exempting a production site.
# Typed unit identities and checker optional witnesses remove seven more
# reference erasures: 419 to 412 with the same compiler on both trees.
# Optional parameter-type queries remove one further reference erasure
# in a same-compiler comparison: 412 to 411.
# Owning codegen contexts, indexes and auxiliary state remove fourteen
# reference erasures: 411 to 397 under the same compiler.
# Optional expansion results and owning generated-origin rows remove
# fifty-one further reference erasures: 397 to 346 under one compiler.
# Owning Token streams and optional symbol/AXIR lookups remove six
# further reference erasures: 346 to 340 under one compiler.
# Owning parser results, macro products and flow bindings remove 25
# further reference erasures: 340 to 315 under one compiler.
# Owning annotations, interner state and typed optional metadata remove
# 21 further reference erasures: 315 to 294 under one compiler.
# Typed emitter, editor and diagnostic optional owners remove nine
# further reference erasures: 294 to 285 under one compiler.
# Compared with 4ee86a21, canonical identity and typed diagnostic,
# signature and editor queries measure 281 to 278 reference erasures.
# Counted source indexes and required diagnostic Strings remove eighteen
# more reference erasures: 278 to 260 under the same compiler.
# Builtin recognition and optional entry-source access remove eleven
# further reference erasures: 260 to 249 under the same compiler.
# Optional namespace modules and symbol-unit lookup remove two more
# reference erasures: 249 to 247 under the same compiler.
# Typed test-runner records and file paths remove three erasures: 243 to
# 240 with the same compiler. The previous 247 pin included four sites
# already removed or reclassified before this migration.
# Shared closure-layout selection adds two explicit nullable-vector checks.
# Both are compiler-only, declared unsafe, and counted by the same erasure rule.
# The raw JSON extraction adds no compiler erasures.
erasure_pin=242
erasure_sum() {  # <axsym> -> the #erasures= total over core/ rows
  awk '$1 == "F" && index($3, "core/") == 1 {
         for (i = 4; i <= NF; i++)
           if ($i ~ /^#erasures=[0-9]+$/) { v = $i; sub(/^#erasures=/, "", v); t += v }
       }
       END { print t + 0 }' "$1"
}
"$axc" --diagnostic-format=ai symbols core/main.ax > "$work/main.axsym" 2> "$work/main.err" || true
sh_rows="$(awk '$1 == "F" && index($3, "core/") == 1' "$work/main.axsym" | wc -l | tr -d ' ')"
if (( sh_rows < 4000 )); then
  bad "symbols listed $sh_rows compiler functions (floor 4000): the read broke"
  sed 's/^/     /' "$work/main.err" | head -4
else
  erasures="$(erasure_sum "$work/main.axsym")"
  if (( erasures == 0 )); then
    bad "the compiler's erasure count read 0 - the measurement is broken, not the tree clean"
  elif (( erasures <= erasure_pin )); then
    ok "compiler erasures $erasures <= $erasure_pin, over $sh_rows functions"
  else
    bad "compiler erasures $erasures > $erasure_pin: a new erasure needs another removed, or a reason and a new pin"
    awk '$1 == "F" && index($3, "core/") == 1 && / #erasures=/ { for (i = 4; i <= NF; i++) if ($i ~ /^#erasures=/) print "     " $2, $3, $i }' "$work/main.axsym" \
      | sort -t= -k2 -rn | head -10
  fi
fi
# Every compiler module that writes a cast must be in the closure the
# sum reads, or its erasures would never be counted.
outside=""
for f in $(git -C "$repo_root" grep -l '(as ' -- 'core/*.ax'); do
  grep -q " $f:" "$work/main.axsym" || outside="$outside $f"
done
if [[ -z "$outside" ]]; then
  ok "every core module with a cast is in core/main.ax's closure"
else
  bad "modules with casts outside the counted closure:$outside"
fi
# The count follows the operand's type, not the spelling.
cat > "$work/erase.ax" <<'EOF'
(data Box
  (Bx String))

(data Color
  (Red)
  (Green))

(type Word Int)

(:: str (-> String Int))
(fn (str s)
  (as s Int))

(:: box (-> Box Int))
(fn (box b)
  (as b Int))

(:: vec (-> (Vec Int) Int))
(fn (vec v)
  (as v Int))

(:: tv (-> a Int))
(fn (tv x)
  (as x Int))

(:: fgn (-> String Foreign))
(fn (fgn s)
  (as s Foreign))

(:: alias (-> Box Word))
(fn (alias b)
  (as b Word))

(:: two (-> String String Int))
(fn (two a b)
  (+ (as a Int) (as b Int)))

(:: chr (-> Char Int))
(fn (chr c)
  (as c Int))

(:: color (-> Color Int))
(fn (color c)
  (as c Int))

(:: num (-> Int Float))
(fn (num n)
  (__floatFromBits n ))

(:: main ())
(fn (main)
  ())
EOF
"$axc" --diagnostic-format=ai symbols "$work/erase.ax" > "$work/erase.axsym" 2> "$work/erase.err" || true
got_erase="$(awk '$1 == "F" { n = 0; for (i = 4; i <= NF; i++) if ($i ~ /^#erasures=/) { n = $i; sub(/^#erasures=/, "", n) } print $2 "=" n }' "$work/erase.axsym" \
  | grep -E '^(str|box|vec|tv|fgn|alias|two|chr|color|num|main)=' | tr '\n' ' ')"
want_erase="str=1 box=1 vec=1 tv=1 fgn=1 alias=1 two=2 chr=0 color=0 num=0 main=0 "
if [[ "$got_erase" == "$want_erase" ]]; then
  ok "erasures are counted by operand type: a reference, a type variable and an alias count; a Char, an enum and a number do not"
else
  bad "the erasure probe read: ${got_erase:-nothing}"
  echo "     wanted: $want_erase"
  sed 's/^/     /' "$work/erase.err" | head -4
fi
# The sum reads compiler rows only, and every key on them.
printf '%s\n' \
  'F a core/x.ax:1:5-6 "Int" @0000000000000001 #effects=Alloc #erasures=3' \
  'F b core/y.ax:2:5-6 "Int" @0000000000000002 #erasures=1 #unsafe=trusted' \
  'F c stdlib/Mem.ax:3:5-6 "Int" @0000000000000003 #erasures=5' \
  'F d core/z.ax:4:5-6 "Int" @0000000000000004 #calls=e' > "$work/synthetic.axsym"
if [[ "$(erasure_sum "$work/synthetic.axsym")" == 4 ]]; then
  ok "the sum counts compiler rows and skips the library's"
else
  bad "the sum of a synthetic stream read $(erasure_sum "$work/synthetic.axsym"), not 4"
fi

echo "--- explicit unsafe claims recognise confirmed erasures ---"
if python3 "$repo_root/tests/selfhost/erasure-claim-support.py" --axiom "$axc"; then
  ok "compiler and library erasures support unsafe claims; no-op claims remain refused"
else
  bad "erasure claim support or unchanged user diagnostics failed"
fi

echo "--- 5. erasure declarations do not depend on directory names ---"
if python3 "$repo_root/tests/selfhost/erasure-path-boundary.py" --axiom "$axc"; then
  ok "user paths cannot grant the library erasure exemption"
else
  bad "erasure path boundary regression"
fi

echo
if [ "$failed" -gt 0 ]; then
  echo "check-cast-arg-root: $failed of $checks checks failed"
  exit 1
fi
echo "check-cast-arg-root: $checks checks - cast census bounded, ownership preserved, AX3040 pinned, erasures ratcheted"
