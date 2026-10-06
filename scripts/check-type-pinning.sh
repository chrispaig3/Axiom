#!/usr/bin/env bash
# Check that a bound type placeholder stays bound.
#
# `tyCompat` (self_host/typecheck.ax) pins an instantiation placeholder
# to the type it first meets. Without that, a let-bound container could
# take a different element type at each use:
#
#     (let ((v vecNew))
#       { (vecPush v 42) (needVec (vecGet v 0)) })
#
# `check` would accept that program, and it exits 139: an `Int` read
# back as a block header with no `cast` written anywhere. That is
# `AX3040`'s failure reached without `AX3040`'s coercion.
#
# The gate has two halves. A checker that refused everything would pass
# every refusal, so the accepted half keeps the refusals meaningful.
#
#   Refused, with AX3004:
#     1. one let-bound container written at `Int` and then at `String`
#     2. an element stored as `Int` and read back at a reference type
#
#   Accepted:
#     3. the same container used at one type throughout
#     4. a rigid source variable stays rigid and generic: `(-> a a Int)`
#        takes two of the same thing, at any type
#     5. pinning is per binding: two containers from one polymorphic
#        constructor may hold different element types in one scope. A
#        global substitution would pass every other check and fail this.
#
# Recursive equations are refused too. Leaving `a = Vec a` unrecorded
# while reporting a match would let a self-containing vector later become
# `Vec String`, so direct and indirect cycles must draw AX3004. Finite
# nesting and nominal recursive ADTs must still compile and run, so
# refusing every nested type cannot pass.
#
# Not checked here: an undeclared function used at two types. Inference
# without generalisation refuses that, independently of pinning.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# $1 name, $2 expect (refuse|accept|run-42), rest: source on stdin
probe() {
  local name="$1" expect="$2" src="$work/$1.ax"
  local rc
  cat > "$src"
  if "$axc" --diagnostic-format=ai check "$src" >"$work/$1.out" 2>&1; then
    if [[ "$expect" == accept ]]; then
      ok "$name: accepted, as it must be"
    elif [[ "$expect" == run-42 ]]; then
      "$axc" --diagnostic-format=ai run "$src" >"$work/$1.run" 2>&1
      rc=$?
      if [[ "$rc" == 42 ]]; then ok "$name: accepted and ran to 42"
      else bad "$name: runtime exit $rc, expected 42"; cat "$work/$1.run"; fi
    else bad "$name: ACCEPTED, and this shape is the unsoundness"; fi
  else
    rc=$?
    if [[ "$expect" == refuse && "$rc" == 1 ]] && grep -q '^E AX3004 ' "$work/$1.out"; then
      ok "$name: refused with AX3004"
    elif [[ "$expect" == refuse ]]; then
      bad "$name: exit $rc without the required type-mismatch diagnostic"
      cat "$work/$1.out"
    else bad "$name: refused, but this program is correct"
         head -2 "$work/$1.out" | sed 's/^/       /'; fi
  fi
}

echo "== the hole, which must be refused =="

probe two-types refuse <<'AX'
(data Box (a) (MkBox Int))
(:: emptyBox (Box a))
(fn (emptyBox) (MkBox 0))
(:: put (-> (Box a) a (Box a)))
(fn (put b x) b)
(fn (main)
  (let ((v emptyBox))
    {
      (put v 42)
      (put v "hi")
      0
    }
  )
)
AX

probe read-back refuse <<'AX'
(data Box (a) (MkBox Int))
(:: emptyBox (Box a))
(fn (emptyBox) (MkBox 0))
(:: put (-> (Box a) a (Box a)))
(fn (put b x) b)
(:: peek (-> (Box a) a))
;@axiom:effect(unsafe)
(fn (peek b) (cast a 0))
(:: needStr (-> String Int))
(fn (needStr s) 0)
(fn (main)
  (let ((v emptyBox))
    {
      (put v 42)
      (needStr (peek v))
    }
  )
)
AX

echo
probe self-containing-vector refuse <<'AX'
(import Vec)
(import Str)
(fn (main)
  (let ((v vecNew))
    {
      (vecPush v v)
      (vecPush v "hello")
      (strLen (vecGet v 0))
    }))
AX

probe mutually-containing-vectors refuse <<'AX'
(import Vec)
(import Str)
(fn (main)
  (let ((a vecNew) (b vecNew))
    {
      (vecPush a b)
      (vecPush b a)
      (vecPush b "hello")
      (strLen (vecGet b 0))
    }))
AX

echo "== what pinning must NOT break =="

probe one-type accept <<'AX'
(data Box (a) (MkBox Int))
(:: emptyBox (Box a))
(fn (emptyBox) (MkBox 0))
(:: put (-> (Box a) a (Box a)))
(fn (put b x) b)
(fn (main)
  (let ((v emptyBox))
    {
      (put v 1)
      (put v 2)
      0
    }
  )
)
AX

probe rigid-var accept <<'AX'
(:: same (-> a a Int))
(fn (same x y) 0)
(fn (main)
  {
    (same 1 2)
    (same "a" "b")
    0
  }
)
AX

probe per-binding accept <<'AX'
(data Box (a) (MkBox Int))
(:: emptyBox (Box a))
(fn (emptyBox) (MkBox 0))
(:: put (-> (Box a) a (Box a)))
(fn (put b x) b)
(fn (main)
  (let (
    (ints emptyBox)
    (strs emptyBox)
  )
    {
      (put ints 1)
      (put strs "s")
      0
    }
  )
)
AX

echo
probe finite-nested-vectors run-42 <<'AX'
(import Vec)
(import Str)
(fn (main)
  (let ((strings vecNew) (nested vecNew) (ints vecNew))
    {
      (vecPush strings "hello")
      (vecPush nested strings)
      (vecPush ints 37)
      (+ (strLen (vecGet (vecGet nested 0) 0)) (vecGet ints 0))
    }))
AX

probe nominal-recursive-data run-42 <<'AX'
(import Vec)
(data Tree () (Leaf Int) (Branch (Vec Tree)))
(:: total (-> Tree Int))
(fn (total t)
  (match t
    ((Leaf n) n)
    ((Branch children) (total (vecGet children 0)))))
(fn (main)
  (let ((children vecNew))
    {
      (vecPush children (Leaf 42))
      (total (Branch children))
    }))
AX

echo
if (( failed == 0 )); then
  echo "check-type-pinning: $checks checks - a bound placeholder stays bound"
  exit 0
fi
echo "check-type-pinning: $failed of $((checks + failed)) checks failed"
exit 1
