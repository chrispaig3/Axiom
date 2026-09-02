#!/usr/bin/env bash
# A `Vec` FIELD MUST MAP EXACTLY AS THE `Int` IT REPLACES.
#
# `fldClass` (self_host/codegen.ax) decides, per declared field type,
# whether a block's reference map names that word. Its three answers
# are 0 (machine scalar, never walked), 2 (reference, walked and
# released) and 1 (UNCLASSIFIABLE) - and 1 does not mean "skip this
# field", it forces the WHOLE block to the leaf shape. The comment
# there states why: "under-reclaiming leaks, a wrong bit
# use-after-frees, and only one of those is survivable".
#
# THE DEFECT THIS GATE EXISTS FOR. `Vec` became a writable type when
# it was seeded beside `Option` (`docs/generics-design.md` section 1),
# and `fldClass` had no arm for it: not a scalar name, not one of the
# `String`/`Option`/`Handle` trio, and - being seeded by the checker
# rather than declared - not in the module's data list either. So it
# fell to 1, and a record holding a `Vec` lost the reference map for
# its OTHER fields. Measured on `(data Rec (MkRec (Vec Int) String))`:
# shape word 8 where the same record with an `Int` in that slot reads
# 262152, so the `String`'s share was never handed back. No
# diagnostic, every gate green, and reachable from ordinary source.
#
# WHY 0 AND NOT 2. A `Vec` header IS a counted block, so 2 is the
# truthful-looking answer and it is the wrong one HERE: `stdlib/Vec.ax`
# says "a vector is born owned ... and `vecFree` is the only thing
# that ends one", so a record that merely holds a vector does not own
# it and must not release it. 0 is also exactly what such a field got
# while it was spelled `Int`, which is what makes typing the handle a
# type-level change with no reclamation consequence. Moving `Vec` to
# class 2 is a separate decision that would have to audit every
# `vecFree` first; it is not this gate's claim.
#
# WHAT IT ASSERTS, and why the table has four rows rather than one.
#
#   1. ANCHOR. `(MkRec Int String)` maps its `String`. This is what
#      proves the extractor reads a shape word at all - without a row
#      that is nonzero, every zero below could be an awk range that
#      never opened.
#   2. THE CLAIM. `(MkRec (Vec Int) String)` reads the SAME word.
#      Before the fix this row read 8, so the row cannot pass
#      vacuously: it is the defect's own signature.
#   3. THE MAP VARIES. `(MkRec Int Int)` maps nothing. Two scalars
#      must not produce the anchor's word, or row 2's equality would
#      be satisfied by an extractor that answers one constant.
#   4. A `Vec` IS NOT ITSELF WALKED. `(MkRec (Vec Int) Int)` maps
#      nothing either - that is the class-0 half of the claim, and it
#      is what would break if someone "fixed" row 2 by making `Vec` a
#      reference.
#
# Rows 3 and 4 are the ablation: they are the same fixture with one
# field type changed, and they must move the number.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# The shape word is the store into the block header at offset -8, and
# it is read from `@mk` alone so that a shape word emitted anywhere
# else in the module cannot stand in for the one under test.
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

# 1. ANCHOR - the extractor reads a real, mapped shape word.
if [[ "$anchor" == "262152" ]]; then
  ok "a String field is mapped: (MkRec Int String) reads 262152"
else
  bad "anchor: (MkRec Int String) reads '$anchor', expected 262152 (bit 18 = block word 2)"
fi

# 2. THE CLAIM - a Vec field changes nothing about the map.
if [[ "$vecref" == "$anchor" && "$anchor" != "" ]]; then
  ok "a (Vec Int) field maps exactly as the Int it replaces ($vecref)"
else
  bad "a (Vec Int) field reads '$vecref' where the Int it replaces reads '$anchor'"
  if [[ "$vecref" == "8" ]]; then
    echo "     8 is the LEAF shape - this is the unclassified-Vec defect itself:"
    echo "     fldClass answered 1, and the String sibling lost its map."
  fi
fi

# 3. THE MAP VARIES - two scalars map nothing.
if [[ "$twoint" == "8" ]]; then
  ok "two scalar fields map nothing: (MkRec Int Int) reads 8"
else
  bad "(MkRec Int Int) reads '$twoint', expected 8 - the extractor is not reading the map"
fi

# 4. A Vec IS NOT ITSELF WALKED - the class-0 half of the claim.
if [[ "$vecint" == "$twoint" && "$twoint" != "" ]]; then
  ok "a Vec is class 0, not a walked reference: (MkRec (Vec Int) Int) reads $vecint"
else
  bad "(MkRec (Vec Int) Int) reads '$vecint', expected $twoint - a Vec must not be walked"
fi

# 5. The two rows really are different numbers, or 2 and 4 are one
#    claim asserted twice.
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
