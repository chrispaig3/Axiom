#!/usr/bin/env bash
# The effect walk decides whether an unfollowed argument is a hole from
# the callee's declared argument position, not from the argument's
# shape.
#
# `#effects-incomplete` marks a row as a lower bound: the walk met a
# call it could not resolve, so an effect missing from the row may still
# happen. A claim of absence over such a row draws a warning instead of
# a verdict: `;@axiom:effect(pure)` draws `AX3037`, `restrict(no-io)`
# draws `AX3051` and a `handle` draws `AX3038`.
#
# The rule is `paramCallablesOf`'s, asked one level down. An arrow, a
# type variable or poison can hold a callable value. A concrete `Int`
# cannot, and a value passed to an `Int` position hides no effect,
# because applying it is `AX3004` and the program does not compile. So
# `vecSiftDownBy`, which passes two loads to `cmp :: (-> Int Int Int)`,
# has a complete row, and so does `vecSortBy`.
#
# A `symbols` golden would not hold this: re-blessing it would hide a
# regression. A lost mark is the silent direction, since it turns three
# warnings into verdicts nobody asked for. So this asserts the rule,
# shape by shape, with controls that must keep the mark, as
# `check-agent-policy.sh` does.
#
# Four of the eight probe rows are controls that must keep
# `#effects-incomplete`, each for a different reason:
#
#   twiceVar   the position is a type variable, which a caller may
#              instantiate to an arrow, so the same body as `twiceInt`
#              stays a lower bound
#   applyArr   the position is an arrow, so the callee can call what
#              lands there
#   pairPos    one `Int` position and one arrow position, each handed
#              an unfollowable value: the rule is per position
#   viaField   the head is not a name, a different row of `MM-EXEC-9a`
#              that this rule does not touch
#
# Without them, deleting the mark outright would pass sections 1 and 3.
#
# The ablation drops the type test from `escapeArgs` in a shadow tree,
# rebuilds, and requires the must-be-absent rows to regain the mark
# while the controls keep it. It costs one compiler build, like
# `check-effect-fixpoint.sh`.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# --------------------------------------------------------------------
# The probe: eight declarations. Four must carry the mark, two must
# not, and `mkFn` and `main` support them. It is written by hand because
# each line is a claim about one shape.
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

# probe_rows <compiler> <outfile>: the probe file's own AXSYM rows.
probe_rows() {
  ( cd "$work/probe" && AXIOM_STDLIB="$repo_root/stdlib" \
      "$1" --diagnostic-format=ai symbols argpos.ax ) \
    2>"$work/probe.err" | grep '^F ' > "$2" || true
}

# Does declaration `$2` in stream `$1` carry `#effects-incomplete`?
has_mark() {
  grep -qE "^F $2 .*#effects-incomplete" "$1"
}

# The two halves of the rule, named once so the ablation can reuse them.
# `absent`: the callee's position cannot hold a function. `present`: it
# can, or the head was never resolved.
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
# `vecSortBy` and `vecSiftDownBy` are the real-library case, checked
# against the tree's stdlib. Both directions are asserted: the mark is
# gone, and the row still says `Mut` through `cmp`. Otherwise a walk
# that reported nothing at all would pass.
mkdir -p "$work/lib"
cat > "$work/lib/lib.ax" <<'AX'
(import Vec)

; The control below: a handler held in a record's field and called
; through it, `((h.run) n)` - a head that is not a name. The standard
; library had one in `Http`'s router, and a program still writes one
; whenever it keeps callbacks in a table.
(struct Handler
  (run : (-> Int Int)))

(:: dispatch (-> Handler Int Int))
(fn (dispatch h n)
  ((h.run) n))

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

# The control: `dispatch` is `((h.run) n)`, a head that is not a name,
# so it keeps the mark.
checks=$((checks + 1))
if grep -qE '^F dispatch .*#effects-incomplete' "$work/librows"; then
  echo "ok   dispatch is still a lower bound - dispatch through a struct field is a different row of MM-EXEC-9a"
else
  echo "FAIL: dispatch lost #effects-incomplete; it calls a value out of a record and nothing resolved it"
  grep -E '^F dispatch ' "$work/librows" | sed 's/^/     /' || echo "     (no row at all)"
  failed=$((failed + 1))
fi

# --------------------------------------------------------------------
echo
echo "== 4. and the type test is what does it (ablation) =="
# --------------------------------------------------------------------
# The seam is `escapeArgs`'s whole condition, matched exactly once, so
# a rename or reformat upstream fails here loudly instead of ablating
# nothing. The ablation drops only the `(arrowParamTy cty i)` type test.
# When a port or the formatter respells the condition without changing
# the rule, update both strings to the new spelling.
abl="$work/tree"
mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/"
# The condition as the formatter lays it out, then the same block with
# the callable conjunct removed.
seam_old='      (if (&&
        (== (escapeValue bound (vecGet args i)) 0)
        (&&
          (!=
            (cast Int acc)
            0)
          (== (tyIsCallable (arrowParamTy cty i)) 1)))'
seam_new='      (if (&&
        (== (escapeValue bound (vecGet args i)) 0)
          (!=
            (cast Int acc)
            0))'
n_seam="$(python3 -c 'import sys; print(open(sys.argv[1], encoding="utf-8").read().count(sys.argv[2]))' "$abl/self_host/typecheck.ax" "$seam_old" || true)"
checks=$((checks + 1))
if [[ "$n_seam" != 1 ]]; then
  echo "FAIL: self_host/typecheck.ax holds $n_seam copies of the ablation seam; this gate expects exactly 1"
  failed=$((failed + 1))
else
  python3 - "$abl/self_host/typecheck.ax" "$seam_old" "$seam_new" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
assert s.count(old) == 1
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  if ! gate_build_tree "$axiom" "$abl" "$AXIOM_STDLIB" "$work/axc-abl" \
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
