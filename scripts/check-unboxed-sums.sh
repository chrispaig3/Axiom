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
# What a REFUSED shape still costs. A scrutinee that is not a DIRECT
# call - here a `let`-bound one - keeps the boxed path, which is what
# proves `calls_in` can read a nonzero count at all.
REFUSED_ALLOC_EXPECT=1
# Bytes the arena bump may move over 20,000 iterations of each
# reference-carrying loop. A leaked payload is 32 bytes and up per
# iteration, so a real leak is megabytes and this bound is not close.
ARENA_BOUND=4096
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
echo "== 3. a REFERENCE payload, and a Result: specialised, and no leak =="
# ------------------------------------------------------------------
# The two shapes the first slice refused. `(Option String)` carries a
# share the block used to own; `(Result Int Error)` carries a MACHINE
# WORD in one arm and a share in the other, so the release belongs to
# the arm and not to the match.
#
# The arena mark is the instrument (`tests/stdlib/370-error-propagation.ax`
# uses the same cell: word 0 is the bump, word 2 is the chunk). A
# leaked payload is 32 bytes and up per iteration, so 20,000
# iterations of each would move megabytes; the bound below is 4096 and
# the measured figure is ~208. A chunk crossing answers -1 and fails,
# because a flat line through a moved chunk would be unmeasurable.
cat > "$work/us/ref.ax" <<'AX'
(import IO)

(import Str)

(import Fmt)

(import Err)

(import Mem)

(:: nameOf (-> Int (Option String)))

(fn (nameOf n)
  (if (== (% n 3) 0)
    None
    (Some (strConcat "n" (fmtInt n)))
  )
)

(:: half (-> Int (Result Int Error)))

(fn (half n)
  (if (== (% n 2) 0)
    (Ok (/ n 2))
    (Err (mkError 7 "odd"))
  )
)

(:: loopOpt (-> Int Int Int Int))

(fn (loopOpt i n acc)
  (if (>= i n)
    acc
    (loopOpt (+ i 1) n (+ acc (match (nameOf i) ((Some s) (strLen s)) ((None) 0))))
  )
)

(:: loopRes (-> Int Int Int Int))

(fn (loopRes i n acc)
  (if (>= i n)
    acc
    (loopRes (+ i 1) n (+ acc (match (half i) ((Ok v) v) ((Err e) (errCode e)))))
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let (
    (a1 (memGetWord __axiom_arena_mark 0))
    (c1 (memGetWord __axiom_arena_mark 2))
    (s1 (loopOpt 0 20000 0))
    (s2 (loopRes 0 20000 0))
    (a2 (memGetWord __axiom_arena_mark 0))
    (c2 (memGetWord __axiom_arena_mark 2))
  )
    {
      (println s1)
      (println s2)
      (println (if (== c1 c2) (- a2 a1) (- 0 1)))
      0
    }
  )
)
AX
if ! "$axc" emit-llvm --input "$work/us/ref.ax" -o "$work/us/ref.ll" > "$work/us/ref.log" 2>&1; then
  bad "the reference/Result fixture did not compile"
  sed 's/^/     /' "$work/us/ref.log" | head -10
else
  np="$(grep -c '^define { i64, i64 }' "$work/us/ref.ll" || true)"
  if (( np == 2 )); then
    ok "both \`nameOf\` and \`half\` get a register-pair variant"
  else
    bad "$np pair variant(s) for a reference payload and a Result, wanted 2"
  fi
  # `Err`'s payload is a share and `Ok`'s is a word, so exactly ONE of
  # the two arms may release. Releasing both is a wild read of an Int.
  hr="$(calls_in "$work/us/ref.ll" loopRes axiom_release)"
  if (( hr == 1 )); then
    ok "the Result consumer releases on one arm only - \`Err\`'s share, not \`Ok\`'s word"
  else
    bad "the Result consumer emits $hr release(s), wanted 1: releasing \`Ok\`'s
     machine word would hand axiom_release an Int above 4096 and it
     would read it as a block header"
  fi
fi

if "$axc" build --opt 2 --input "$work/us/ref.ax" --output "$work/us/ref" > /dev/null 2>&1; then
  # No `mapfile`: the macOS runner ships bash 3.2, which is why
  # `gate_prose_docs_abs` is a function rather than a `mapfile` too.
  "$work/us/ref" > "$work/us/ref.out" 2>&1 || true
  r0="$(sed -n '1p' "$work/us/ref.out")"
  r1="$(sed -n '2p' "$work/us/ref.out")"
  moved="$(sed -n '3p' "$work/us/ref.out")"
  if [[ "$r0" == "72594" && "$r1" == "50065000" ]]; then
    ok "both loops answer what they answered boxed"
  else
    bad "the loops answer '$r0' and '$r1', wanted 72594 and 50065000"
  fi
  if [[ "$moved" =~ ^[0-9]+$ ]] && (( moved < ARENA_BOUND )); then
    ok "the arena moved $moved bytes over 40,000 iterations - the shares are given back"
  else
    bad "the arena moved '$moved' bytes (bound $ARENA_BOUND, -1 means the chunk
     changed and the measurement is not flat). A payload retained and
     not released, or released twice, shows here first."
  fi
else
  bad "the reference/Result fixture did not build"
fi

# ------------------------------------------------------------------
echo
echo "== 4. negative probe: a scrutinee that is not a direct call still boxes =="
# ------------------------------------------------------------------
# The instrument check. If `calls_in` matched nothing, section 2's
# zeroes would read 0 for that reason rather than for the
# optimisation. A `let`-bound scrutinee is outside the rewrite, so it
# must still build a block.
cat > "$work/us/indirect.ax" <<'AX'
(import IO)

(:: optFind (-> Int (Option Int)))

(fn (optFind n)
  (if (< n 0)
    None
    (Some (* n 2))
  )
)

(:: viaLet (-> Int Int))

(fn (viaLet n)
  (let ((r (optFind n)))
    (match r
      ((Some v) v)
      ((None) 0)
    )
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println (viaLet 21))
    0
  }
)
AX
if ! "$axc" emit-llvm --input "$work/us/indirect.ax" -o "$work/us/indirect.ll" > /dev/null 2>&1; then
  bad "probe: the let-bound-scrutinee variant did not compile"
else
  ia="$(calls_in "$work/us/indirect.ll" optFind axiom_alloc)"
  if [[ "$ia" == "$REFUSED_ALLOC_EXPECT" ]]; then
    ok "probe: a let-bound scrutinee keeps the boxed path and builds $ia block - the counter reads the IR"
  else
    bad "probe: the boxed path built $ia block(s), wanted $REFUSED_ALLOC_EXPECT"
  fi
  in0="$(calls_in "$work/us/indirect.ll" optFindAbsent axiom_alloc)"
  if [[ "$in0" == "0" ]]; then
    ok "probe: a name with no definition reads 0, so the range is one definition"
  else
    bad "probe: an absent name reads $in0 - the counter is not anchored"
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
