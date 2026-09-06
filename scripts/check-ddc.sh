#!/usr/bin/env bash
# Diverse double-compile: the same sources, executed two ways that share
# nothing but the reference manual.
#
# WHAT EVERY OTHER GATE TAKES FOR GRANTED. Each of the 80 gates in this
# tree runs a compiler descended from the committed LLVM seed, so a
# defect in the seed is invisible to all of them: every one asks the
# suspect to grade its own work. The fixpoint (`stage2 == stage3`)
# proves reproducibility, not correctness - a compiler that miscompiles
# `>` as `>=` reproduces that miscompile in its own output, and both
# stages agree. This is Thompson's trusting-trust problem, and the
# lineage gate answers it only at the root: the Rust compiler at
# `bb730db` (28,082 lines, same author as `self_host/`) compiling the
# FIRST seed's tree. Nothing re-derives the CURRENT tree independently.
#
# WHAT THIS ADDS. A second, deliberately simple checker - Python,
# standard library only, derived from `docs/reference.md`'s described
# behaviour and never ported from `self_host/*.ax` - that directly
# interprets a frozen subset of the language
# (`scripts/lib/ddc-interp.py` states it: integers, comparisons, `if`,
# `let`, calls, recursion; no strings, no effects, no macros) and
# answers with the program's exit status. For every fixture in
# `tests/ddc/*.ax` the gate requires three numbers to agree: the
# `; expect N` the fixture states, the exit of the binary the
# seed-descended compiler builds, and the exit of the interpreter that
# never invoked an Axiom binary, `llc` or `cc`. The comparable artefact
# is executed behaviour, not IR bytes: two honest codegens MUST differ
# (the lineage gate asserts exactly that of the Rust anchor's IR), so
# byte-identity would be the wrong thing to ask.
#
# WHY AGREEMENT IS ENOUGH HERE, and where it is not. Agreement says two
# implementations agree, not that either is correct - the stdlib gate's
# header makes the same point about its retired differential. The third
# number is what makes this stronger than that: `; expect N` is a claim
# the fixture's own author states about arithmetic both sides can do,
# so a uniformly wrong pair still has to equal the stated constant.
# This does not cover the language outside the subset, and it does not
# cover a defect both implementations share by sharing a
# misunderstanding of the reference. What it covers is exactly the
# Thompson class: a defect present in the seed-descended path and absent
# from the independent one.
#
# NEGATIVE PROBES, run on every invocation:
#   P1  the comparator is fed a doctored triple (42 expected, 43 built)
#       and must refuse it. A comparator that accepts everything is the
#       vacuous check this repository finds most often.
#   P2  a seed-only codegen defect, planted where a backdoored seed's
#       emission would carry it: `020-cmp-boundary.ax` is emitted to IR,
#       its single `icmp sgt` flipped to `icmp sge` (the gate asserts
#       there is exactly one, so a codegen change re-derives this probe
#       rather than passing it silently), both IRs built and run. The
#       honest binary must answer 42 with the interpreter; the tampered
#       one answers 43 against both. The fixpoint cannot see this class:
#       P3 shows why.
#   P3  the honest fixture is emitted twice and the two IRs must be
#       byte-identical. Reproducibility HOLDS - and would hold for a
#       uniformly backdoored compiler too, since both of its stages
#       carry the defect identically. Self-comparison passing while the
#       independent comparison fails is precisely the gap this gate
#       exists for.
#
# COST. Eight fixtures through `run` plus two emissions and two links:
# seconds. It runs in the `test` matrix on every push.
#
# WHAT REMAINS, stated rather than hidden. The interpreter shares a
# maintainer with the compiler (social diversity is item 02's bus-factor
# work, not this gate's), covers the subset only, and Path A still
# trusts `llc`/`cc` (THREATS.md rows 5-7). `bootstrap/THREATS.md` row 12
# records this defence and those limits.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH - the independent checker cannot run, and skipping would be a gate that is off"; exit 1; }
command -v llc >/dev/null || { echo "FAIL: llc is not on PATH"; exit 1; }
command -v cc >/dev/null || { echo "FAIL: cc is not on PATH"; exit 1; }

interp="$repo_root/scripts/lib/ddc-interp.py"
[[ -f "$interp" ]] || { echo "FAIL: $interp is missing"; exit 1; }

failed=0; passed=0
fail() { echo "FAIL: $*"; failed=$((failed + 1)); }
ok()   { echo "ok   $*"; passed=$((passed + 1)); }

# The comparator. Every agreement below - and probe P1 - calls this and
# nothing else, so a probe that passes here is a statement about the
# comparison the gate actually makes.
agree() { # <name> <want> <axc-exit> <interp-exit> -> 0 when all three agree
  if [[ "$2" == "$3" && "$3" == "$4" ]]; then
    ok "$1: expect $2, seed-built $3, independent $4"
    return 0
  fi
  echo "FAIL: $1: expect $2, seed-built $3, independent $4 - the two implementations disagree"
  return 1
}

echo "== P1: the comparator refuses a doctored triple =="
if agree "probe" 42 43 42 >/dev/null 2>&1; then
  fail "probe: expect 42 against seed-built 43 was accepted - the comparator cannot fail"
else
  ok "probe: expect 42 against seed-built 43 is refused"
fi

echo
echo "== the subset corpus, three ways =="
swept=0
for src in tests/ddc/*.ax; do
  name="$(basename "$src" .ax)"
  swept=$((swept + 1))
  want="$(head -1 "$src" | sed -n 's/^; expect \([0-9][0-9]*\)$/\1/p')"
  if [[ -z "$want" ]]; then
    fail "$name: first line is not '; expect N' - a fixture with no stated answer cannot be agreed with"
    continue
  fi
  "$axc" run "$src" >/dev/null 2>"$work/$name.run.err"; axc_st=$?
  python3 "$interp" "$src" >/dev/null 2>"$work/$name.interp.err"; interp_st=$?
  if (( interp_st == 3 )); then
    fail "$name: the independent checker refused the fixture: $(head -1 "$work/$name.interp.err")"
    continue
  fi
  agree "$name" "$want" "$axc_st" "$interp_st" || failed=$((failed + 1))
done

# A sweep that reads fewer files than it should reports the agreement
# it was looking for. Eight fixtures today; six is the floor a real
# deletion campaign would have to cross deliberately.
if (( swept < 6 )); then
  fail "swept $swept fixture(s), floor is 6 - the corpus shrank or the glob stopped matching"
fi

echo
echo "== P2: a seed-only codegen defect is caught =="
boundary="tests/ddc/020-cmp-boundary.ax"
if ! "$axc" emit-llvm --diagnostic-format=ai "$boundary" -o "$work/honest.ll" >/dev/null 2>"$work/emit.err"; then
  fail "could not emit $boundary: $(head -3 "$work/emit.err")"
else
  if ! grep -q '^target triple' "$work/honest.ll" || (( $(wc -l <"$work/honest.ll") < 100 )); then
    fail "the honest emission is truncated ($(wc -l <"$work/honest.ll" | tr -d ' ') lines) - comparing it would pass on an empty file"
  else
    nsgt="$(grep -c 'icmp sgt' "$work/honest.ll")"
    if (( nsgt != 1 )); then
      fail "the honest IR holds $nsgt 'icmp sgt' lines, not exactly one - the ablation's anchor moved, re-derive it"
    else
      sed 's/icmp sgt/icmp sge/' "$work/honest.ll" > "$work/evil.ll"
      if cmp -s "$work/honest.ll" "$work/evil.ll"; then
        fail "the flip changed no byte - the ablation is measuring itself"
      else
        if llc -filetype=obj -relocation-model=pic "$work/honest.ll" -o "$work/honest.o" 2>"$work/honest.link.err" \
          && cc "$work/honest.o" -o "$work/honest" $link_entry 2>>"$work/honest.link.err" \
          && llc -filetype=obj -relocation-model=pic "$work/evil.ll" -o "$work/evil.o" 2>"$work/evil.link.err" \
          && cc "$work/evil.o" -o "$work/evil" $link_entry 2>>"$work/evil.link.err"; then
          "$work/honest" >/dev/null 2>&1; honest_st=$?
          "$work/evil" >/dev/null 2>&1; evil_st=$?
          if (( honest_st != 42 )); then
            fail "the honest binary answers $honest_st, not 42 - the pipeline is measuring itself"
          elif (( evil_st == 42 )); then
            fail "one flipped comparison and the binary still answers 42 - the boundary fixture cannot see its own ablation"
          else
            ok "honest answers 42 with the interpreter; sgt->sge answers $evil_st against both"
          fi
        else
          fail "could not build the honest/tampered pair: $(head -3 "$work/honest.link.err" "$work/evil.link.err" 2>/dev/null)"
        fi
      fi
    fi
  fi
fi

echo
echo "== P3: reproducibility holds - and would hold with the defect too =="
if "$axc" emit-llvm --diagnostic-format=ai "$boundary" -o "$work/second.ll" >/dev/null 2>&1 \
  && cmp -s "$work/honest.ll" "$work/second.ll"; then
  ok "two emissions of $boundary are byte-identical - self-comparison passes, which a uniform backdoor also satisfies"
else
  fail "two emissions of $boundary differ - the compiler is nondeterministic (see check-reproducible.sh)"
fi

echo
if (( failed > 0 )); then
  echo "check-ddc: $failed check(s) failed, $passed passed"
  exit 1
fi
echo "check-ddc: $passed checks - the seed-built compiler and the independent"
echo "           checker agree on $swept fixtures, and a planted seed-only"
echo "           defect fails the comparison its fixpoint cannot see"
