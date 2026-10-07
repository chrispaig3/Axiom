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
# self_host/ is excluded: (cast Int ...) there is compiler plumbing
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
# Four are `stdlib/Task.ax`'s and `stdlib/Par.ax`'s spawn handle carried
# through the recovery point around a spawn, which answers a word, so
# each pool turns the handle into its word and back (`taskWordOf`,
# `parHandleOf`); each module states that as its one such cast. Three
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
cast_count="$(git -C "$repo_root" grep -h -o '(cast ' -- stdlib tests examples ':!tests/fuzz' | wc -l | tr -d ' ')"
if [ "$cast_count" -eq 0 ]; then
  bad "user-level: the cast count read 0 - the measurement is broken, not the tree clean"
elif [ "$cast_count" -le 475 ]; then
  ok "user-level (cast count $cast_count <= 475)"
else
  bad "user-level (cast count $cast_count > 475): new casts need a MM-VAL-23 reason and a baseline bump"
fi

echo "--- 2. type-preserving casts keep ownership ---"
cat > "$work/cast3.ax" <<'EOF'
(import Mem)
(import Str)
(:: main Int)
(fn (main)
  (let ((p (memAlloc 8)))
    {
      (memSetWord p 0 (strDup "hi"))
      0
    }))
EOF
cat > "$work/cast4.ax" <<'EOF'
(import Mem)
(import Str)
(:: main Int)
(fn (main)
  (let ((p (memAlloc 8)))
    {
      (memSetWord p 0 (cast String (strDup "hi")))
      0
    }))
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
  rel3="$(grep -c 'call void @axiom_release' "$work/cast3.ll" || true)"
  rel4="$(grep -c 'call void @axiom_release' "$work/cast4.ll" || true)"
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
(:: main Int)
(fn (main)
  (let ((p (memAlloc 8)))
    { (memSetWord p 0 (cast Int 7)) 0 }))
EOF
if "$axc" --diagnostic-format=ai emit-llvm "$work/scalar.ax" -o "$work/scalar.ll" \
     > /dev/null 2> "$work/scalar.err"; then
  if grep -q 'call void @axiom_release' "$work/scalar.ll"; then
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
# `self_host/typecheck.ax`), so `(cast Int c)` of a `Char` is not one,
# and `(cast Foreign s)` or `(cast Word p)` through an alias is.
#
# The compiler's own total is the work of retiring `Int` as its heap
# handle, and it may only fall. The ratchet is <=; a commit that adds
# an erasure to `self_host/` must lower another or update this number
# with its reason.
#
# Baseline 836 measured 2026-10-06: 804 on trunk `fc7ef7c0`, plus the
# 31 results that returned a record through a declared `Int` and now
# write `(cast Int ...)` because the implicit coercion is gone, plus
# one in `tcWalkDecls` opening the erasure-site list itself.
erasure_pin=836
erasure_sum() {  # <axsym> -> the #erasures= total over self_host/ rows
  awk '$1 == "F" && index($3, "self_host/") == 1 {
         for (i = 4; i <= NF; i++)
           if ($i ~ /^#erasures=[0-9]+$/) { v = $i; sub(/^#erasures=/, "", v); t += v }
       }
       END { print t + 0 }' "$1"
}
"$axc" --diagnostic-format=ai symbols self_host/main.ax > "$work/main.axsym" 2> "$work/main.err" || true
sh_rows="$(awk '$1 == "F" && index($3, "self_host/") == 1' "$work/main.axsym" | wc -l | tr -d ' ')"
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
    awk '$1 == "F" && index($3, "self_host/") == 1 && / #erasures=/ { for (i = 4; i <= NF; i++) if ($i ~ /^#erasures=/) print "     " $2, $3, $i }' "$work/main.axsym" \
      | sort -t= -k2 -rn | head -10
  fi
fi
# Every compiler module that writes a cast must be in the closure the
# sum reads, or its erasures would never be counted.
outside=""
for f in $(git -C "$repo_root" grep -l '(cast ' -- 'self_host/*.ax'); do
  grep -q " $f:" "$work/main.axsym" || outside="$outside $f"
done
if [[ -z "$outside" ]]; then
  ok "every self_host module with a cast is in self_host/main.ax's closure"
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

(type Word = Int)

(:: str (-> String Int))
(fn (str s)
  (cast Int s))

(:: box (-> Box Int))
(fn (box b)
  (cast Int b))

(:: vec (-> (Vec Int) Int))
(fn (vec v)
  (cast Int v))

(:: tv (-> a Int))
(fn (tv x)
  (cast Int x))

(:: fgn (-> String Foreign))
(fn (fgn s)
  (cast Foreign s))

(:: alias (-> Box Word))
(fn (alias b)
  (cast Word b))

(:: two (-> String String Int))
(fn (two a b)
  (+ (cast Int a) (cast Int b)))

(:: chr (-> Char Int))
(fn (chr c)
  (cast Int c))

(:: color (-> Color Int))
(fn (color c)
  (cast Int c))

(:: num (-> Int Float))
(fn (num n)
  (cast Float n))

(:: main Int)
(fn (main)
  0)
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
  'F a self_host/x.ax:1:5-6 "Int" @0000000000000001 #effects=Alloc #erasures=3' \
  'F b self_host/y.ax:2:5-6 "Int" @0000000000000002 #erasures=1 #unsafe=trusted' \
  'F c stdlib/Mem.ax:3:5-6 "Int" @0000000000000003 #erasures=5' \
  'F d self_host/z.ax:4:5-6 "Int" @0000000000000004 #calls=e' > "$work/synthetic.axsym"
if [[ "$(erasure_sum "$work/synthetic.axsym")" == 4 ]]; then
  ok "the sum counts compiler rows and skips the library's"
else
  bad "the sum of a synthetic stream read $(erasure_sum "$work/synthetic.axsym"), not 4"
fi

echo
if [ "$failed" -gt 0 ]; then
  echo "check-cast-arg-root: $failed of $checks checks failed"
  exit 1
fi
echo "check-cast-arg-root: $checks checks - cast census bounded, ownership preserved, AX3040 pinned, erasures ratcheted"
