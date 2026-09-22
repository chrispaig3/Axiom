#!/usr/bin/env bash
# THE CAST-AT-ARGUMENT-ROOT GATE (docs/memory-model.md MM-VAL-22/23,
# QA P0 §3 F7/F19).
#
# A `cast` at an argument root launders a word past the checker's
# evidence walk (`evStampFill` in self_host/typecheck.ax classifies it
# 0 outright), so codegen emits no retain/release for it
# (self_host/codegen.ax `emitPrimRetainRef`: a missing stamp answers
# 0). The direction is LEAK, not early free - the temporary's release
# is gone - which is the conservative side, and the one this gate pins.
#
# Measured on darwin-aarch64 (probe in docs/cast-arg-root.md):
#
#   memSetWord p 0 (strDup "hi")                1 release in the IR
#   memSetWord p 0 (cast String (strDup "hi"))   0 releases in the IR
#
# WHY PIN IT RATHER THAN FIX IT. The real fix is per MM-VAL-23: casts
# belong at a RETURN under an honest declared type (the
# `mapGet`->`Int` + `mapGetStr` precedent), and the 1,223 AX3040 sites
# migrate that way - not by making codegen emit unconditional
# retain+release on evidence 0 (which would add retain traffic to every
# `memSetWord` of an integer, the shape the 0-answer exists to keep
# free) and not by refusing arg-root casts outright (which needs a new
# diagnostic code, an explain entry, goldens, and a reseed). This file
# converts "there is a documented leak hole one cast wide" into "here
# is exactly how wide, and here is the ratchet that keeps it from
# widening": if the release counts below ever become EQUAL, the defect
# is fixed and this gate must be deleted or repurposed - it will say so.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

gate_build_axc axc

echo "--- 1. user-level cast count does not grow ---"
# self_host/ is excluded: (cast Int ...) there is compiler plumbing
# for untyped words, not the user-level laundering MM-VAL-22 names.
# Baseline 329 measured 2026-09-21 (was 326 on 2026-09-19): two casts
# arrived with the AX3071 unretained-store refusal probes and one with
# the 430 reentrant-drop fixture's Foreign stash - all three probe the
# ownership rules at the boundary casts exist for, which is the
# MM-VAL-23 reason. The ratchet is <=, so removing casts always passes
# and adding one must update this number with a reason.
cast_count="$(rg --no-filename -o '\(cast ' stdlib/ tests/ examples/ 2>/dev/null | wc -l | tr -d ' ')"
if [ "$cast_count" -le 329 ]; then
  ok "user-level (cast count $cast_count <= 329)"
else
  bad "user-level (cast count $cast_count > 329): new casts need a MM-VAL-23 reason and a baseline bump"
fi

echo "--- 2. arg-root cast still leaks (does not free early) ---"
cat > "$work/cast3.ax" <<'EOF'
(import Mem)
(import Str)
(:: main Int)
(fn (main)
  (let ((p (memAlloc 8)))
    {
      (memSetWord p 0 (strDup "hi"))
      0
    }))
EOF
cat > "$work/cast4.ax" <<'EOF'
(import Mem)
(import Str)
(:: main Int)
(fn (main)
  (let ((p (memAlloc 8)))
    {
      (memSetWord p 0 (cast String (strDup "hi")))
      0
    }))
EOF
if "$axc" --diagnostic-format=ai check "$work/cast3.ax" >/dev/null 2>&1 \
  && "$axc" --diagnostic-format=ai check "$work/cast4.ax" >/dev/null 2>&1; then
  ok "both probes check OK (no new refusal)"
else
  bad "a probe no longer checks: run $axc check on cast3/cast4 by hand"
fi
"$axc" --diagnostic-format=ai emit-llvm "$work/cast3.ax" -o "$work/cast3.ll" >/dev/null 2>&1
"$axc" --diagnostic-format=ai emit-llvm "$work/cast4.ax" -o "$work/cast4.ll" >/dev/null 2>&1
# `grep -c`, not `rg -c`: the Linux image carries no ripgrep and a
# missing counter reads as 0 == 0 - the fixed defect - on exactly
# the leg that never saw the tool. (Measured 2026-09-19.)
if [[ ! -f "$work/cast3.ll" || ! -f "$work/cast4.ll" ]]; then
  bad "emit-llvm produced no IR for the probes; counting releases would compare nothing"
else
  rel3="$(grep -c 'call void @axiom_release' "$work/cast3.ll" || true)"
  rel4="$(grep -c 'call void @axiom_release' "$work/cast4.ll" || true)"
  rel3="${rel3:-0}"
  rel4="${rel4:-0}"
  if [ "$rel4" -lt "$rel3" ]; then
    ok "cast at arg root drops a release ($rel3 -> $rel4): leak direction holds, MM-VAL-22 current"
  elif [ "$rel4" -eq "$rel3" ]; then
    bad "releases now equal ($rel3 == $rel4): MM-VAL-22 may be FIXED - update docs/cast-arg-root.md and delete or repurpose this gate"
  else
    bad "cast version releases MORE ($rel3 -> $rel4): over-release direction, possible premature free - investigate immediately"
  fi
fi

echo "--- 3. AX3040 rule still pinned ---"
if "$axc" explain AX3040 >/dev/null 2>&1; then
  ok "explain AX3040 answers"
else
  bad "explain AX3040 stopped answering"
fi
if [ -f "tests/diagnostics/460-signature-type-variable.ax" ]; then
  ok "tests/diagnostics/460-signature-type-variable.ax exists"
else
  bad "460-signature-type-variable.ax missing: AX3040 accept/reject shape unpinned"
fi

echo
if [ "$failed" -gt 0 ]; then
  echo "check-cast-arg-root: $failed of $checks checks failed"
  exit 1
fi
echo "check-cast-arg-root: $checks checks - cast census bounded, leak direction pinned, AX3040 pinned"
