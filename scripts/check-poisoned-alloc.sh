#!/usr/bin/env bash
# Build and run the compiler with reusable freed payloads poisoned.
# The witness establishes that the flag changes freeing, while allocation
# still returns zeroed storage. Independent poisoned generations must
# emit the same IR; this also works when a host linker stamps binaries.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

checks=0
ok() { checks=$((checks + 1)); echo "ok   $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }
build() {
  local compiler="$1" output="$2"; shift 2
  if ! "$compiler" --diagnostic-format=ai "$@" build core/main.ax -o "$output" >"$output.log" 2>&1; then
    head -12 "$output.log" >&2
    fail "could not build $output"
  fi
}
mkdir -p "$work/p"
cat > "$work/p/witness.ax" <<'AX'
(import IO)
(import Str)

(:: readWord (-> Int Int))
;@axiom:effect(unsafe)
(fn (readWord a) (__load64 a 0))

(:: dropIt (-> Int ()))
;@axiom:effect(unsafe)
(fn (dropIt a) { (__release a) () })

(:: main ())
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (main)
  { (let s (strDup "freed-value-12345678"))
    {
      (dropIt (as s Int))
      { (let word (readWord (as s Int))) (println "{word}")}
    }})
AX
for mode in plain poison; do
  flags=(--diagnostic-format=ai)
  [[ "$mode" == poison ]] && flags+=(--alloc-poison)
  "$axiom" "${flags[@]}" build "$work/p/witness.ax" -o "$work/p/$mode" >"$work/p/$mode.log" 2>&1 \
    || { head -12 "$work/p/$mode.log" >&2; fail "the $mode witness did not build"; }
done
plain="$("$work/p/plain")"
poison="$("$work/p/poison")"
[[ "$plain" == 20 && "$poison" == -6510615555426900571 ]] \
  || fail "freed word: plain=$plain poison=$poison; expected 20 and the poison pattern"
ok "the witness reads its former length normally and the poison pattern under the flag"

cat > "$work/p/zero.ax" <<'AX'
(import Str)
(:: main Int)
;@axiom:effect(unsafe)
(fn (main)
  { (let s (strDup "reusable")) (let p (as s Int))
    {
      (__release p)
      { (let q (__alloc 24))
        (if (&& (== p q) (== (__load64 q 0) 0)) 42 1)}
    }})
AX
"$axiom" --diagnostic-format=ai --alloc-poison build "$work/p/zero.ax" -o "$work/p/zero" >"$work/p/zero.log" 2>&1 \
  || fail "the zeroed-allocation witness did not build"
rc=0; "$work/p/zero" || rc=$?
[[ "$rc" == 42 ]] || fail "a poisoned build's allocation was not zeroed (exit $rc)"
ok "a reused allocation in a poisoned build returns zeroed memory"

build "$axiom" "$work/stage1" --alloc-poison
ok "the provisioned compiler builds a poisoned stage1"
build "$work/stage1" "$work/stage2" --alloc-poison
ok "poisoned stage1 builds poisoned stage2"
build "$work/stage2" "$work/stage3" --alloc-poison
ok "poisoned stage2 builds poisoned stage3"
for stage in stage2 stage3; do
  "$work/$stage" --diagnostic-format=ai --alloc-poison emit-llvm core/main.ax -o "$work/$stage.ll" \
    >"$work/$stage.emit.log" 2>&1 || { head -12 "$work/$stage.emit.log" >&2; fail "$stage could not emit itself"; }
done
cmp -s "$work/stage2.ll" "$work/stage3.ll" || fail "the poisoned generations emit different IR"
grep -qF 'store i64 -6510615555426900571' "$work/stage3.ll" || fail "the compared compiler IR contains no poison stores"
ok "two poisoned generations emit identical IR containing the poison stores"

cat > "$work/p/hello.ax" <<'AX'
(import IO)
(:: main Int)
;@axiom:effect(io)
(fn (main) { (println "poisoned") 42 })
AX
"$work/stage3" --diagnostic-format=ai --alloc-poison build "$work/p/hello.ax" -o "$work/p/hello" >"$work/p/hello.log" 2>&1 \
  || fail "the poisoned compiler could not build hello"
rc=0; out="$("$work/p/hello")" || rc=$?
[[ "$rc" == 42 && "$out" == poisoned ]] || fail "hello answered exit=$rc output=$out"
ok "a program built by the poisoned compiler prints its message and exits 42"
echo "check-poisoned-alloc: $checks checks passed"
