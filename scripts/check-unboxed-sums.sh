#!/usr/bin/env bash
# WHAT AN `Option` COSTS, COUNTED IN THE EMITTED IR.
#
# `(Some v)` is a 16-byte heap block - `axiom_alloc`, a shape word, a
# tag, a refcount and the field - which the consumer reads back and
# hands to `axiom_release`. `docs/unboxed-sums-design.md` measures that
# wrapper at 11.86 ns and prototypes a `{tag, payload}` register pair
# that costs 0.36 ns, and its section 4 asks for exactly this gate
# before any code generation moves:
#
#   count `axiom_alloc` calls in the emitted IR for a fixture with a
#   known number of matched lookups, with an ablation that forces the
#   boxed path and must move the count
#
# WHY A COUNT AND NOT A TIMING. `bench-compile.sh` is explicit that a
# wall-clock bound on a shared runner is a flaky test, and the ratio
# gates that exist here measure scaling rather than constants. The
# number of heap blocks a construction costs is neither: it is a
# property of the emitted module, it is exact, and it is the thing the
# optimisation is about. A timing gate would go red on a noisy runner
# and stay green on a representation regression; this does the reverse.
#
# WHAT IT ASSERTS.
#
#   1. BEHAVIOUR IS FIXED. The fixture answers 249500 at `--opt` 0, 1
#      and 2. Any representation change has to keep this, and it is
#      first because a faster wrong answer is not the goal.
#
#   2. THE SPECIALISATION HAPPENED, AND THEN THAT IT IS FREE, in that
#      order. `@optFind$pair` is defined and returns `{ i64, i64 }`;
#      the match calls it once and reads the tag and payload with two
#      `extractvalue`s; the variant builds ALLOC_EXPECT blocks and the
#      consumer performs RELEASE_EXPECT releases, both 0. The order
#      matters: a zero block count is satisfied just as well by a
#      function that was never emitted, so the existence check comes
#      first or the rest asserts an optimisation by absence of
#      evidence. Both were 1 before the specialisation landed.
#
#   3. A REFUSED SHAPE STILL BOXES, AND IS COUNTED. `(Option String)`
#      carries a reference, which `pairRetOK` declines - the block owns
#      a share of it and a pair has no refcount to give that share
#      back with, so a variant here would be a use-after-free rather
#      than a speedup. It must still build one block, which is also
#      what proves `calls_in` reads the IR at all: without it the
#      zeroes above could be an awk range that never opened.
#
#   4. THE COUNTER IS ANCHORED ON ONE DEFINITION. A name with no
#      definition in the module must read 0 while `optStr` reads more.
#      3 proves the counter can be nonzero; this proves it is not
#      counting every `axiom_alloc` in the program.
#
# THE FIXTURE LIVES HERE, in a heredoc, rather than under `tests/`.
# Every `.ax` added to `tests/selfhost/` is swept by several gates that
# carry population counts, so a fixture whose only reader is this gate
# would move numbers in gates that have nothing to say about it.
#
# Usage:
#   scripts/check-unboxed-sums.sh
#   AXIOM=path/to/compiler scripts/check-unboxed-sums.sh

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

gate_build_axc axc

failed=0
checks=0
ok()  { checks=$((checks + 1)); echo "ok   $*"; }
bad() { checks=$((checks + 1)); failed=$((failed + 1)); echo "FAIL $*"; }

# The counts this tree's code generation produces. Both were 1 before
# the register-pair specialisation landed and are 0 after; a rise is a
# representation regression.
ALLOC_EXPECT=0
RELEASE_EXPECT=0
# What a REFUSED shape still costs. `(Option String)` carries a
# reference, which `pairRetOK` declines - the block owns a share of it
# today and a pair has no refcount to hand that share back with.
REFUSED_ALLOC_EXPECT=1
GOLDEN=249500

mkdir -p "$work/us"

# `optFind` is the canonical absence shape - the form `internFind`,
# `pathLastSlash`, `pathExtIndex`, `strHexVal`, `utf8DecodeAt`,
# `utf8CharAt` and `keyStrEnd` are every one written in: a guard, a
# `None`, and a `(Some e)`. `sum` consumes it by matching the DIRECT
# call, which is the only site shape the specialisation rewrites.
write_fixture() {
  cat > "$1" <<'AX'
(import IO)

(:: optFind (-> Int (Option Int)))

(fn (optFind n)
  (if (< n 0)
    None
    (Some (* n 2))
  )
)

(:: sum (-> Int Int Int))

(fn (sum i acc)
  (if (>= i 1000)
    acc
    (sum (+ i 1) (+ acc (match (optFind (- i 500)) ((Some v) v) ((None) 0))))
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println (sum 0 0))
    0
  }
)
AX
}

# `calls_in <ir> <fn> <symbol>`: how many times `symbol` is called
# inside the definition of `fn`. Anchored on `define ... @fn(` and the
# closing brace, so a call in a neighbouring function is not counted -
# check 4 is what proves that anchoring holds.
calls_in() {
  awk -v f="$2" -v s="$3" '
    $0 ~ ("^define .*@" f "\\(") { inside = 1 }
    inside && index($0, s) > 0   { n++ }
    inside && /^}/               { inside = 0 }
    END { print n + 0 }' "$1"
}

# ------------------------------------------------------------------
echo "== 1. behaviour: the answer does not depend on the representation =="
# ------------------------------------------------------------------
write_fixture "$work/us/us.ax"
for o in 0 1 2; do
  if ! "$axc" build --opt "$o" --input "$work/us/us.ax" --output "$work/us/us$o" \
       > "$work/us/build$o.log" 2>&1; then
    bad "the fixture did not build at --opt $o"
    sed 's/^/     /' "$work/us/build$o.log" | head -10
    continue
  fi
  got="$("$work/us/us$o" 2>&1 || true)"
  if [[ "$got" == "$GOLDEN" ]]; then
    ok "--opt $o answers $GOLDEN"
  else
    bad "--opt $o answers '$got', wanted $GOLDEN"
  fi
done

# ------------------------------------------------------------------
echo
echo "== 2. cost: the blocks an Option construction and its match cost =="
# ------------------------------------------------------------------
"$axc" emit-llvm --input "$work/us/us.ax" -o "$work/us/us.ll" > /dev/null 2>&1 \
  || { bad "could not emit IR for the fixture"; }

if [[ -f "$work/us/us.ll" ]]; then
  # FIRST that the specialisation happened at all. Without this, the
  # two zeroes below are satisfied just as well by a function that was
  # never emitted - a check that cannot fail, asserting an optimisation
  # by the absence of evidence.
  if grep -q '^define { i64, i64 } @optFind\$pair(' "$work/us/us.ll"; then
    ok "\`optFind\` has a register-pair variant, returning { i64, i64 }"
  else
    bad "no \`@optFind\$pair\` in the module - the specialisation did not happen,
     and the two counts below would read 0 for the wrong reason"
  fi
  nx="$(calls_in "$work/us/us.ll" sum 'call { i64, i64 } @optFind$pair')"
  ex="$(calls_in "$work/us/us.ll" sum 'extractvalue { i64, i64 }')"
  if (( nx == 1 && ex == 2 )); then
    ok "the match calls it once and reads the tag and payload from registers"
  else
    bad "the match site makes $nx pair call(s) and $ex extractvalue(s), wanted 1 and 2"
  fi
  a="$(calls_in "$work/us/us.ll" 'optFind\$pair' axiom_alloc)"
  r="$(calls_in "$work/us/us.ll" sum axiom_release)"
  if [[ "$a" == "$ALLOC_EXPECT" ]]; then
    ok "the pair variant builds $a heap blocks - the Option is free"
  else
    bad "the pair variant builds $a heap block(s), the file says $ALLOC_EXPECT
     This number is the claim, so move ALLOC_EXPECT in the same commit
     that moves the code generator, and not before."
  fi
  if [[ "$r" == "$RELEASE_EXPECT" ]]; then
    ok "the matching consumer performs $r releases - there is no block to free"
  else
    bad "the matching consumer performs $r release(s), the file says $RELEASE_EXPECT"
  fi
fi

# ------------------------------------------------------------------
echo
echo "== 3. negative probe: a REFUSED shape still boxes, and is counted =="
# ------------------------------------------------------------------
# The instrument check, and the safety restriction, in one. If
# `calls_in` matched nothing - a renamed symbol, an awk range that
# never opened - section 2's zeroes would read 0 for that reason
# instead of for the optimisation. A reference payload is the shape
# `pairRetOK` declines, so it must still allocate.
cat > "$work/us/ref.ax" <<'AX'
(import IO)

(:: optStr (-> Int (Option String)))

(fn (optStr n)
  (if (< n 0)
    None
    (Some "hit")
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println (match (optStr 1) ((Some s) s) ((None) "miss")))
    0
  }
)
AX
if ! "$axc" emit-llvm --input "$work/us/ref.ax" -o "$work/us/ref.ll" > "$work/us/ref.log" 2>&1; then
  bad "probe: the reference-payload variant did not compile"
  sed 's/^/     /' "$work/us/ref.log" | head -10
else
  ra="$(calls_in "$work/us/ref.ll" optStr axiom_alloc)"
  rp="$(grep -c '^define { i64, i64 }' "$work/us/ref.ll" || true)"
  if [[ "$ra" == "$REFUSED_ALLOC_EXPECT" ]] && (( rp == 0 )); then
    ok "probe: an (Option String) gets no pair variant and still builds $ra block - the counter reads the IR, and the reference restriction is live"
  else
    bad "probe: (Option String) built $ra block(s) and $rp pair variant(s), wanted $REFUSED_ALLOC_EXPECT and 0.
     A pair variant here would hand the consumer a payload with no
     refcount behind it, which is a use-after-free and not a speedup."
  fi
  if "$axc" build --input "$work/us/ref.ax" --output "$work/us/ref" > /dev/null 2>&1; then
    got="$("$work/us/ref" 2>&1 || true)"
    if [[ "$got" == "hit" ]]; then
      ok "probe: the refused shape still answers correctly"
    else
      bad "probe: the refused shape answers '$got', wanted 'hit'"
    fi
  else
    bad "probe: the refused shape did not build"
  fi
fi

# ------------------------------------------------------------------
echo
echo "== 4. negative probe: the count is anchored on one definition =="
# ------------------------------------------------------------------
# Section 2 reads `optFind$pair`; this proves that range is a
# definition and not the whole module.
# Its own emission: `build` above removes the `.ll` beside its output.
if ! "$axc" emit-llvm --input "$work/us/ref.ax" -o "$work/us/anchor.ll" > /dev/null 2>&1; then
  bad "probe: could not emit IR for the anchoring probe"
else
  aw="$(calls_in "$work/us/anchor.ll" optStr axiom_alloc)"
  an="$(calls_in "$work/us/anchor.ll" optStrAbsent axiom_alloc)"
  if (( aw > 0 )) && [[ "$an" == "0" ]]; then
    ok "probe: \`optStr\` reads $aw and a name with no definition reads $an, so the range is one definition"
  else
    bad "probe: \`optStr\` reads $aw and an absent name reads $an - the counter
     is not anchored on one definition, so section 2 is counting the module"
  fi
fi

echo
if (( failed > 0 )); then
  echo "check-unboxed-sums: $failed of $checks checks failed"
  exit 1
fi
echo "check-unboxed-sums: $checks checks - the answer is fixed, the blocks an"
echo "                    Option costs are the number on file, and both probes"
echo "                    show the counter can move and is anchored"
