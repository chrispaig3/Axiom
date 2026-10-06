#!/usr/bin/env bash
# `;@axiom:isr` marks an interrupt entry point: the hardware calls it
# by name with no arguments, and it must not allocate.
#
# `isr` implies `no-alloc`, added to the same claim set the effect walk
# answers, so the violation, the warning and `strict` read as if the
# claim were written. It refuses parameters with AX3010. An allocating
# ISR is a compile error, not heap corruption at run time. See
# docs/embedded-guide.md.
#
#   1. Refusals. `651-isr-params` draws AX3010 at the declaration, and
#      `652-isr-alloc` draws AX3049 naming `no-alloc` with the call
#      chain to the allocation. A typo (`isrr`) draws AX3039
#      suggesting `isr`. All three are errors and fail the check.
#   2. Staticlib. A probe with a `pub` ISR and a `pub` plain function
#      archives both symbols. The plain one is the control that shows
#      the gate measures `isr`, not the export. Fixture 652 is refused
#      again under `--emit-staticlib`, because the check runs wherever
#      the checker runs.
#   3. Ablations. A shadow tree whose `isr` block answers nothing lets
#      both fixtures check clean, and a planted allocation in the good
#      probe fails the archive build. Each confirms its edit landed
#      before trusting the failure.
#   4. Bound handlers (MM-EXEC-18, MM-EXEC-19): the fault hook's shape,
#      recursion and waiting, each with its own ablation.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

fx651="$repo_root/tests/diagnostics/651-isr-params.ax"
fx652="$repo_root/tests/diagnostics/652-isr-alloc.ax"
for f in "$fx651" "$fx652"; do
  [[ -f "$f" ]] || { echo "FAIL: $f is missing"; exit 1; }
done

# --------------------------------------------------------------------
echo "== 1. the two refusals, and the typo that suggests =="
# --------------------------------------------------------------------
"$axc" --diagnostic-format=ai check "$fx651" > "$work/651.out" 2> "$work/651.err"; rc651=$?
if [[ "$rc651" != 0 ]] && grep -q '^E AX3010 ' "$work/651.err"; then
  ok "651: a parameterised isr draws AX3010 and fails"
else
  bad "651: exit $rc651, wanted failure with AX3010"
  head -3 "$work/651.err" | sed 's/^/     /'
fi
"$axc" --diagnostic-format=ai check "$fx652" > "$work/652.out" 2> "$work/652.err"; rc652=$?
if [[ "$rc652" != 0 ]] && grep -q '^E AX3049 .*no-alloc' "$work/652.err"; then
  ok "652: an allocating isr draws AX3049 naming no-alloc and fails"
else
  bad "652: exit $rc652, wanted failure with AX3049 naming no-alloc"
  head -3 "$work/652.err" | sed 's/^/     /'
fi
cat > "$work/typo.ax" <<'TYPO'
(:: tick Int)
;@axiom:isrr
(fn (tick) 1)

(:: main Int)
(fn (main) 0)
TYPO
"$axc" --diagnostic-format=ai check "$work/typo.ax" > "$work/typo.out" 2> "$work/typo.err"; rctypo=$?
if [[ "$rctypo" == 1 ]] && grep -q '^E AX3039 .*did you mean `isr`' "$work/typo.err"; then
    ok "typo: isrr suggests isr as an error and fails"
else
  bad "typo: exit $rctypo, wanted failure with an AX3039 suggesting isr"
  head -3 "$work/typo.err" | sed 's/^/     /'
fi

# --------------------------------------------------------------------
echo
echo "== 2. the staticlib composition: symbols out, checks still on =="
# --------------------------------------------------------------------
cat > "$work/isrlib.ax" <<'LIB'
(pub :: tick Int)

;@axiom:isr
(pub fn (tick) 1)

(pub :: plain (-> Int Int))

(pub fn (plain n) (+ n 1))
LIB
if "$axc" build --input "$work/isrlib.ax" --output "$work/isrlib.a" --emit-staticlib > "$work/isrlib.build" 2>&1; then
  syms="$(nm -g "$work/isrlib.a" 2>/dev/null | grep -oE '_?[A-Za-z][A-Za-z0-9_]*' | LC_ALL=C sort -u | tr '\n' ' ')"
  if [[ "$syms" == *"tick"* && "$syms" == *"plain"* ]]; then
    ok "archive carries _tick and _plain ($(echo "$syms" | tr ' ' '\n' | grep -c . || true) global symbols)"
  else
    bad "archive is missing a symbol: [$syms]"
  fi
else
  bad "the good probe would not archive:"
  sed 's/^/     /' "$work/isrlib.build" | head -5
fi
# The refusing fixture, archived: the check runs on the staticlib path too.
if "$axc" build --input "$fx652" --output "$work/isr652.a" --emit-staticlib > "$work/isr652.build" 2>&1; then
  bad "652 archived clean - the isr check does not run under --emit-staticlib"
else
  if grep -q 'AX3049' "$work/isr652.build"; then
    ok "652 is refused as AX3049 under --emit-staticlib too"
  else
    bad "652 failed under --emit-staticlib, but not as AX3049:"
    head -3 "$work/isr652.build" | sed 's/^/     /'
  fi
fi

# --------------------------------------------------------------------
echo
echo "== 3. the ablations: each half, deliberately broken =="
# --------------------------------------------------------------------
# Ablation 1: `isr` implies nothing. The tag still parses (the namespace
# is open) but has no effect, so both fixtures must check clean.
abl="$work/abl-noop"
rm -rf "$abl"; mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/"
if python3 - "$abl/self_host/typecheck.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = "(if (== (tagsHaveIsr sig own) 1)"
if s.count(old) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, "(if (== (tagsHaveIsr sig own) 999)"))
PY
then
  if gate_build_tree "$axiom" "$abl" "$AXIOM_STDLIB" "$work/axc-noisr" \
       > "$work/abl-noop.build" 2>&1; then
    r1=0; AXIOM_STDLIB="$abl/stdlib" "$work/axc-noisr" --diagnostic-format=ai check "$fx651" >/dev/null 2>&1 || r1=$?
    r2=0; AXIOM_STDLIB="$abl/stdlib" "$work/axc-noisr" --diagnostic-format=ai check "$fx652" >/dev/null 2>&1 || r2=$?
    if [[ "$r1" == 0 && "$r2" == 0 ]]; then
      ok "ablation noop: with the implication deleted both fixtures check clean, so arms 1-2 are measuring it"
    else
      bad "ablation noop: exits $r1/$r2 with the implication deleted - the arms prove nothing"
    fi
  else
    bad "ablation noop: the compiler with the implication deleted would not build"
    sed 's/^/     /' "$work/abl-noop.build" | head -8
  fi
else
  bad "ablation noop: the edit did not land - the implication was never broken, so the arm proved nothing"
fi

# Ablation 2: the good probe allocates. The archive build must fail,
# which shows section 2 passes because of the probe's shape, not the flag.
{ printf '(import Str)\n\n'; cat "$work/isrlib.ax"; cat <<'ABL'

(pub :: greedy Int)

;@axiom:isr
(pub fn (greedy) (strLen (concat "x" "y")))
ABL
} > "$work/isrlib-abl.ax"
# Confirm the plant landed before trusting the failure.
if ! grep -q '(pub fn (greedy)' "$work/isrlib-abl.ax"; then
  bad "ablation alloc: the plant did not land, so the arm proved nothing"
elif ! head -1 "$work/isrlib-abl.ax" | grep -q '(import Str)'; then
  bad "ablation alloc: the import did not land, so the arm proved nothing"
elif "$axc" build --input "$work/isrlib-abl.ax" --output "$work/isrlib-abl.a" --emit-staticlib > "$work/isrlib-abl.build" 2>&1; then
  bad "ablation alloc: an allocating isr archived clean - section 2 cannot fail"
else
  if grep -q 'AX3049' "$work/isrlib-abl.build"; then
    ok "ablation alloc: the planted allocation fails the archive as AX3049"
  else
    bad "ablation alloc: failed, but not as AX3049:"
    head -3 "$work/isrlib-abl.build" | sed 's/^/     /'
  fi
fi

# --------------------------------------------------------------------
echo
echo "== 4. the bound handlers: the fault hook's shape, recursion, waiting =="
# --------------------------------------------------------------------
# docs/memory-model.md MM-EXEC-18 and MM-EXEC-19. Four fixtures, each
# with a control inside it that must stay silent:
#   1090  `isr(fault)` takes five `Int`s and answers one. Two wrong
#         shapes draw AX3010; the declared one draws nothing.
#   1091  a bound handler reaching an operation that waits is AX4009:
#         an IRQ handler reaching `__arm_wfi`, or a fault hook reaching
#         a system call. A hook halting in `wfi` is accepted.
#   1092  every `isr` implies `restrict(no-recursion)`: two handlers
#         reaching a self-call draw AX3049 naming it.
#   1093  `isr(fault)` implies `no-alloc` like every `isr`.
# Then one ablation per rule: a shadow tree with that rule's check
# answering nothing, under which its fixture must check clean. That
# shows each refusal comes from its rule.
fx1090="$repo_root/tests/diagnostics/1090-isr-fault-signature.ax"
fx1091="$repo_root/tests/diagnostics/1091-isr-waits.ax"
fx1092="$repo_root/tests/diagnostics/1092-isr-recursion.ax"
fx1093="$repo_root/tests/diagnostics/1093-isr-fault-alloc.ax"
for f in "$fx1090" "$fx1091" "$fx1092" "$fx1093"; do
  [[ -f "$f" ]] || { echo "FAIL: $f is missing"; exit 1; }
done
# `refused <fixture> <want lines as code:needle, one per expected diagnostic>`
refused() {
  local fx="$1"; shift
  local base; base="$(basename "$fx" .ax)"
  "$axc" --diagnostic-format=ai check "$fx" > "$work/$base.out" 2> "$work/$base.err"; local rc=$?
  local n; n=$(grep -c '^[EW] AX' "$work/$base.err" || true)
  if [[ "$rc" == 0 ]]; then
    bad "$base: checked clean, wanted $# refusals"; return
  fi
  if [[ "$n" != "$#" ]]; then
    bad "$base: $n diagnostics, wanted $#:"; head -6 "$work/$base.err" | cut -c1-200 | sed 's/^/     /'; return
  fi
  local w
  for w in "$@"; do
    if ! grep -q "^E ${w%%:*} .*${w#*:}" "$work/$base.err"; then
      bad "$base: no ${w%%:*} matching [${w#*:}]"; return
    fi
  done
  ok "$base: $# refusals, each the rule's, and the control silent"
}
refused "$fx1090" 'AX3010:AXTAG mismatch on `tooFew`: `isr(fault)` binds the fault hook' \
                  'AX3010:AXTAG mismatch on `wrongType`: `isr(fault)` binds the fault hook'
refused "$fx1091" 'AX4009:`onIrq` is bound by `isr(irq)` and waits for an interrupt with IRQs masked: onIrq -> settle -> __arm_wfi' \
                  'AX4009:`onFault` is bound by `isr(fault)` and reaches a system call.*onFault -> note -> __syscall1'
refused "$fx1092" 'AX3049:`tick` claims `restrict(no-recursion)`.*tick -> countdown -> countdown' \
                  'AX3049:`onFault` claims `restrict(no-recursion)`.*onFault -> countdown -> countdown'
refused "$fx1093" 'AX3049:`onFault` claims `restrict(no-alloc)` and the body performs Alloc'

# One shadow tree per rule, as `name~anchor~replacement~fixture`. The
# separator is `~` because an anchor holds `||`. The edit must land
# exactly once, the tree must build, and the fixture must check clean.
while IFS='~' read -r name anchor repl fx; do
  abl="$work/abl-$name"
  rm -rf "$abl"; mkdir -p "$abl"
  cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/"
  if ! python3 - "$abl/self_host/typecheck.ax" "$anchor" "$repl" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  then
    bad "ablation $name: the edit did not land - the rule was never broken, so the arm proved nothing"
    continue
  fi
  if ! gate_build_tree "$axiom" "$abl" "$AXIOM_STDLIB" "$work/axc-$name" > "$work/abl-$name.build" 2>&1; then
    bad "ablation $name: the compiler with the rule deleted would not build"
    sed 's/^/     /' "$work/abl-$name.build" | head -8
    continue
  fi
  r=0; AXIOM_STDLIB="$abl/stdlib" "$work/axc-$name" --diagnostic-format=ai check "$repo_root/tests/diagnostics/$fx" > /dev/null 2>&1 || r=$?
  if [[ "$r" == 0 ]]; then
    ok "ablation $name: with the rule deleted $fx checks clean, so section 4 measures it"
  else
    bad "ablation $name: $fx still fails with the rule deleted - section 4 proves nothing about it"
  fi
done <<'ABL'
faultsig~(if (== (isrFaultSigOk tc d) 1)~(if (== (isrFaultSigOk tc d) (isrFaultSigOk tc d))~1090-isr-fault-signature.ax
waits~(if (|| (!= (nodeTag d) TAG_D_FN) (if (strEq v "irq") false (if (strEq v "fault") false true)))~(if true~1091-isr-waits.ax
norec~          (if (== (strInVec rs "no-recursion" 0) 1)~          (if true~1092-isr-recursion.ax
ABL

echo
if (( failed > 0 )); then
  echo "check-isr: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-isr: $checks checks - parameters refused, allocation refused,"
echo "           typos suggested, symbols archived, and both halves ablated;"
echo "           the fault hook's shape, recursion and waiting refused, each"
echo "           rule ablated"
