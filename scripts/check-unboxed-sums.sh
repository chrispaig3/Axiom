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
#   2. THE COST IS WHAT IS ON FILE. `optFind` builds ALLOC_EXPECT
#      blocks and the matching consumer performs RELEASE_EXPECT
#      releases. Today both are 1: one `(Some ...)` construction, one
#      release at the match. When the specialisation of
#      `docs/unboxed-sums-design.md` section 4 lands, both become 0 for
#      the specialised path, and THIS LINE IS THE PROOF - the win is
#      asserted by a number in the module rather than by a stopwatch.
#
#   3. THE COUNTER READS THE IR. A variant of the fixture with a
#      SECOND construction must raise the count. Without this the two
#      numbers above could both be measuring an awk range that matched
#      nothing, which is this repository's most common defect: a check
#      that cannot fail.
#
#   4. THE COUNTER IS ANCHORED ON THE RIGHT FUNCTION. A variant whose
#      construction moves into a DIFFERENT function must leave
#      `optFind`'s count at zero rather than counting the whole module.
#      3 proves the counter can rise; this proves it is not simply
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

# The counts this tree's code generation produces. Both go to 0 when
# the register-pair specialisation lands; changing either without a
# change in `self_host/codegen.ax` is a representation regression.
ALLOC_EXPECT=1
RELEASE_EXPECT=1
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
  a="$(calls_in "$work/us/us.ll" optFind axiom_alloc)"
  r="$(calls_in "$work/us/us.ll" sum axiom_release)"
  if [[ "$a" == "$ALLOC_EXPECT" ]]; then
    ok "\`optFind\` builds $a heap block(s) per construction site"
  else
    bad "\`optFind\` builds $a heap block(s), the file says $ALLOC_EXPECT
     A DROP IS THE OPTIMISATION LANDING and a rise is a regression;
     either way this number is the claim, so move ALLOC_EXPECT in the
     same commit that moves the code generator, and not before."
  fi
  if [[ "$r" == "$RELEASE_EXPECT" ]]; then
    ok "the matching consumer performs $r release(s)"
  else
    bad "the matching consumer performs $r release(s), the file says $RELEASE_EXPECT"
  fi
fi

# ------------------------------------------------------------------
echo
echo "== 3. negative probe: a second construction must raise the count =="
# ------------------------------------------------------------------
# The instrument check. If `calls_in` matched nothing - a renamed
# symbol, an awk range that never opened - both numbers above would
# read 0 and look like a landed optimisation.
sed 's|    (Some (\* n 2))|    (if (> n 100) (Some (+ n 1)) (Some (* n 2)))|' \
  "$work/us/us.ax" > "$work/us/two.ax"
if ! grep -q '(Some (+ n 1))' "$work/us/two.ax"; then
  bad "probe: the second-construction edit did not apply - the fixture's shape has moved"
elif ! "$axc" emit-llvm --input "$work/us/two.ax" -o "$work/us/two.ll" > "$work/us/two.log" 2>&1; then
  bad "probe: the two-construction variant did not compile"
  sed 's/^/     /' "$work/us/two.log" | head -10
else
  a2="$(calls_in "$work/us/two.ll" optFind axiom_alloc)"
  if (( a2 > ALLOC_EXPECT )); then
    ok "probe: a second construction raises the count to $a2, so the counter reads the IR"
  else
    bad "probe: a second construction left the count at $a2 - \`calls_in\` is not
     reading what it claims to read, and checks 2's numbers assert nothing"
  fi
fi

# ------------------------------------------------------------------
echo
echo "== 4. negative probe: the count is anchored on optFind, not the module =="
# ------------------------------------------------------------------
# `optFind` answers a plain Int and allocates nothing; the construction
# moves to `optMake`. A counter reading the whole module would still
# report the module's constructions against `optFind`.
cat > "$work/us/moved.ax" <<'AX'
(import IO)

(:: optMake (-> Int (Option Int)))

(fn (optMake n)
  (if (< n 0)
    None
    (Some (* n 2))
  )
)

(:: optFind (-> Int Int))

(fn (optFind n) (+ n 1))

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println (+ (optFind 1) (match (optMake 3) ((Some v) v) ((None) 0))))
    0
  }
)
AX
if ! "$axc" emit-llvm --input "$work/us/moved.ax" -o "$work/us/moved.ll" > "$work/us/moved.log" 2>&1; then
  bad "probe: the moved-construction variant did not compile"
  sed 's/^/     /' "$work/us/moved.log" | head -10
else
  am="$(calls_in "$work/us/moved.ll" optFind axiom_alloc)"
  aw="$(calls_in "$work/us/moved.ll" optMake axiom_alloc)"
  if (( am == 0 && aw > 0 )); then
    ok "probe: with the construction moved, \`optFind\` reads 0 and \`optMake\` reads $aw"
  else
    bad "probe: \`optFind\` reads $am and \`optMake\` reads $aw - the counter is not
     anchored on one definition, so check 2 is counting the module"
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
