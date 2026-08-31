#!/usr/bin/env bash
# THE FALLIBLE-CALL RECLAMATION GATE (docs/error-model.md ERR-MEM-4).
#
# `tests/stdlib/370-error-propagation.ax` term 32 asserts that the
# block a fallible call answers is reclaimed - 20,000 calls, matched
# directly and let-bound alike, moving the bump less than one probe
# gap. `run-stdlib-tests.sh` runs it on every push. So why a second
# gate?
#
# Because that term is a FLAT LINE, and this repository's standing rule
# is that a flat line also reads flat when the measurement is broken.
# Term 64 answers half of that from inside the fixture - 2000 Strings
# allocated and kept must move the same probe pair - which proves the
# INSTRUMENT works. It cannot prove that the COMPILER is what makes
# term 32 flat, because nothing in the fixture can change the compiler.
#
# This gate can. It takes the one word the fix turns on, turns it off,
# rebuilds the compiler from the ablated tree, and requires the fixture
# to go red - at term 32 exactly, and at no other term.
#
#   `binderIsScalar` in self_host/codegen.ax answers whether the
#   checker stamped a match arm's binder with a machine-scalar type.
#   The ablation is `(if (== t 0)` -> `(if (>= t 0)`: every binder
#   answers "not a scalar", which is what the compiler believed before
#   2026-08-25 because it had no stamp to read.
#
# Measured 2026-08-25 on darwin-aarch64:
#
#   built from the tree      370 exits 127   probe delta 32 bytes
#   built from the ablation  370 exits  95   probe delta 640,032 bytes
#
# 640,000 is 32 bytes x 20,000 calls, which is ERR-MEM-4's number to
# the byte and is what says the ablation restores the defect rather
# than merely breaking something.
#
# WHY THE EXIT STATUS IS COMPARED TERM BY TERM. An ablated compiler
# that miscompiled the fixture outright would also fail it, and would
# look identical to a gate that only asked "did it go red". 127 - 95 is
# 32 and only 32: terms 1, 2, 4, 8, 16 and 64 must all still pass under
# the ablation, so the one thing that moved is the one thing ablated.
#
# Cost: one extra compiler build, ~16s. `gate_build_axc`'s cache does
# not apply to it - the ablated tree hashes differently by design.
#
# Usage:
#   scripts/check-fallible-reclaim.sh
#   AXIOM=path/to/compiler scripts/check-fallible-reclaim.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

fixture="$repo_root/tests/stdlib/370-error-propagation.ax"
want="$(tr -d '[:space:]' < "$repo_root/tests/stdlib/370-error-propagation.exit")"

# The fixture's own exit status IS its report: a bitmask, one bit per
# term. Running it needs no golden here because `.exit` is the golden.
run_fixture() {  # <compiler> -> exit status
  local out
  out="$work/run.$$"
  ( "$1" run "$fixture" ) >"$out" 2>&1
  printf '%s' "$?"
}

# --------------------------------------------------------------------
echo "== the tree as it stands reclaims it =="
# --------------------------------------------------------------------
rc="$(run_fixture "$axc")"
if [[ "$rc" == "$want" ]]; then
  ok "370-error-propagation exits $rc - every term, including 32"
else
  bad "370-error-propagation exits $rc, wanted $want"
  echo "     the compiler under test is $axc"
fi

# --------------------------------------------------------------------
echo
echo "== and one word is what does it =="
# --------------------------------------------------------------------
# The ablation is applied to a COPY of the tree, so a gate that dies
# half way through cannot leave the repository holding it. That is not
# hypothetical tidiness: `gate_source_stamp` hashes `self_host/`, so an
# ablation left behind would silently become the tree every later gate
# builds from.
abl="$work/tree"
mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/" || {
  echo "FAIL: could not copy the tree to ablate" >&2; exit 1; }

target="$abl/self_host/codegen.ax"
before="$(grep -c '(if (== t 0)' "$target")"
if (( before < 1 )); then
  bad "binderIsScalar's guard is not where this gate expects it"
  echo "     nothing was ablated, so the red half of this gate proves nothing"
else
  # Anchored on the function, not on the string: `(if (== t 0)` is a
  # common enough shape that a bare substitution would edit whatever
  # else happened to match first.
  python3 - "$target" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = """(pub fn (binderIsScalar n)
  (let ((t (nodeBinderTy n)))
    (if (== t 0)
      0"""
new = """(pub fn (binderIsScalar n)
  (let ((t (nodeBinderTy n)))
    (if (>= t 0)
      0"""
if s.count(old) != 1:
    sys.stderr.write("binderIsScalar not found verbatim (%d matches)\n" % s.count(old))
    sys.exit(1)
open(p, "w").write(s.replace(old, new))
PY
  if (( $? != 0 )); then
    bad "could not ablate binderIsScalar"
  else
    echo "-- rebuilding the compiler from the ablated tree --"
    if AXIOM_STDLIB="$abl/stdlib" "$axiom" build "$abl/self_host/main.ax" \
         -o "$work/axc-ablated" >"$work/ablated.build.log" 2>&1; then
      rc_abl="$(run_fixture "$work/axc-ablated")"
      if [[ "$rc_abl" == "$want" ]]; then
        bad "the ablated compiler still exits $rc_abl - term 32 cannot fail"
      elif (( (want - rc_abl) == 32 )); then
        ok "the ablated compiler exits $rc_abl - term 32 and nothing else"
      else
        bad "the ablated compiler exits $rc_abl; wanted $((want - 32))"
        echo "     $want - $rc_abl = $((want - rc_abl)), so a term other than"
        echo "     32 moved and the ablation is not isolated"
      fi
    else
      bad "the ablated compiler did not build"
      sed 's/^/     /' "$work/ablated.build.log" | head -20
    fi
  fi
fi

# --------------------------------------------------------------------
echo
echo "== and nothing in the tree reaches the disagreeing stamp =="
# --------------------------------------------------------------------
# THIS HALF USED TO ASSERT THE OPPOSITE, and the change is a finding,
# not a weakening. Read it before touching it.
#
# `stampPatBinderTy` writes a binder node's resolved type so codegen
# can tell a machine scalar - which cannot alias the block it was
# copied out of - from a reference, which can (docs/error-model.md
# ERR-MEM-4). The stamp has three states: 0, a NAME, and the empty
# string for "two checks disagreed", which reads back conservative.
# The third exists because a binder node can in principle be checked
# more than once at DIFFERENT types, and last-write-wins would hand
# codegen an `Int` for a binder that is really a `String` - not a
# leak, a release of a block the binder still points into.
#
# Until traits were removed there was exactly one way to reach it: a
# trait DEFAULT body, which `checkImplComplete` synthesized into every
# impl that omitted the method WITHOUT copying the body's nodes, so
# two impls at two types checked one AST. That path is gone with the
# construct, and `373-shared-default-binder` - the fixture that
# exercised it - was removed with the traits it was written in.
#
# MEASURED 2026-08-31, before this half was rewritten, by building the
# last-write-wins compiler and diffing emitted IR against the tree's:
#
#   278 fixtures under tests/stdlib, tests/selfhost, tests/frontend
#   every module in stdlib/
#   self_host/main.ax - the whole 60k-line compiler
#
# BYTE-IDENTICAL, all of it. Nothing Axiom can currently express
# checks one pattern binder twice at two types, so the old assertion
# ("last-write-wins puts a release back") had become a check that
# cannot fail - the defect this repository refuses most often.
#
# So the claim is inverted and stated as what is actually true: the
# arm is retained as a conservative guard, and this half proves the
# tree does not depend on it. If a future feature re-introduces
# one-AST-two-type-environments - a generic body re-checked per
# instantiation, an effect handler lowered per operation - this goes
# RED, and whoever did it decides deliberately whether the arm is
# load-bearing again rather than finding out from a use-after-free.
#
# The subject is `self_host/main.ax` rather than a fixture on purpose:
# it is the largest and most varied Axiom program in existence, and a
# fixture written to reach a path nothing reaches would be a fixture
# written to pass.
abl2="$work/tree2"
mkdir -p "$abl2"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl2/" || {
  echo "FAIL: could not copy the tree to ablate" >&2; exit 1; }

if python3 "$repo_root/scripts/lib/ablate-poison-arm.py" "$abl2/self_host/typecheck.ax"; then
  echo "-- rebuilding the compiler with a last-write-wins stamp --"
  if AXIOM_STDLIB="$abl2/stdlib" "$axiom" build "$abl2/self_host/main.ax" \
       -o "$work/axc-lww" >"$work/lww.build.log" 2>&1; then

    # The sweep. `emit-llvm` and not `build`, so the comparison is of
    # what the checker handed codegen and not of anything the linker
    # chose.
    differ=0; swept=0; empty=0
    for f in "$repo_root"/self_host/main.ax "$repo_root"/stdlib/*.ax; do
      a="$("$axc"          emit-llvm "$f" 2>/dev/null | shasum | cut -d' ' -f1)"
      b="$("$work/axc-lww" emit-llvm "$f" 2>/dev/null | shasum | cut -d' ' -f1)"
      swept=$((swept + 1))
      if [[ -z "$a" ]]; then
        empty=$((empty + 1))
        continue
      fi
      if [[ "$a" != "$b" ]]; then
        differ=$((differ + 1))
        echo "     reaches it: ${f#"$repo_root"/}"
      fi
    done

    # An emit that produced NOTHING compares equal to another emit that
    # produced nothing, so a sweep that silently emitted nothing would
    # report perfect agreement. Counted and refused rather than trusted.
    if (( empty > 0 )); then
      bad "$empty of $swept subjects emitted no IR - the sweep is comparing silence"
    elif (( swept < 2 )); then
      bad "swept $swept subject(s) - the glob stopped matching"
    elif (( differ > 0 )); then
      bad "$differ of $swept subjects change under last-write-wins"
      echo "     Something now checks one pattern binder twice at two types."
      echo "     That is the hazard `stampPatBinderTy`'s disagreement arm exists"
      echo "     for, and it is reachable again. Decide deliberately: either the"
      echo "     arm is load-bearing and this gate goes back to asserting the"
      echo "     ablation puts a release back - with a fixture that reaches the"
      echo "     path - or the new construct should not share nodes."
    else
      ok "$swept subjects, including the whole compiler, are byte-identical"
      echo "     under last-write-wins - nothing reaches the disagreeing stamp"
    fi
  else
    bad "the last-write-wins compiler did not build"
    sed 's/^/     /' "$work/lww.build.log" | head -20
  fi
else
  bad "could not ablate the poison arm"
fi

echo
if (( failed > 0 )); then
  echo "check-fallible-reclaim: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-fallible-reclaim: $checks checks - the block a fallible call"
echo "                        answers is reclaimed, the one word that reclaims"
echo "                        it brings ERR-MEM-4's 32 bytes back when removed,"
echo "                        and nothing in the tree reaches the stamp's"
echo "                        disagreement arm"
