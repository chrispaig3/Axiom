#!/usr/bin/env bash
# A `Vec` field must map exactly as the `Int` it replaces.
#
# `fldClass` (self_host/codegen.ax) decides, per declared field type,
# whether a block's reference map names that word: 0 (scalar, never
# walked), 2 (reference, walked and released) or 1 (unclassifiable).
# Class 1 forces the whole block to the leaf shape, the safe direction:
# under-reclaiming leaks, while a wrong bit is a use-after-free. So one
# unclassified field drops the reference map for every other field, and
# a `String` beside it is never released, with no diagnostic.
#
# A `Vec` field is class 0. A `Vec` header is a counted block, but
# `stdlib/Vec.ax` makes `vecFree` the only thing that ends a vector, so a
# record holding one does not own it and must not release it. Class 0 is
# also what the field got when it was spelled `Int`, so typing the handle
# changes no reclamation. Moving `Vec` to class 2 would first need an
# audit of every `vecFree`.
#
# The four rows:
#
#   1. Anchor. `(MkRec Int String)` maps its `String`. A nonzero row
#      proves the extractor reads a shape word at all, and is not an
#      awk range that never opened.
#   2. The claim. `(MkRec (Vec Int) String)` reads the same word. An
#      unclassified `Vec` reads 8, the leaf shape, so losing the `Vec`
#      arm in `fldClass` fails this row.
#   3. The map varies. `(MkRec Int Int)` maps nothing, so an extractor
#      that answers one constant cannot satisfy row 2.
#   4. A `Vec` is not walked. `(MkRec (Vec Int) Int)` maps nothing. This
#      breaks if row 2 is "fixed" by making `Vec` a reference.
#
# Rows 3 and 4 are the ablation: the same fixture with one field type
# changed, and they must move the number.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# The shape word is the store into the block header at offset -8. It is
# read from `@mk` alone, so no other shape word in the module can stand
# in for the one under test.
shape_of() {
  awk '/^define i64 @mk\(/,/^}/' "$1" \
    | awk '/add i64 %\.t0, -8/{seen=1}
           seen && /^ *store i64 [0-9]+, ptr/{gsub(/[^0-9]/,"",$3); print $3; exit}'
}

# $1 field-0 type, $2 field-1 type, $3 field-1 literal, $4 field-0 argument
emit_shape() {
  local f0="$1" f1="$2" lit="$3" arg="$4" src="$work/shape.ax" ll="$work/shape.ll"
  cat > "$src" <<EOF
(import Vec)
(data Rec (MkRec $f0 $f1))
(:: mk (-> $f0 Rec))
(fn (mk n) (MkRec n $lit))
(fn (main) (match (mk $arg) ((MkRec a b) 0)))
EOF
  if ! "$axc" emit-llvm "$src" -o "$ll" >"$work/shape.err" 2>&1; then
    echo "COMPILE-FAILED"
    return
  fi
  local s; s="$(shape_of "$ll")"
  echo "${s:-NO-SHAPE-WORD}"
}

VEC='(cast (Vec Int) (vecNew))'

echo "== the shape word a record gets, by the type of its first field =="
anchor="$(emit_shape Int String '"hi"' 7)"
vecref="$(emit_shape '(Vec Int)' String '"hi"' "$VEC")"
twoint="$(emit_shape Int Int 0 7)"
vecint="$(emit_shape '(Vec Int)' Int 0 "$VEC")"

printf '     %-22s %s\n' "(MkRec Int       String)" "$anchor"
printf '     %-22s %s\n' "(MkRec (Vec Int) String)" "$vecref"
printf '     %-22s %s\n' "(MkRec Int       Int)"    "$twoint"
printf '     %-22s %s\n' "(MkRec (Vec Int) Int)"    "$vecint"

# 1. Anchor: the extractor reads a real, mapped shape word.
if [[ "$anchor" == "262152" ]]; then
  ok "a String field is mapped: (MkRec Int String) reads 262152"
else
  bad "anchor: (MkRec Int String) reads '$anchor', expected 262152 (bit 18 = block word 2)"
fi

# 2. The claim: a Vec field changes nothing about the map.
if [[ "$vecref" == "$anchor" && "$anchor" != "" ]]; then
  ok "a (Vec Int) field maps exactly as the Int it replaces ($vecref)"
else
  bad "a (Vec Int) field reads '$vecref' where the Int it replaces reads '$anchor'"
  if [[ "$vecref" == "8" ]]; then
    echo "     8 is the LEAF shape - this is the unclassified-Vec defect itself:"
    echo "     fldClass answered 1, and the String sibling lost its map."
  fi
fi

# 3. The map varies: two scalars map nothing.
if [[ "$twoint" == "8" ]]; then
  ok "two scalar fields map nothing: (MkRec Int Int) reads 8"
else
  bad "(MkRec Int Int) reads '$twoint', expected 8 - the extractor is not reading the map"
fi

# 4. A Vec is not walked: the class-0 half of the claim.
if [[ "$vecint" == "$twoint" && "$twoint" != "" ]]; then
  ok "a Vec is class 0, not a walked reference: (MkRec (Vec Int) Int) reads $vecint"
else
  bad "(MkRec (Vec Int) Int) reads '$vecint', expected $twoint - a Vec must not be walked"
fi

# 5. The mapped and unmapped rows must differ, or 2 and 4 are one claim
#    asserted twice.
if [[ "$anchor" != "$twoint" ]]; then
  ok "the mapped and unmapped rows differ ($anchor vs $twoint)"
else
  bad "mapped and unmapped rows both read '$anchor' - this table proves nothing"
fi

echo
if (( failed == 0 )); then
  echo "check-vec-field-shape: $checks checks - a Vec field maps as its Int did"
  exit 0
fi
echo "check-vec-field-shape: $failed of $((checks + failed)) checks failed"
exit 1
