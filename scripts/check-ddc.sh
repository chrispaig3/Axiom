#!/usr/bin/env bash
# Diverse double-compile: the same sources, run two ways that share
# nothing but the reference manual.
#
# Every other gate runs a compiler descended from the committed LLVM
# seed, so a seed defect is invisible to them all. The fixpoint
# (`stage2 == stage3`) proves reproducibility, not correctness: a
# compiler that miscompiles `>` as `>=` reproduces the miscompile. This
# is Thompson's trusting-trust problem, which the lineage gate answers
# only for the first seed.
#
# The second implementation is `scripts/lib/ddc-interp.py`, in Python
# with only its standard library, written from `docs/reference.md` and
# never ported from `self_host/*.ax`. It interprets a frozen subset
# (integers, comparisons, `if`, `let`, calls, recursion) and exits with
# the program's answer. For each `tests/ddc/*.ax` three numbers must
# agree: the fixture's `; expect N`, the exit of the seed-built binary,
# and the interpreter's exit. The stated constant means a pair wrong the
# same way still fails. The gate compares behaviour, since two honest
# codegens emit different IR.
#
# Negative probes, run every time:
#   P1  The comparator must refuse a doctored triple (42 expected, 43
#       built), so it can't be one that accepts everything.
#   P2  A seed-only codegen defect, planted in the emitted IR where a
#       backdoored seed would carry it: `020-cmp-boundary.ax` is
#       emitted, its one `icmp sgt` flipped to `icmp sge`, and both IRs
#       built and run. The honest binary must answer 42 and the
#       tampered one must not. If a codegen change moves the count of
#       `icmp sgt` off one, the probe fails: re-derive it.
#   P3  Two emissions of the honest fixture must be byte-identical. A
#       uniformly backdoored compiler passes this too, which is the gap
#       P2 closes.
#
# Limits: the subset only, a defect both sides share by misreading the
# reference alike, one maintainer for both, and Path A still trusts
# `llc` and `cc`. `bootstrap/THREATS.md` row 12 records this defence.
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

# The comparator. P1 and every agreement below call this alone, so P1
# tests the comparison the gate really makes.
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

# A sweep that reads too few files still reports agreement, so fewer
# than six fixtures fails. The corpus holds eight, so only a glob that
# stops matching or the removal of several fixtures gets below six.
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
