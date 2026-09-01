#!/usr/bin/env bash
# A release on a STATIC is not emitted, and one predicate is what does it.
#
# `MM-LIFE-2b`'s header sits at handle-16 on every counted block. For a
# bare string literal the block is a `@strhdr_*` constant and the count
# word is the sentinel `-1`, so `@axiom_release` handles it by loading
# the count, comparing against `-1`, and returning. The call is a call
# that cannot free anything.
#
# WHAT THIS WAS, MEASURED 2026-08-31 over the compiler's own emitted IR
# (`emit-llvm self_host/main.ax`, 197,562 lines, 3,469 functions), by
# classifying every `axiom_release` site by what DEFINES the value it
# releases:
#
#     5762  53.1%  a static string literal (@strhdr_*)
#     4636  42.7%  the result of a call (callee-allocated, owned)
#      338   3.1%  a load - a field or a frame slot
#      110   1.0%  a phi
#        3   0.0%  a parameter (borrowed)
#
# Over half the release traffic in the largest Axiom program there is,
# doing nothing, and the operand's definition said so at compile time.
# Deleting those 5,762 out of the IR by hand and rebuilding gave
# byte-identical output, a 5.3% smaller binary, and peak RSS at or
# below baseline - which is arithmetic, not luck: deleting a call that
# frees nothing cannot cost memory. The compiler change that replaced
# that by-hand edit measures 5.6% on its own binary; the two differ
# because the by-hand version edited ONE emission of the IR and this
# one reaches every emission including the compiler's own bootstrap.
#
# WHY IT IS NOT `valueOwnedRef` ANSWERING 0, which is the obvious fix
# and is wrong. That predicate answers 1 for `TAG_E_STR` deliberately -
# its own comment says "a static: immortal, and releasing it is a
# no-op, so a branch answering one does not stop the join being owned"
# - because `(if c "lit" (mkStr))` has to stay owned for the OTHER
# branch's share to be given back. Answering 0 there silences this
# release and LEAKS that one. So `isStaticSentinelNode` is asked at the
# two sites that emit a release for a value that IS the literal, and
# the join reasoning is untouched. The gate's second assertion is what
# keeps that distinction honest.
#
# THE ABLATION. `isStaticSentinelNode` in `self_host/codegen.ax` answers
# 1 for `TAG_E_STR`. Turning that answer into 0 is the whole fix
# undone: the predicate still exists, still runs, and never fires. The
# gate rebuilds the compiler from the ablated tree and requires the
# static-release count to go back up into the thousands. A count that
# no ablation can move is not evidence.
#
# Cost: one extra compiler build, the same price
# `check-fallible-reclaim.sh` pays for the same reason.
#
# Usage:
#   scripts/check-static-release.sh
#   AXIOM=path/to/compiler scripts/check-static-release.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH"; exit 1; }
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# Count `axiom_release` sites whose operand is defined, in the same
# define, by a `ptrtoint ... @strhdr_*` - the static-string form and
# the only one `emitStrExpr` writes. Prints "<static> <total> <hdrs>".
count_static_releases() {
  python3 - "$1" <<'PY'
import re, sys
txt = open(sys.argv[1], encoding="utf-8", errors="replace").read()
static = total = 0
hdrs = len(re.findall(r'^@strhdr_\d+ = ', txt, re.M))
for b in re.split(r'\n(?=define )', txt):
    defs = {}
    for L in b.split("\n"):
        m = re.match(r'\s*(%[\w.]+) = (.*)', L)
        if m:
            defs[m.group(1)] = m.group(2)
    for L in b.split("\n"):
        m = re.match(r'^\s*call void @axiom_release\(i64 (%[.\w]+)\)', L)
        if m:
            total += 1
            if "@strhdr_" in defs.get(m.group(1), ""):
                static += 1
print(static, total, hdrs)
PY
}

# ---------------------------------------------------------------
# 1. A fixture whose literals sit in BOTH guarded positions.
# ---------------------------------------------------------------
# `argOf` puts one in argument position (`releaseOwnedArgs`) and `Box`
# puts one in a constructor field (the block-construction store). Both
# are the shapes that emitted a release before 2026-08-31, and both
# must emit none now.
echo "== a literal in argument and in field position emits no release =="
cat > "$work/lit.ax" <<'AX'
(import Str)

(struct Box (label : String) (n : Int))

(:: argOf (-> Int Int))

(fn (argOf n) (strLen (strDup "in argument position")))

(:: boxOf (-> Int Int))

(fn (boxOf n) (cast Int (Box "in field position" n)))

(:: main Int)

(fn (main) (- (argOf 1) (boxOf 1)))
AX
if ! "$axc" emit-llvm "$work/lit.ax" -o "$work/lit.ll" >"$work/lit.log" 2>&1; then
  bad "the fixture does not compile"
  sed 's/^/     /' "$work/lit.log" | head -20
else
  read -r st tot hd <<<"$(count_static_releases "$work/lit.ll")"
  if [[ "$hd" -lt 2 ]]; then
    bad "the fixture emitted $hd string headers; it is supposed to have at least 2 - the check would be vacuous"
  elif [[ "$st" != 0 ]]; then
    bad "$st release(s) on a static literal, over $hd headers; expected 0"
  else
    ok "0 static releases over $hd string headers ($tot release site(s) in total, all on real blocks)"
  fi
fi

# ---------------------------------------------------------------
# 2. The join stays owned - the thing the obvious fix would break.
# ---------------------------------------------------------------
# `(if c "lit" (strDup ...))` is owned by `valueOwnedRef` BECAUSE the
# literal answers 1 there. If someone "simplifies" this change by
# making that predicate answer 0 for TAG_E_STR, this arm's share stops
# being given back and the leak is silent. So the gate requires the
# join to still emit a release: the literal's is gone, the join's is
# not, and the two are different questions.
echo "== a join over a literal and a real string still gives its share back =="
cat > "$work/join.ax" <<'AX'
(import Str)

(:: pick (-> Int Int))

(fn (pick c)
  (strLen
    (if (== c 0)
      "a literal"
      (strDup "a real block")
    )
  )
)

(:: main Int)

(fn (main) (- (pick 0) (pick 0)))
AX
if ! "$axc" emit-llvm "$work/join.ax" -o "$work/join.ll" >"$work/join.log" 2>&1; then
  bad "the join fixture does not compile"
  sed 's/^/     /' "$work/join.log" | head -20
else
  read -r jst jtot jhd <<<"$(count_static_releases "$work/join.ll")"
  if [[ "$jtot" -lt 1 ]]; then
    bad "the join emitted $jtot release sites; the owned join's share is no longer given back - see this gate's header"
  elif [[ "$jst" != 0 ]]; then
    bad "$jst release(s) on a static literal in the join fixture; expected 0"
  else
    ok "the join keeps $jtot release site(s) and none is on the literal"
  fi
fi

# ---------------------------------------------------------------
# 3. The corpus figure, over the largest Axiom program there is.
# ---------------------------------------------------------------
# A residue is expected and is named rather than rounded away: five
# sites survive, from release paths that hold no AST node to ask. The
# cap is what would notice a regression, and the header floor is what
# keeps a compiler that emitted no literals at all from passing.
echo "== the compiler's own IR: the residue is named, not rounded =="
if ! "$axc" emit-llvm "$repo_root/self_host/main.ax" -o "$work/self.ll" >"$work/self.log" 2>&1; then
  bad "could not emit IR for self_host/main.ax"
  sed 's/^/     /' "$work/self.log" | head -20
else
  read -r sst stot shd <<<"$(count_static_releases "$work/self.ll")"
  if [[ "$shd" -lt 2000 ]]; then
    bad "self_host/main.ax emitted $shd string headers; the floor is 2000 - this check has stopped seeing the program"
  elif [[ "$sst" -gt 20 ]]; then
    bad "$sst static releases in the compiler's own IR; the cap is 20 (5 on 2026-08-31, from paths with no AST node to ask)"
  else
    ok "$sst static release(s) over $shd headers, against 5762 before 2026-08-31 ($stot release sites total, was 10849)"
  fi
fi

# ---------------------------------------------------------------
# 4. The ablation: turn the predicate's answer off and rebuild.
# ---------------------------------------------------------------
echo "== ablation: isStaticSentinelNode answering 0 puts them all back =="
abl="$work/tree"
mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/" || {
  echo "FAIL: could not copy the tree to ablate" >&2; exit 1; }

# The one answer the fix turns on. The predicate keeps existing and
# keeps being called; it just never fires - so an ablation that broke
# the build would read differently from one that restored the defect.
python3 - "$abl/self_host/codegen.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = """(pub fn (isStaticSentinelNode cg e)
  (if (== e 0)
    0
    (if (== (nodeTag e) TAG_E_STR)
      1
      0
    )
  )
)"""
new = """(pub fn (isStaticSentinelNode cg e)
  (if (== e 0)
    0
    (if (== (nodeTag e) TAG_E_STR)
      0
      0
    )
  )
)"""
if s.count(old) != 1:
    sys.exit("the ablation matched %d times, wanted 1" % s.count(old))
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
if [[ $? -ne 0 ]]; then
  bad "could not apply the ablation - isStaticSentinelNode has moved, and this gate is asserting nothing"
else
  if ! AXIOM_STDLIB="$abl/stdlib" "$axc" build "$abl/self_host/main.ax" \
       -o "$work/axc-ablated" >"$work/ablated.build.log" 2>&1; then
    bad "the ablated compiler did not build"
    sed 's/^/     /' "$work/ablated.build.log" | head -20
  elif ! "$work/axc-ablated" emit-llvm "$repo_root/self_host/main.ax" \
       -o "$work/abl.ll" >"$work/abl.emit.log" 2>&1; then
    bad "the ablated compiler did not emit"
    sed 's/^/     /' "$work/abl.emit.log" | head -20
  else
    read -r ast atot ahd <<<"$(count_static_releases "$work/abl.ll")"
    if [[ "$ast" -lt 1000 ]]; then
      bad "the ablated compiler emitted only $ast static releases; it should be thousands, so this gate is not measuring what it claims"
    else
      ok "ablated: $ast static releases (against $sst from the tree) - the predicate is what removes them"
    fi
    # AND THE FIXTURE, which is what keeps check 1 from being vacuous.
    # It asserts a zero, and a fixture that reached neither guarded site
    # would produce a zero too. The ablated compiler must find both.
    checks=$((checks + 1))
    if "$work/axc-ablated" emit-llvm "$work/lit.ax" -o "$work/lit-abl.ll" \
         >"$work/lit-abl.log" 2>&1; then
      read -r lst _ltot _lhd <<<"$(count_static_releases "$work/lit-abl.ll")"
      if [[ "$lst" -lt 2 ]]; then
        bad "the ablated compiler emitted $lst static release(s) for the fixture; wanted 2 - the fixture no longer reaches both guarded sites, so check 1 above is vacuous"
      else
        ok "ablated: the fixture emits $lst static releases, so both guarded positions are live"
      fi
    else
      bad "the ablated compiler could not re-emit the fixture"
      sed 's/^/     /' "$work/lit-abl.log" | head -20
    fi
  fi
fi

echo
if (( failed )); then
  echo "check-static-release: $failed check(s) failed"
  exit 1
fi
echo "check-static-release: $checks checks passed"
