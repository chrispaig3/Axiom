#!/usr/bin/env bash
# Count what an `Option` costs in the emitted IR.
#
# A boxed `(Some v)` is a 16-byte heap block (`axiom_alloc`, a shape
# word, a tag, a refcount and the field) that the consumer reads back
# and hands to `axiom_release`. The register-pair lowering described in
# `docs/error-model.md` returns `{tag, payload}` instead. This gate
# counts `axiom_alloc` calls for fixtures with a known number of matched
# lookups, with a probe that forces the boxed path and must move the
# count.
#
# A count, not a timing: a wall-clock bound on a shared runner is flaky
# (see `bench-compile.sh`), while the number of heap blocks is an exact
# property of the emitted module. A timing gate would go red on a noisy
# runner and stay green on a representation regression.
#
# Each section asserts one thing, and its comment gives the detail:
#
#   1. Behaviour is fixed: the fixture answers 249500 at `--opt` 0, 1
#      and 2. A faster wrong answer is not the goal.
#   2. The specialisation happened, and then it is free: the
#      `{ i64, i64 }` variant exists and the match calls it once, the
#      variant builds ALLOC_EXPECT blocks, and the consumer performs
#      RELEASE_EXPECT releases. Existence is checked first, because a
#      function that was never emitted also builds no blocks.
#   3. A reference payload and a `Result` specialise too, and give their
#      shares back.
#  3b. A match in tail position specialises too.
#   4. A scrutinee that is not a direct call is boxed in the caller,
#      which also proves `calls_in` reads the IR.
#   5. `restrict(no-alloc)` holds for the function and is refused
#      (AX3049) on a caller that boxes.
#   6. The checker's unboxing test agrees with the emitter's over the
#      compiler itself.
#
# The fixtures live here in heredocs, not under `tests/`. Several gates
# carry population counts over `tests/selfhost/`, so a fixture only this
# gate reads would move numbers in gates with nothing to say about it.
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

# Blocks the pair variant builds, and releases its matching consumer
# performs. A rise is a representation regression.
ALLOC_EXPECT=0
RELEASE_EXPECT=0
# Blocks a `let`-bound scrutinee costs, built in the caller's own
# definition. The boxing wrapper `@optFind` builds one too.
BOX_IN_CALLER_EXPECT=1
# Bytes the arena bump may move over 20,000 iterations of each
# reference-carrying loop. A leaked payload is 32 bytes or more per
# iteration, so a real leak moves megabytes, far past this bound.
ARENA_BOUND=4096
GOLDEN=249500

mkdir -p "$work/us"

# `optFind` is the canonical absence shape: a guard, a `None` and a
# `(Some e)`, the form of `internFind`, `pathLastSlash` and similar
# lookups. `sum` matches the direct call, the only site shape the
# specialisation rewrites.
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
# closing brace, so a call in a neighbouring function is not counted.
# Check 4 proves the anchoring holds.
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
  # First, that the specialisation happened at all. A function that was
  # never emitted would also satisfy the two zeroes below.
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
# `(Option String)` carries a share. `(Result Int Error)` carries a
# machine word in one arm and a share in the other, so the release
# belongs to the arm, not the match.
#
# The arena mark is the instrument (`tests/stdlib/370-error-propagation.ax`
# uses the same cell: word 0 is the bump, word 2 is the chunk). A leaked
# payload is 32 bytes or more per iteration, so 20,000 iterations of
# each would move megabytes against a bound of 4096. A chunk crossing
# answers -1 and fails, because a moved chunk makes the figure
# meaningless.
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
    (Some (concat "n" (fmtInt n)))
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
  # By name. A count of every pair variant in the module includes the
  # standard library's, such as `sysResult`, which change shape for
  # reasons unrelated to this fixture.
  if grep -q '^define { i64, i64 } @nameOf\$pair(' "$work/us/ref.ll" \
     && grep -q '^define { i64, i64 } @half\$pair(' "$work/us/ref.ll"; then
    ok "both \`nameOf\` and \`half\` get a register-pair variant"
  else
    bad "a pair variant is missing for a reference payload or a Result"
  fi
  # `Err`'s payload is a share and `Ok`'s is a word, so exactly one of
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
  # Read the lines with `sed`, not `mapfile`: the macOS runner ships
  # bash 3.2.
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
echo "== 3b. a match in TAIL position specialises too =="
# ------------------------------------------------------------------
# `emitMatch` and `emitMatchTail` are separate emitters, and each needs
# the hook. A match that is a function's tail goes through the second,
# which section 3 cannot see because its match sits inside an argument.
#
# The tail hook is armed only where `scrutineeReleasable` answers 0. An
# arm in tail position may emit its own `ret`, so a release after the
# arms would be unreachable: a leak with no diagnostic. Skipping that
# case is simpler than tracking which arms fall through, and every
# `Option Int` lookup in the tree qualifies.
cat > "$work/us/tail.ax" <<'AX'
(import IO)

(:: look (-> Int (Option Int)))

(fn (look n)
  (if (< n 0)
    None
    (Some (* n 3))
  )
)

(:: viaTail (-> Int Int))

(fn (viaTail n)
  (match (look n)
    ((Some v) v)
    ((None) 0)
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println (+ (viaTail 5) (viaTail (- 0 2))))
    0
  }
)
AX
if ! "$axc" emit-llvm --input "$work/us/tail.ax" -o "$work/us/tail.ll" > /dev/null 2>&1; then
  bad "the tail-position fixture did not compile"
else
  ta="$(calls_in "$work/us/tail.ll" 'look\$pair' axiom_alloc)"
  tc="$(calls_in "$work/us/tail.ll" viaTail 'call { i64, i64 } @look$pair')"
  if grep -q '^define { i64, i64 } @look\$pair(' "$work/us/tail.ll" \
     && [[ "$ta" == "0" ]] && [[ "$tc" == "1" ]]; then
    ok "a match in tail position specialises: \`viaTail\` calls the pair, and the variant builds $ta blocks"
  else
    bad "tail position: variant present=$(grep -c '^define { i64, i64 } @look\$pair(' "$work/us/tail.ll" || true), $ta block(s), $tc pair call(s) from viaTail, wanted 1, 0 and 1 -
     \`emitMatchTail\` is a second emitter and needs its own hook"
  fi
fi
if "$axc" build --opt 2 --input "$work/us/tail.ax" --output "$work/us/tail" > /dev/null 2>&1; then
  tg="$("$work/us/tail" 2>&1 || true)"
  if [[ "$tg" == "15" ]]; then
    ok "the tail-position fixture answers 15"
  else
    bad "the tail-position fixture answers '$tg', wanted 15"
  fi
else
  bad "the tail-position fixture did not build"
fi

echo
echo "== 4. negative probe: a scrutinee that is not a direct call is boxed, in the caller =="
# ------------------------------------------------------------------
# The instrument check. If `calls_in` matched nothing, section 2's
# zeroes would read 0 for that reason alone. A `let`-bound scrutinee is
# outside the rewrite, so a block is still built, at the call in
# `viaLet`, where the checker charges it. The callee's body
# (`optFind$pair`) builds none on any path, and `@optFind` is the boxing
# wrapper a bare reference reaches.
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
  ia="$(calls_in "$work/us/indirect.ll" viaLet axiom_alloc)"
  ip="$(calls_in "$work/us/indirect.ll" 'optFind\$pair' axiom_alloc)"
  if [[ "$ia" == "$BOX_IN_CALLER_EXPECT" && "$ip" == "0" ]]; then
    ok "probe: a let-bound scrutinee is boxed in the CALLER ($ia block in viaLet, $ip in the variant) - the counter reads the IR"
  else
    bad "probe: viaLet builds $ia block(s), optFind\$pair $ip; wanted $BOX_IN_CALLER_EXPECT and 0"
  fi
  in0="$(calls_in "$work/us/indirect.ll" optFindAbsent axiom_alloc)"
  if [[ "$in0" == "0" ]]; then
    ok "probe: a name with no definition reads 0, so the range is one definition"
  else
    bad "probe: an absent name reads $in0 - the counter is not anchored"
  fi
fi

# The wrapper. An unreferenced wrapper is pruned like any unreferenced
# definition, so `applyIt` takes `optFind` as a value: the module keeps
# `@optFind`, and a call through the value boxes there.
cat > "$work/us/value.ax" <<'AX'
(import IO)

(:: optFind (-> Int (Option Int)))

(fn (optFind n)
  (if (< n 0)
    None
    (Some (* n 2))
  )
)

(:: applyIt (-> (-> Int (Option Int)) Int Int))

(fn (applyIt f n)
  (match (f n)
    ((Some v) v)
    ((None) 0)
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println (applyIt optFind 21))
    0
  }
)
AX
if ! "$axc" emit-llvm --input "$work/us/value.ax" -o "$work/us/value.ll" > /dev/null 2>&1; then
  bad "probe: the function-as-a-value fixture did not compile"
else
  vw="$(calls_in "$work/us/value.ll" optFind axiom_alloc)"
  vp="$(calls_in "$work/us/value.ll" 'optFind\$pair' axiom_alloc)"
  if grep -q '^define i64 @optFind(' "$work/us/value.ll" && [[ "$vw" == "1" && "$vp" == "0" ]]; then
    ok "probe: named as a value, \`@optFind\` is the boxing wrapper - $vw block there, $vp in the variant"
  else
    bad "probe: the wrapper reads $vw block(s) and the variant $vp, wanted 1 and 0 (wrapper present: $(grep -c '^define i64 @optFind(' "$work/us/value.ll" || true))"
  fi
fi

echo
echo "== 5. the no-alloc claim: the function keeps it, the boxing caller pays =="
# ------------------------------------------------------------------
# Three claims on one file, and `check` must answer each differently.
# `look` is the pair shape and allocates nothing on any path; `direct`
# matches it and reads registers; `stored` lets it outlive the match
# and is where the block is built. The row `symbols` prints must say
# the same, because AX3049 is decided from that row.
cat > "$work/us/claim.ax" <<'AX'
(import IO)

;@axiom:restrict(no-alloc)
(:: look (-> Int (Option Int)))

(fn (look n)
  (if (< n 0)
    None
    (Some (* n 3))
  )
)

;@axiom:restrict(no-alloc)
(:: direct (-> Int Int))

(fn (direct n)
  (match (look n)
    ((Some v) (+ v 1))
    ((None) 0)
  )
)

;@axiom:restrict(no-alloc)
(:: stored (-> Int Int))

(fn (stored n)
  (let ((r (look n)))
    (match r
      ((Some v) (+ v 1))
      ((None) 0)
    )
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println (+ (direct 4) (stored 5)))
    0
  }
)
AX
"$axc" check "$work/us/claim.ax" > "$work/us/claim.log" 2>&1 || true
if grep -q 'AX3049.*`stored`' "$work/us/claim.log" \
   && ! grep -q 'AX3049.*`look`' "$work/us/claim.log" \
   && ! grep -q 'AX3049.*`direct`' "$work/us/claim.log"; then
  ok "check: \`look\` and \`direct\` keep no-alloc, \`stored\` is refused (AX3049) - the box is its"
else
  bad "check answered the three no-alloc claims wrongly:"
  grep 'AX3049' "$work/us/claim.log" | sed 's/^/     /' | head -6
fi
"$axc" symbols --diagnostic-format=ai "$work/us/claim.ax" > "$work/us/claim.syms" 2>/dev/null || true
rl="$(grep '^F look ' "$work/us/claim.syms" | grep -c '#effects=[^ ]*Alloc' || true)"
rs="$(grep '^F stored ' "$work/us/claim.syms" | grep -c '#effects=[^ ]*Alloc' || true)"
rd="$(grep '^F direct ' "$work/us/claim.syms" | grep -c '#effects=[^ ]*Alloc' || true)"
if [[ "$rl" == "0" && "$rd" == "0" && "$rs" == "1" ]]; then
  ok "symbols: no Alloc on \`look\` or \`direct\`, Alloc on \`stored\` - the row says where the block is"
else
  bad "symbols: Alloc on look=$rl direct=$rd stored=$rs, wanted 0, 0 and 1"
fi
# The IR must agree with the row, function by function. Emit from a copy
# without the claims: `stored`'s refusal is an error, and a program with
# an error emits nothing.
sed '/^;@axiom:restrict/d' "$work/us/claim.ax" > "$work/us/claim-untagged.ax"
if "$axc" emit-llvm --input "$work/us/claim-untagged.ax" -o "$work/us/claim.ll" > /dev/null 2>&1; then
  cl="$(calls_in "$work/us/claim.ll" 'look\$pair' axiom_alloc)"
  cd_="$(calls_in "$work/us/claim.ll" direct axiom_alloc)"
  cs="$(calls_in "$work/us/claim.ll" stored axiom_alloc)"
  if [[ "$cl" == "0" && "$cd_" == "0" && "$cs" == "1" ]]; then
    ok "IR: look\$pair $cl, direct $cd_, stored $cs block(s) - each definition matches its row"
  else
    bad "IR: look\$pair $cl, direct $cd_, stored $cs block(s), wanted 0, 0 and 1"
  fi
else
  bad "the claim fixture did not emit"
fi

# ------------------------------------------------------------------
echo
echo "== 6. the checker's mirror against the emitter, over the compiler itself =="
# ------------------------------------------------------------------
# Every function the compiler compiles into itself, checked by
# `scripts/lib/alloc-rows.py`: a row without `Alloc` names a definition
# without `axiom_alloc`. The two predicates that decide which functions
# are unboxed live in two files (`pairFnOK`, `tcPairFnOK`), and this
# checks they have not drifted.
if "$axc" emit-llvm --input "$repo_root/self_host/main.ax" -o "$work/us/self.ll" > "$work/us/self.log" 2>&1 \
   && "$axc" symbols --diagnostic-format=ai "$repo_root/self_host/main.ax" > "$work/us/self.syms" 2>/dev/null; then
  if out="$(python3 "$repo_root/scripts/lib/alloc-rows.py" "$work/us/self.syms" "$work/us/self.ll" 2>&1)"; then
    ok "self-compile: $out"
  else
    bad "self-compile: a row and its definition disagree about Alloc:"
    echo "$out" | sed 's/^/     /' | head -12
  fi
else
  bad "could not emit IR and rows for self_host/main.ax"
fi

echo
if (( failed > 0 )); then
  echo "check-unboxed-sums: $failed of $checks checks failed"
  exit 1
fi
echo "check-unboxed-sums: $checks checks - the answer is fixed, the blocks an"
echo "                    Option costs are the number on file, the box is the"
echo "                    caller's, and the checker's mirror agrees with the emitter"
