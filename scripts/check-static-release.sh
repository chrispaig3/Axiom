#!/usr/bin/env bash
# Checks that no release is emitted for a static string literal, and that
# one predicate, `isStaticSentinelNode`, is what removes it.
#
# The `MM-LIFE-2b` header sits at handle-16 on every counted block. For a
# bare string literal the block is a `@strhdr_*` constant whose count word
# is the sentinel `-1`, so `@axiom_release` loads the count, sees `-1` and
# returns. Such a call can never free anything. Without the elision the
# compiler's own IR has thousands of them; with it the binary is smaller
# and its output unchanged.
#
# Why not make `valueOwnedRef` answer 0 for `TAG_E_STR`: it answers 1 so
# that `(if c "lit" (mkStr))` stays owned and the other branch's share is
# given back. Answering 0 would leak that share. Instead,
# `isStaticSentinelNode` is asked only at the four sites that release a
# value that is itself the literal: argument, field, `let` scope end and
# tail-call temporary. Check 2 guards the join.
#
# The ablation flips `isStaticSentinelNode`'s answer for `TAG_E_STR` to 0
# in a copy of the tree, rebuilds the compiler, and requires the count to
# climb back into the thousands. A count no ablation can move is not
# evidence. It costs one extra compiler build, as
# `check-fallible-reclaim.sh` does.
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

# Count `axiom_release` sites whose operand is defined in the same
# function by a `ptrtoint ... @strhdr_*`, the only static-string form
# `emitStrExpr` writes. Prints "<static> <total> <hdrs>".
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
# 1. A fixture with a literal in each guarded position.
# ---------------------------------------------------------------
# `argOf` puts one in argument position (`releaseOwnedArgs`), `Box` in a
# constructor field (the block-construction store), `letOf` in a `let`
# binding (the scope-end release in `emitLetAt`) and `tailOf` in a self
# tail call (the temporary `releaseTailTemps` hands back). None may emit
# a release.
echo "== a literal in argument, field, let and tail position emits no release =="
cat > "$work/lit.ax" <<'AX'
(import Str)

(struct Box (label : String) (n : Int))

(:: argOf (-> Int Int))

(fn (argOf n) (strLen (strDup "in argument position")))

(:: boxOf (-> Int Int))

(fn (boxOf n) (cast Int (Box "in field position" n)))

(:: letOf (-> Int Int))

(fn (letOf n) (let ((s "in let position")) (strLen s)))

(:: tailOf (-> Int String Int))

(fn (tailOf n acc)
  (if (<= n 0)
    (strLen acc)
    (tailOf (- n 1) "in tail position")))

(:: main Int)

(fn (main) (- (+ (argOf 1) (+ (letOf 1) (tailOf 3 "seed"))) (boxOf 1)))
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
# 2. The join stays owned, which the obvious fix would break.
# ---------------------------------------------------------------
# `valueOwnedRef` treats `(if c "lit" (strDup ...))` as owned because the
# literal answers 1 there. Making it answer 0 for TAG_E_STR would silently
# leak the other arm's share, so the join must still emit a release.
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
# 3. The compiler's own IR, the largest Axiom program in the tree.
# ---------------------------------------------------------------
# Every release path that holds an AST node asks the predicate, so any
# static release here is a missed elision and the cap is 0. The census is
# syntactic: it sees operands defined by a literal. A static value behind
# a `load`, such as a literal passed into a parameter slot, has no node
# and is out of its scope. The header floor stops a compiler that emits
# no literals at all from passing.
echo "== the compiler's own IR: zero static releases =="
if ! "$axc" emit-llvm "$repo_root/self_host/main.ax" -o "$work/self.ll" >"$work/self.log" 2>&1; then
  bad "could not emit IR for self_host/main.ax"
  sed 's/^/     /' "$work/self.log" | head -20
else
  read -r sst stot shd <<<"$(count_static_releases "$work/self.ll")"
  if [[ "$shd" -lt 2000 ]]; then
    bad "self_host/main.ax emitted $shd string headers; the floor is 2000 - this check has stopped seeing the program"
  elif [[ "$sst" != 0 ]]; then
    bad "$sst static release(s) in the compiler's own IR; the cap is 0 - a missed elision, or a new nodeless path to name"
  else
    ok "0 static releases over $shd headers, against 5762 before 2026-08-31 ($stot release sites total, was 10849)"
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

# Flip the one answer the fix turns on. The predicate still exists and
# still runs, so a broken build reads differently from a restored defect.
python3 - "$abl/self_host/codegen.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
# `old` follows the formatter's spelling, closers folded onto the last
# line. Only the `1` for TAG_E_STR changes.
old = """(pub fn (isStaticSentinelNode cg e)
  (if (== e 0)
    0
    (if (== (nodeTag e) TAG_E_STR)
      1
      0)))"""
new = """(pub fn (isStaticSentinelNode cg e)
  (if (== e 0)
    0
    (if (== (nodeTag e) TAG_E_STR)
      0
      0)))"""
if s.count(old) != 1:
    sys.exit("the ablation matched %d times, wanted 1" % s.count(old))
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
if [[ $? -ne 0 ]]; then
  bad "could not apply the ablation - isStaticSentinelNode has moved, and this gate is asserting nothing"
else
  if ! gate_build_tree "$axc" "$abl" "$abl/stdlib" \
       "$work/axc-ablated" >"$work/ablated.build.log" 2>&1; then
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
    # The fixture too: check 1 asserts a zero, which a fixture reaching
    # none of the guarded sites would also produce. The ablated compiler
    # must find all four.
    checks=$((checks + 1))
    if "$work/axc-ablated" emit-llvm "$work/lit.ax" -o "$work/lit-abl.ll" \
         >"$work/lit-abl.log" 2>&1; then
      read -r lst _ltot _lhd <<<"$(count_static_releases "$work/lit-abl.ll")"
      if [[ "$lst" -lt 4 ]]; then
        bad "the ablated compiler emitted $lst static release(s) for the fixture; wanted 4 - the fixture no longer reaches all four guarded sites, so check 1 above is vacuous"
      else
        ok "ablated: the fixture emits $lst static releases, so all four guarded positions are live"
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
