#!/usr/bin/env bash
# A tail call runs in constant stack at `--opt 0` - a SELF call in every
# tail position, and a MUTUAL call whose prototypes match - and the
# marker that guarantees the second is proved to be the mechanism by
# taking it out of the IR.
#
# WHAT WAS TRUE BEFORE THIS EXISTED, measured 2026-09-03 on the tree at
# 6d26d2e with eight probes under an 8 MiB stack:
#
#   * a self tail call in a `let` body, a `cond` arm, a `match` arm and
#     the tail of a `{ }` block ran ten million iterations at `--opt 0`
#     - `emitTailJump`'s loop reaches every one of them, and has since
#     2026-08-22 (`self_host/codegen.ax`, the comment under
#     `tailCallsSelf`). `docs/reference.md`'s Optimisation section and
#     this gate's sibling `check-stack-depth.sh` still said a `let`
#     body was not a tail position. Nothing measured it.
#   * a MUTUAL tail call - `(fn (ev i acc) (if .. acc (od (+ i 1) ..)))`
#     - died by SIGSEGV at `--opt 0` and ran only at `--opt 1`, where
#     LLVM's sibling-call pass happens to rescue it. That is what
#     `docs/memory-model.md` MM-EXEC-6c said, and a program MUST NOT
#     rely on it.
#
# WHAT CHANGED. `emitPlainCall` marks a tail call `musttail` when LLVM's
# conditions hold and nothing is owed after it (`mustTailOK`, which
# lists them). `musttail` is LLVM's GUARANTEED tail call: `llc` emits a
# jump at every optimisation level or refuses the module. Measured on
# the compiler's own IR: 386 call sites marked, out of the 1,059 calls
# that sat immediately before a `ret`; 603 of the rest have a
# prototype the caller's does not match (LLVM's condition under the C
# convention), 68 owe a retain or a release after the call (this
# compiler's condition), and the two left are runtime helpers.
#
# WHAT IT ASSERTS
#   1. tests/stdlib/467-mutual-tail.ax, built at `--opt 0`, answers its
#      golden under a 512 KiB stack. Ten million alternating calls
#      through `ev`/`od`, through a `let` body and a `match` arm, and
#      around a three-way cycle; a self call in a `let` body beside
#      them. A plain call chain that deep needs hundreds of megabytes.
#      The fixture's two REFUSED shapes are two thousand deep, which is
#      the frames they genuinely cost at `--opt 0` and fits: a first
#      draft ran them a hundred thousand deep and the whole fixture
#      died of the term that claims no guarantee.
#   2. The IR says why: `musttail` on every call the design marks, and
#      on NEITHER refusal - the mismatched arity (`od3`/`ev2`) and the
#      owned temporary (`odS`/`evS`), whose call is followed by the
#      `axiom_release` that is the reason it cannot be marked. A
#      refusal that had quietly become a mark would be a use after
#      free in the callee, and this is where it would show.
#   3. THE ABLATION: the same IR with every `musttail` deleted, through
#      the same `llc -O0` and `cc`, must die by SIGNAL under the same
#      512 KiB. The marker is the whole mechanism, so the marker is
#      what is taken away; a fixture that passed without it would be
#      measuring the stack, not the guarantee.
#   4. The compiler's own IR carries at least 300 `musttail` sites
#      (386 on 2026-09-03). A regression that lost the token - an
#      emitter path that clears field 30 early, a pre-scan that stops
#      opening the tail walk - lands far below that; the count is
#      printed so drift is visible before it is a failure.
#
# NOT A DIFFERENTIAL against an installed compiler: the subject is what
# THIS tree's emitter writes, and the assertions are on the process's
# exit status and the IR's own bytes.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

fixture="tests/stdlib/467-mutual-tail.ax"
golden="tests/stdlib/467-mutual-tail.out"
stack_kib=512

# One run at a stack limit. Answers "ok", "signal:<rc>" or "other:<rc>".
run_at() {  # <binary> <kib>
  local out rc
  out="$( (ulimit -s "$2" 2>/dev/null || exit 200; "$1") 2>/dev/null )"
  rc=$?
  if [[ "$rc" -eq 200 ]]; then echo "unsettable"; return; fi
  if [[ "$rc" -eq 0 ]]; then
    if [[ "$out" == "$(cat "$golden")" ]]; then echo "ok"; else echo "other:0-wrong-output"; fi
    return
  fi
  if [[ "$rc" -ge 128 ]]; then echo "signal:$rc"; return; fi
  echo "other:$rc"
}

echo "== 1. the fixture at --opt 0 under ${stack_kib} KiB =="
if ! "$axc" build --input "$fixture" --output "$work/mt" --opt 0 --emit-llvm >"$work/mt.build" 2>&1; then
  echo "FAIL: could not build $fixture at --opt 0"; sed 's/^/     /' "$work/mt.build" | head -10; exit 1
fi
ll="$work/mt.ll"
[[ -f "$ll" ]] || { echo "FAIL: --emit-llvm left no $ll"; exit 1; }
r="$(run_at "$work/mt" "$stack_kib")"
if [[ "$r" == "unsettable" ]]; then
  echo 'SKIP: this shell cannot set ulimit -s (nothing to measure)'
  exit 0
fi
if [[ "$r" == "ok" ]]; then
  ok "467-mutual-tail answers its golden at --opt 0 under ${stack_kib} KiB"
else
  bad "467-mutual-tail at --opt 0 under ${stack_kib} KiB: $r"
fi

echo "== 2. the IR marks what the design marks, and neither refusal =="
marked=0
for callee in od ev odM evL cyA cyB cyC; do
  if grep -q "musttail call i64 @${callee}(" "$ll"; then
    marked=$((marked + 1))
  else
    bad "no \`musttail\` on the call to \`$callee\`"
  fi
done
(( marked == 7 )) && ok "musttail on all seven calls the design marks"
if grep -q "musttail call i64 @od3(\|musttail call i64 @ev2(" "$ll"; then
  bad "a MISMATCHED prototype was marked musttail - LLVM refuses that under the C convention, and llc would have"
else
  ok "the mismatched-arity pair is a plain call"
fi
if grep -q "musttail call i64 @odS(\|musttail call i64 @evS(" "$ll"; then
  bad "an OWNED TEMPORARY was handed over under musttail - the caller's release after the call is gone"
else
  # and the reason is in the IR: the release follows the call
  if awk '/= call i64 @odS\(/{f=1; n=0; next} f{n++; if ($0 ~ /axiom_release/) {hit=1; exit} if (n>4) f=0} END{exit !hit}' "$ll"; then
    ok "the owned-temporary pair is a plain call, and its axiom_release follows it"
  else
    bad "the owned-temporary call to odS is not followed by its axiom_release - the reason for the refusal has moved"
  fi
fi

echo "== 3. the ablation: the same IR without the marker dies by signal =="
sed 's/musttail call/call/' "$ll" > "$work/abl.ll"
if grep -q musttail "$work/abl.ll"; then
  bad "the ablation left a musttail in the IR"
fi
if llc -O0 -filetype=obj "$work/abl.ll" -o "$work/abl.o" 2>"$work/abl.llc" && cc "$work/abl.o" -o "$work/abl" 2>"$work/abl.cc"; then
  r="$(run_at "$work/abl" "$stack_kib")"
  case "$r" in
    signal:*) ok "without musttail the same program dies by ${r#signal:} under ${stack_kib} KiB - the marker is the mechanism" ;;
    ok)       bad "without musttail the program still answers under ${stack_kib} KiB - the fixture is not deep enough to need the guarantee" ;;
    *)        bad "the ablated program: $r" ;;
  esac
  # That it is the STACK it dies of is established by assertion 1: the
  # same IR, marker kept, answered under the same limit. Ten million
  # frames cannot be given room to prove it the other way round - the
  # chain needs hundreds of megabytes, more than `ulimit -s` will grant
  # on darwin - so the pair of runs under ONE limit is the measurement.
else
  bad "could not compile the ablated IR"; head -5 "$work/abl.llc" "$work/abl.cc" 2>/dev/null | sed 's/^/     /'
fi

echo "== 4. the compiler's own IR =="
floor=300
if "$axc" emit-llvm self_host/main.ax > "$work/self.ll" 2>"$work/self.err"; then
  n="$(grep -c 'musttail call' "$work/self.ll")"
  if (( n >= floor )); then
    ok "self_host/main.ax carries $n musttail sites (floor $floor)"
  else
    bad "self_host/main.ax carries $n musttail sites, under the floor of $floor"
  fi
else
  bad "emit-llvm self_host/main.ax failed"; head -5 "$work/self.err" | sed 's/^/     /'
fi

echo
if (( failed > 0 )); then
  echo "check-tail-calls: $failed check(s) failed"
  exit 1
fi
echo "check-tail-calls: $checks checks passed"
