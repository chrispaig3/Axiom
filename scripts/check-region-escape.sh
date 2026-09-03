#!/usr/bin/env bash
# THE ESCAPE RULE, MM-RGN-3, and the compatibility half of MM-RGN-4
# (docs/memory-model-v2-design.md §2, stage S3 of §4).
#
# Stage S3 lets a signature name the region a reference lives in,
# `(:: intern (-> (Str @s) (Table @r) (Sym @r)))`, and refuses a store,
# a return or a capture that would let a value be read after its
# region is reclaimed. Two claims rest on it, and this gate holds both
# from the outside:
#
#   1. AN ANNOTATION CHANGES NOTHING THE EMITTER SEES. The annotation
#      lives in a spare word of the type node that no reader of a
#      type consults (`tyRegion`, parser.ax), so a program and the
#      same program with every `@r` deleted emit BYTE-IDENTICAL LLVM.
#      `tests/stdlib/468-region-signatures.ax` against its stripped
#      twin. This is MM-RGN-4's "backward compatible by construction",
#      measured rather than argued; and it is what `check-self-host`'s
#      fixpoint cannot say, because nothing in self_host/ is annotated
#      (the seed's parser cannot read `@r` - land, reseed, then use).
#
#   2. THE RULE IS LOAD-BEARING. The five fixtures 645-649 are refused
#      for the codes they name (check-diagnostics holds the bytes; this
#      holds the codes so the gate reads alone), and an ABLATED
#      compiler - the tree with `rgnCheckAll` answering 0 - ACCEPTS
#      645-648. Then the program that compiler lets through is RUN:
#      `tests/region/escape-store.ax` stores a string from a region
#      into a cell that outlives it, resets the arena past the string,
#      reuses the bytes, and reads the cell back. It must not print
#      `hello` at exit 0. That is §1.4's measured behaviour today
#      turned into the thing this stage makes unspellable. 649's
#      `restrict(no-escape)` refusal must SURVIVE the ablation, because
#      it reads the facts and not the pass - one computation, two
#      readers, and the gate says which reader each claim rests on.
#
#   3. THE TWO-REGION SWEEP of §5 probe 1 is a program now
#      (`scripts/lib/region-sweep.py`): the count of `fn` declarations
#      whose body stores a value derived from one parameter into a
#      place derived from another. The note quotes 349 of 5,841
#      (5.98%) by a hand-run proxy and 3.5-5.2% by audit; the proxy
#      here reads 241 of 6,206 (3.88%) over the tree on 2026-09-03.
#      Held as a BAND rather than a point: a floor on how many
#      functions were swept (a proxy that stops parsing reads zero),
#      and a ceiling on the fraction, which is the claim MM-RGN-4's
#      ergonomics rest on. The ceiling is generous - 8% - because the
#      number is allowed to move with the corpus; what it may not do
#      is become most of the tree.
#
# Every refusal is anchored on a code and a NAME in the message, never
# on "the gate failed": a probe that broke the build would satisfy a
# red-expecting test, and section 4 of check-compat.sh records that
# happening once.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc
failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

fix="$repo_root/tests/diagnostics"
mkdir -p "$work/run"

# ---------------------------------------------------------------
# 1. byte-identity: the annotated program against its stripped twin
# ---------------------------------------------------------------
echo "== 1. an annotation changes nothing the emitter sees =="
cp "$repo_root/tests/stdlib/468-region-signatures.ax" "$work/run/ann.ax"
sed -E 's/ @[a-z][A-Za-z0-9_]*//g' "$work/run/ann.ax" > "$work/run/bare.ax"
# `;@axiom:` tags are not annotations; only ` @name` inside a type is.
if grep -qE ' @[a-z]' "$work/run/bare.ax"; then
  bad "the stripped twin still carries an annotation - the sed no longer matches the spelling"
fi
checks=$((checks + 1))
if ! "$axc" emit-llvm "$work/run/ann.ax" > "$work/run/ann.ll" 2> "$work/run/ann.err"; then
  bad "the annotated fixture did not emit"; sed 's/^/     /' "$work/run/ann.err" | head -10
elif ! "$axc" emit-llvm "$work/run/bare.ax" > "$work/run/bare.ll" 2> "$work/run/bare.err"; then
  bad "the stripped twin did not emit"; sed 's/^/     /' "$work/run/bare.err" | head -10
elif ! cmp -s "$work/run/ann.ll" "$work/run/bare.ll"; then
  bad "the annotated program and its stripped twin emit different IR"
  diff "$work/run/ann.ll" "$work/run/bare.ll" | head -10 | sed 's/^/     /'
else
  lines="$(wc -l < "$work/run/ann.ll" | tr -d ' ')"
  if [[ "$lines" -lt 500 ]]; then
    bad "the fixture emitted only $lines lines - it no longer reaches the library, so identity says nothing"
  else
    ok "468 with and without its annotations: byte-identical IR ($lines lines)"
  fi
fi
# and it RUNS to its golden, which is what makes the identity worth having
checks=$((checks + 1))
if "$axc" run "$work/run/ann.ax" > "$work/run/ann.out" 2>&1 \
   && diff -q "$work/run/ann.out" "$repo_root/tests/stdlib/468-region-signatures.out" > /dev/null; then
  ok "468 runs to its golden under the annotations"
else
  bad "468 did not run to its golden"; sed 's/^/     /' "$work/run/ann.out" | head -10
fi

# ---------------------------------------------------------------
# 2. the rule refuses, by code and by name
# ---------------------------------------------------------------
echo "== 2. the fixtures are refused for the codes they name =="
refused() {  # <case> <code> <name-in-message>
  local case="$1" code="$2" name="$3"
  checks=$((checks + 1))
  cp "$fix/$case.ax" "$work/run/$case.ax"
  ( cd "$work/run" && "$axc" --diagnostic-format=ai check "$case.ax" ) > /dev/null 2> "$work/run/$case.err"
  if grep -q "^[EW] $code .*$name" "$work/run/$case.err"; then
    ok "$case: $code names \`$name\`"
  else
    bad "$case: no $code naming \`$name\`"; sed 's/^/     /' "$work/run/$case.err" | cut -c1-160 | head -6
  fi
}
refused 645-region-escape-store   AX3060 'field `s`'
refused 645-region-escape-store   AX3060 'parameter `v` of `vecPush`'
refused 646-region-escape-return  AX3061 'pick'
refused 646-region-escape-return  AX3063 'orphan'
refused 647-region-capture        AX3062 'captures `s`'
refused 648-region-argument       AX3063 'pair'
refused 649-restrict-no-escape    AX3049 'through `vecPush`'
refused 649-restrict-no-escape    AX3051 'dispatch'
refused 649-restrict-no-escape    AX3057 'dispatchStrict'
# the program of section 3, refused by the tree's compiler
checks=$((checks + 1))
cp "$repo_root/tests/region/escape-store.ax" "$work/run/escape-store.ax"
( cd "$work/run" && "$axc" --diagnostic-format=ai check escape-store.ax ) > /dev/null 2> "$work/run/escape-store.err"
if grep -q '^E AX3060 .*field `s`' "$work/run/escape-store.err"; then
  ok "tests/region/escape-store.ax: AX3060 at the store"
else
  bad "tests/region/escape-store.ax is not refused with AX3060"; sed 's/^/     /' "$work/run/escape-store.err" | cut -c1-160 | head -4
fi

# ---------------------------------------------------------------
# 3. the ablation: the pass answering 0 accepts them, and the accepted
#    program reads reclaimed memory
# ---------------------------------------------------------------
echo "== 3. ablation: rgnCheckAll answering 0 =="
abl="$work/tree"
mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/" || {
  echo "FAIL: could not copy the tree to ablate" >&2; exit 1; }
python3 - "$abl/self_host/typecheck.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = """(pub fn (rgnCheckAll tc)
  (if (== (rgnProgramUsesRegions tc) 0)
    0
    {"""
new = """(pub fn (rgnCheckAll tc)
  (if (== 0 0)
    0
    {"""
if s.count(old) != 1:
    sys.exit("the ablation matched %d times, wanted 1" % s.count(old))
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
if [[ $? -ne 0 ]]; then
  bad "could not apply the ablation - rgnCheckAll has moved, and section 3 is asserting nothing"
elif ! AXIOM_STDLIB="$abl/stdlib" "$axc" build "$abl/self_host/main.ax" \
     -o "$work/axc-ablated" > "$work/ablated.build.log" 2>&1; then
  bad "the ablated compiler did not build"; sed 's/^/     /' "$work/ablated.build.log" | head -20
else
  accepted() {  # <case>
    local case="$1"
    checks=$((checks + 1))
    if ( cd "$work/run" && AXIOM_STDLIB="$abl/stdlib" "$work/axc-ablated" check "$case.ax" ) > "$work/run/$case.abl" 2>&1; then
      ok "ablated: $case is ACCEPTED - the pass is what refuses it"
    else
      bad "ablated: $case is still refused, so the refusal does not rest on the pass"
      sed 's/^/     /' "$work/run/$case.abl" | head -4
    fi
  }
  accepted 645-region-escape-store
  accepted 646-region-escape-return
  accepted 647-region-capture
  accepted 648-region-argument
  accepted escape-store
  # 649 rests on the facts, not the pass, and must survive
  checks=$((checks + 1))
  ( cd "$work/run" && AXIOM_STDLIB="$abl/stdlib" "$work/axc-ablated" --diagnostic-format=ai check 649-restrict-no-escape.ax ) > /dev/null 2> "$work/run/649.abl"
  if grep -q '^E AX3049 .*through `vecPush`' "$work/run/649.abl"; then
    ok "ablated: 649's restrict(no-escape) refusal survives - it reads the facts, not the pass"
  else
    bad "ablated: 649's AX3049 vanished with the pass, so no-escape rests on the pass after all"
  fi
  # THE RUN. Built by the ablated compiler, the escape happens.
  checks=$((checks + 1))
  if ! ( cd "$work/run" && AXIOM_STDLIB="$abl/stdlib" "$work/axc-ablated" build escape-store.ax -o escape-store ) > "$work/run/escape-store.build" 2>&1; then
    bad "the ablated compiler did not build tests/region/escape-store.ax"
    sed 's/^/     /' "$work/run/escape-store.build" | head -10
  else
    set +e
    ( cd "$work/run" && ./escape-store ) > "$work/run/escape-store.out" 2> "$work/run/escape-store.stderr"
    status=$?
    set -e
    got="$(head -c 64 "$work/run/escape-store.out" | tr -d '\0' | head -1)"
    if [[ "$status" -eq 0 && "$got" == "hello" ]]; then
      bad "the accepted program printed \`hello\` at exit 0 - the store it makes did not escape, so the refusal guards nothing"
    else
      ok "the accepted program does not answer \`hello\` at exit 0 (exit $status, read back: '${got:0:24}') - the stored value was reclaimed"
    fi
    set +e
  fi
fi

# ---------------------------------------------------------------
# 4. the two-region sweep, as a band
# ---------------------------------------------------------------
echo "== 4. the two-region sweep (§5 probe 1) =="
checks=$((checks + 1))
sweep="$(cd "$repo_root" && python3 scripts/lib/region-sweep.py self_host stdlib tests examples web/bench 2>&1 | tail -1)"
echo "     $sweep"
fns="$(printf '%s' "$sweep" | sed -n 's/.*fns=\([0-9]*\).*/\1/p')"
rel="$(printf '%s' "$sweep" | sed -n 's/.*relating=\([0-9]*\).*/\1/p')"
pct="$(printf '%s' "$sweep" | sed -n 's/.*pct=\([0-9.]*\).*/\1/p')"
if [[ -z "$fns" || -z "$rel" || -z "$pct" ]]; then
  bad "the sweep printed nothing this gate can read"
elif [[ "$fns" -lt 5000 ]]; then
  bad "the sweep saw only $fns functions; the tree holds thousands, so the proxy has stopped parsing"
elif [[ "$rel" -lt 100 ]]; then
  bad "the sweep found only $rel functions relating two regions; the hand audit found hundreds, so the store heads it recognises have moved"
elif python3 -c "import sys; sys.exit(0 if float('$pct') <= 8.0 else 1)"; then
  ok "$rel of $fns functions relate two regions ($pct%) - within the band MM-RGN-4's ergonomics claim rests on"
else
  bad "$rel of $fns functions relate two regions ($pct%) - above the 8% ceiling; MM-RGN-4's 'common case carries no annotation' needs re-measuring"
fi

echo
if [[ "$failed" -eq 0 ]]; then
  echo "check-region-escape: $checks checks, 0 failed"
  exit 0
fi
echo "check-region-escape: $checks checks, $failed failed"
exit 1
