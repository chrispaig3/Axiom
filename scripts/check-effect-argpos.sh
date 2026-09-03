#!/usr/bin/env bash
# Assert that the effect walk decides "is this unfollowed argument a
# hole?" from the CALLEE'S DECLARED ARGUMENT POSITION, and not from the
# argument's shape.
#
# WHAT THE RULE IS. `#effects-incomplete` marks a row as a LOWER bound:
# the walk met a call it could not resolve, so an effect absent from the
# row is not evidence that the body does not perform it. A claim of
# absence over such a row cannot be answered - `;@axiom:pure` draws
# `AX3037`, `restrict(no-io)` draws `AX3051`, a `handle` draws `AX3038`,
# each a warning rather than a verdict.
#
# A call through an effect-transparent parameter used to set that mark
# for every argument the walk could not follow, whatever the callee's
# signature said the argument WAS. `vecSiftDownBy` calls
# `(cmp (memGetWord d r) (memGetWord d k))` and `cmp` is declared
# `(-> Int Int Int)`: two loads into two `Int` positions. Measured on
# this tree at 0.6.1, before the type was consulted:
#
#   F vecSiftDownBy ... #effects=Mut #effects-incomplete #effect-params=cmp
#   F vecSortBy     ... #effects=Mut #effects-incomplete #effect-params=cmp
#
# The standard library's sort published its row as a lower bound on the
# strength of two machine words its own signature calls integers, and
# `restrict(no-io)` over anything reaching it came back `AX3051 cannot
# be checked` rather than OK.
#
# The rule now is `paramCallablesOf`'s, asked one level down: an arrow,
# a type variable or poison can hold a callable value; a concrete `Int`
# cannot, and a value handed to an `Int` position can hide no effect,
# because applying it is `AX3004` and the program does not compile.
#
# WHY A GATE AND NOT A GOLDEN. A population golden over `symbols` output
# would go green again the moment someone re-blessed it, which is
# exactly how a regression in this mark would land: the mark going
# MISSING is the silent direction, since it turns three unverifiable
# warnings into verdicts nobody asked for. So this asserts the
# DISCRIMINATION, shape by shape, with controls that must keep the mark
# - `check-agent-policy.sh`'s model, where `__atomic_load` carries no
# `Mut` precisely so the other four rows still mean something.
#
# THE CONTROLS ARE THE POINT. Four of the eight probe rows must KEEP
# `#effects-incomplete`, and each fails for a different reason:
#
#   twiceVar   the position is a type VARIABLE, which a caller may
#              instantiate to an arrow - the one case where the same
#              body as `twiceInt` must stay a lower bound
#   applyArr   the position is an arrow, so the callee really can call
#              what lands there
#   pairPos    a callee with an `Int` position AND an arrow position,
#              handed an unfollowable value in each: per position, not
#              per call
#   viaField   the head is not a name at all - a different row of
#              `MM-EXEC-9a`, which this change does not touch
#
# Without them, deleting the mark outright passes assertions 1 and 3.
#
# THE ABLATION restores the pre-fix condition in a shadow tree - the
# type test dropped from `escapeArgs` - rebuilds, and requires the
# "must be absent" rows to go red while the controls stay green. It
# costs one compiler build, which is what `check-effect-fixpoint.sh`
# pays for the same guarantee.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# --------------------------------------------------------------------
# The probe. Eight declarations, four that must carry the mark and
# three that must not, plus `main`. Written out rather than generated:
# every line of it is a claim about one shape, and a generator would
# put a layer between the shape and the reader.
# --------------------------------------------------------------------
mkdir -p "$work/probe"
cat > "$work/probe/argpos.ax" <<'AX'
; `(f (f x))` hands an unfollowable value - the result of a call - to
; `f`. These two bodies are identical and their rows must differ,
; because their SIGNATURES differ.
(:: twiceInt (-> (-> Int Int) Int Int))
(fn (twiceInt f x) (f (f x)))

(:: twiceVar (-> (-> a a) a a))
(fn (twiceVar f x) (f (f x)))

(:: mkFn (-> Int (-> Int Int)))
(fn (mkFn n) (lambda (y) (+ y n)))

(:: applyArr (-> (-> (-> Int Int) Int) Int))
(fn (applyArr g) (g (mkFn 1)))

(:: pairPos (-> (-> Int (-> Int Int) Int) Int Int))
(fn (pairPos g x) (g (+ x 1) (mkFn x)))

(:: onlyInt (-> (-> Int Int Int) Int Int))
(fn (onlyInt g x) (g (+ x 1) (+ x 2)))

(struct Cell (run : (-> Int Int)))

(:: viaField (-> Cell Int Int))
(fn (viaField c x) ((c.run) x))

(:: main Int)
(fn (main) 0)
AX

# `<compiler> <outfile>` - the probe's AXSYM rows, own file only.
probe_rows() {
  ( cd "$work/probe" && AXIOM_STDLIB="$repo_root/stdlib" \
      "$1" --diagnostic-format=ai symbols argpos.ax ) \
    2>"$work/probe.err" | grep '^F ' > "$2" || true
}

# Does declaration `$2` in stream `$1` carry `#effects-incomplete`?
has_mark() {
  grep -qE "^F $2 .*#effects-incomplete" "$1"
}

# The two halves of the rule, named once so the ablation can re-use
# them. ABSENT: the callee's position cannot hold a function.
# PRESENT: it can, or the head was never resolved at all.
absent=(twiceInt onlyInt)
present=(twiceVar applyArr pairPos viaField)

probe_rows "$axc" "$work/rows"
rows=$(wc -l < "$work/rows" | tr -d ' ')

echo "== the probe =="
checks=$((checks + 1))
if (( rows < 8 )); then
  echo "FAIL: the probe listed only $rows declarations; it declares 8."
  echo "      A stream this short would satisfy every 'absent' assertion below"
  echo "      by holding nothing at all."
  sed 's/^/     /' "$work/probe.err" | head -10
  failed=$((failed + 1))
  echo
  echo "check-effect-argpos: the probe did not resolve; nothing below was measured"
  exit 1
fi
echo "ok   the probe lists $rows declarations"
checks=$((checks + 1))
echo

# --------------------------------------------------------------------
echo "== 1. an unfollowed argument in a position that cannot hold a function is not a hole =="
# --------------------------------------------------------------------
for d in "${absent[@]}"; do
  if has_mark "$work/rows" "$d"; then
    bad "$d carries #effects-incomplete; every argument position it passes an unfollowed value to is declared Int"
    grep -E "^F $d " "$work/rows" | sed 's/^/     /' || true
  else
    ok "$d is complete - $(grep -E "^F $d " "$work/rows" | sed -E 's/.*"([^"]*)".*/\1/' || true)"
  fi
done

# --------------------------------------------------------------------
echo
echo "== 2. and in a position that can, it still is (the controls) =="
# --------------------------------------------------------------------
for d in "${present[@]}"; do
  if has_mark "$work/rows" "$d"; then
    ok "$d is still a lower bound"
  else
    bad "$d lost #effects-incomplete - a value the walk cannot follow reaches a position that CAN hold a function, and the row now reads as complete"
    grep -E "^F $d " "$work/rows" | sed 's/^/     /' || true
  fi
done

# --------------------------------------------------------------------
echo
echo "== 3. the library's own sort, which is what found this =="
# --------------------------------------------------------------------
# `vecSortBy`/`vecSiftDownBy` are the real-corpus instance. Asserted
# against the tree's stdlib rather than a copy, and asserted in BOTH
# directions: the mark is gone AND the row it belongs to is still there.
# Without the second half, an effect walk that stopped reporting
# anything at all would pass this.
mkdir -p "$work/lib"
cat > "$work/lib/lib.ax" <<'AX'
(import Vec)
(import Http)

(:: main Int)
(fn (main) 0)
AX
( cd "$work/lib" && AXIOM_STDLIB="$repo_root/stdlib" \
    "$axc" --diagnostic-format=ai symbols lib.ax ) 2>"$work/lib.err" \
  | grep '^F ' > "$work/librows" || true

for d in vecSortBy vecSiftDownBy; do
  row="$(grep -E "^F $d " "$work/librows" || true)"
  checks=$((checks + 1))
  if [[ -z "$row" ]]; then
    echo "FAIL: $d is not in the stdlib symbol stream at all"
    failed=$((failed + 1))
  elif [[ "$row" == *"#effects-incomplete"* ]]; then
    echo "FAIL: $d still reads as a lower bound"
    echo "     $row"
    failed=$((failed + 1))
  elif [[ "$row" != *"#effects=Mut"* || "$row" != *"#effect-params=cmp"* ]]; then
    echo "FAIL: $d lost more than the marker - its row no longer says Mut through a transparent \`cmp\`"
    echo "     $row"
    failed=$((failed + 1))
  else
    echo "ok   $d: Mut, transparent in cmp, and no longer a lower bound"
  fi
done

# The control from the real corpus: `httpCall` is `((h.run) fd r)`, a
# head that is not a name, and nothing here may touch it.
checks=$((checks + 1))
if grep -qE '^F httpCall .*#effects-incomplete' "$work/librows"; then
  echo "ok   httpCall is still a lower bound - dispatch through a struct field is a different row of MM-EXEC-9a"
else
  echo "FAIL: httpCall lost #effects-incomplete; it calls a value out of a record and nothing resolved it"
  grep -E '^F httpCall ' "$work/librows" | sed 's/^/     /' || echo "     (no row at all)"
  failed=$((failed + 1))
fi

# --------------------------------------------------------------------
echo
echo "== 4. and the type test is what does it (ablation) =="
# --------------------------------------------------------------------
# The seam is `escapeArgs`'s condition, matched whole so a rename or a
# reformat upstream is a loud failure here rather than a silent no-op.
#
# It was one such loud failure on 2026-09-01, and the report was right.
# The `Vec` port gave `escapeArgs` the signature
# `(-> Int (Vec Int) Int (Vec a) Int Int)`: `acc` is a container now and
# not a bare word, so its absent test is spelled the way the port spells
# every absent container - `(!= (cast Int acc) 0)` where it read
# `(!= acc 0)`. The RULE this gate names did not move. The type test on
# `(arrowParamTy cty i)` is the same conjunct of the same condition, and
# the ablation still drops exactly it and nothing else; only the
# sentinel's spelling changed, so only the string changed.
abl="$work/tree"
mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/"
seam='      (if (&& (== (escapeValue bound (vecGet args i)) 0) (&& (!= (cast Int acc) 0) (== (tyIsCallable (arrowParamTy cty i)) 1)))'
n_seam="$(grep -c -F -x "$seam" "$abl/self_host/typecheck.ax" || true)"
checks=$((checks + 1))
if [[ "$n_seam" != 1 ]]; then
  echo "FAIL: self_host/typecheck.ax holds $n_seam copies of the ablation seam; this gate expects exactly 1"
  failed=$((failed + 1))
else
  python3 - "$abl/self_host/typecheck.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = "(if (&& (== (escapeValue bound (vecGet args i)) 0) (&& (!= (cast Int acc) 0) (== (tyIsCallable (arrowParamTy cty i)) 1)))"
new = "(if (&& (== (escapeValue bound (vecGet args i)) 0) (!= (cast Int acc) 0))"
assert s.count(old) == 1
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  if ! ( cd "$abl" && "$axiom" build --input self_host/main.ax --output "$work/axc-abl" ) \
       > "$work/abl.build.log" 2>&1; then
    echo "FAIL: the ablated compiler would not build"
    sed 's/^/     /' "$work/abl.build.log" | head -10
    failed=$((failed + 1))
  else
    probe_rows "$work/axc-abl" "$work/rows.abl"
    regressed=0
    for d in "${absent[@]}"; do
      if has_mark "$work/rows.abl" "$d"; then
        regressed=$((regressed + 1))
      fi
    done
    kept=0
    for d in "${present[@]}"; do
      if has_mark "$work/rows.abl" "$d"; then
        kept=$((kept + 1))
      fi
    done
    checks=$((checks + 1))
    if (( regressed == ${#absent[@]} )); then
      echo "ok   without the type test all ${#absent[@]} complete rows go back to lower bounds - assertion 1 is measuring it"
    else
      echo "FAIL: the ablated compiler still reports $((${#absent[@]} - regressed)) of ${#absent[@]} as complete."
      echo "      Assertion 1 would pass with the type test deleted, so it tests nothing."
      failed=$((failed + 1))
    fi
    checks=$((checks + 1))
    if (( kept == ${#present[@]} )); then
      echo "ok   and all ${#present[@]} controls are marked either way - the ablation moves one rule, not the walk"
    else
      echo "FAIL: the ablation changed a control too ($kept of ${#present[@]} still marked); the seam is not the rule this gate names"
      failed=$((failed + 1))
    fi
  fi
fi

echo
if (( failed > 0 )); then
  echo "check-effect-argpos: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-effect-argpos: $checks checks - the position decides, ${#present[@]} controls hold it, and the ablation proves it"
