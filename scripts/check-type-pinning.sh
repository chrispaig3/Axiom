#!/usr/bin/env bash
# A PLACEHOLDER THAT IS BOUND STAYS BOUND.
#
# `tyCompat` compared types and recorded nothing, so a minted
# placeholder matched anything and went on matching anything. For a
# value read once that is a sound under-approximation - the file said
# so, "under-report, never mis-report". For a value BOUND and then
# used twice it is not, and a container is exactly that:
#
#     (let ((v vecNew))
#       { (vecPush v 42) (needVec (vecGet v 0)) })
#
# Each `vecPush` matched its OWN fresh placeholder, the `let`'s was
# never pinned, and `check` answered OK for a program that exits 139 -
# an `Int` read back as a block header with NO `cast` written
# anywhere. That is `AX3040`'s own failure reached without `AX3040`'s
# coercion.
#
# WHAT THIS GATE ASSERTS, and why it is in two halves. A checker that
# refused everything would pass every refusal below, so the accepted
# half is not decoration: it is what keeps the refusals meaningful.
#
#   REFUSED - the hole, in both shapes:
#     1. one let-bound container written at `Int` and then at `String`
#     2. an element stored as `Int` and read back at a reference type
#
#   ACCEPTED - what pinning must not break:
#     3. the same container used at ONE type throughout
#     4. a rigid source variable is still rigid, and still generic:
#        `(-> a a Int)` takes two of the same thing, at any type
#     5. PINNING IS PER BINDING, not global: two containers from the
#        same polymorphic constructor may be pinned to DIFFERENT
#        element types in one scope. A global substitution would pass
#        every other check here and fail this one.
#
# Together those are the four obligations the patch names, checked
# from the outside: only an instantiation placeholder binds (4), the
# binding follows the BINDING and not the program (5), and it is what
# closes 1 and 2.
#
# NOT asserted here, deliberately: that an UNDECLARED function may be
# used at two types. It may not, and it could not before pinning
# either - `(fn (untyped x) x)` applied to an `Int` and a `String` is
# refused by both compilers. That is a pre-existing rule about
# inference without generalisation, and writing it down here as
# though pinning caused it would be a false attribution.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# $1 name, $2 expect (refuse|accept), rest: source on stdin
probe() {
  local name="$1" expect="$2" src="$work/$1.ax"
  cat > "$src"
  if "$axc" check "$src" >"$work/$1.out" 2>&1; then
    if [[ "$expect" == accept ]]; then ok "$name: accepted, as it must be"
    else bad "$name: ACCEPTED, and this shape is the unsoundness"; fi
  else
    if [[ "$expect" == refuse ]]; then ok "$name: refused"
    else bad "$name: refused, but this program is correct"
         sed 's/\x1b\[[0-9;]*m//g' "$work/$1.out" | grep -E "^error|expected" | head -2 | sed 's/^/       /'; fi
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
if (( failed == 0 )); then
  echo "check-type-pinning: $checks checks - a bound placeholder stays bound"
  exit 0
fi
echo "check-type-pinning: $failed of $((checks + failed)) checks failed"
exit 1
