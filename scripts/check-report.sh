#!/usr/bin/env bash
# The resource report and the restricted profile (R-D1): what
# `scripts/axiom-report.py` reads off the compiler, what it refuses,
# and the stack bound it computes from machine code.
#
# The tool's docstring is the scope statement of record. This gate
# holds it to five things, and to an ablation for each rule:
#
#   1. The bound algorithm on graphs answered by hand (`--selftest`):
#      a call chain sums, a diamond takes the heavier arm, a tail call
#      replaces its caller's frame, a cycle of tail calls is a loop, a
#      cycle through a call is unbounded, and code with no frame size
#      is unbounded - whatever order the roots are visited in.
#   2. Facts read off `symbols --calls`: the per-function marks of a
#      program that has one of everything (allocation, IO, recursion
#      direct and mutual, a call through a parameter, a spawn, an isr),
#      compared exactly - and `#extern`, the compiler's own marker.
#   3. The profile: tests/profile/ok-*.ax pass with exit 0; each
#      tests/profile/rpN-*.ax is refused with exit 1 by exactly the rule
#      its name gives, and by no other.
#   4. The stack bound, where llc can build an AArch64 ELF object: the
#      conforming program and tests/embedded/blink.ax are bounded under
#      the 8 KiB the baremetal-aarch64 link reserves; tree recursion is
#      unbounded; a 64-byte budget is refused; every reported bound is
#      the sum of the frames on its own path; and the tool's ELF reader
#      agrees with `llvm-readobj --stack-sizes`, an independent parser,
#      on every function's frame (SKIP, named, where llvm-readobj is
#      absent - never a pass).
#   5. Ablations: a copy of the tool with one rule's refusal disabled
#      must stop refusing that rule's fixture (so the fixture is caught
#      by the rule it names, not by accident), and a copy whose bound
#      treats calls as tail calls must call tree recursion bounded (so
#      section 4's unbounded verdict is the algorithm's, not luck).
#
# What a green run does NOT show: that a bounded stack is a bounded
# latency (it is not; nothing here is a WCET bound), that traps are
# enumerated (they are not), or anything about targets other than
# AArch64 ELF for the stack half.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
skipped=0
ok()   { echo "ok   $*"; checks=$((checks + 1)); }
bad()  { echo "FAIL $*"; failed=$((failed + 1)); }
skip() { echo "SKIP $*"; skipped=$((skipped + 1)); }

tool="$repo_root/scripts/axiom-report.py"
fxdir="$repo_root/tests/profile"
blink="$repo_root/tests/embedded/blink.ax"
[[ -f "$tool" ]] || { echo "FAIL: $tool is missing"; exit 1; }
[[ -f "$blink" ]] || { echo "FAIL: $blink is missing"; exit 1; }
nfx=$(ls "$fxdir"/*.ax 2>/dev/null | wc -l | tr -d ' ')
(( nfx >= 6 )) || { echo "FAIL: $fxdir holds $nfx fixtures, fewer than the 6 this gate reads"; exit 1; }

report() {  # report <tool> <out-json> <args...>: exit status of the tool
  local t="$1" out="$2"; shift 2
  python3 "$t" --axiom "$axc" --format json "$@" > "$out" 2> "$out.err"
}
rules_of() {  # the sorted, de-duplicated refusal rules in a JSON report
  python3 -c 'import json,sys; print(" ".join(sorted(set(r["rule"] for r in json.load(open(sys.argv[1]))["refusals"]))))' "$1"
}

echo "== 1. the bound algorithm on graphs answered by hand =="
if python3 "$tool" --selftest > "$work/self.out" 2>&1; then
  ok "selftest: $(tail -1 "$work/self.out")"
else
  bad "selftest:"; sed 's/^/     /' "$work/self.out"
fi

echo
echo "== 2. facts read off the compiler =="
cat > "$work/facts.ax" <<'AX'
(import IO)
(import Vec)

(:: countdown (-> Int Int))
(fn (countdown n)
  (if (<= n 0)
    0
    (countdown (- n 1))))

(:: ping (-> Int Int))
(fn (ping n)
  (if (<= n 0)
    0
    (pong (- n 1))))

(:: pong (-> Int Int))
(fn (pong n)
  (ping n))

(:: apply (-> (-> Int Int) Int Int))
(fn (apply f x)
  (f x))

(:: build (-> Int (Vec Int)))
(fn (build n)
  (let ((v vecNew))
    {
      (vecPush v n)
      v
    }))

;@axiom:isr
(fn (tick)
  0)

; Two effect tags render as two `#effect=` keys, and `unsafe` FIRST here,
; so a reader keeping only the last key would lose the direct-Unsafe mark.
(:: peek (-> Int Int))
;@axiom:effect(unsafe)
;@axiom:effect(io)
(fn (peek a)
  {
    (println "peek")
    (__load64 a 0)
  })

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println "hi")
    (countdown 3)
    (ping 4)
    (apply (fn (x) (+ x 1)) 2)
    (vecLen (build 3))
    (tick)
    (peek 0)
    (parallel p ((a (+ 1 2)) (b (+ 3 4)))
      (+ a b))
  })
AX
report "$tool" "$work/facts.json" "$work/facts.ax"; rc=$?
if [[ "$rc" != 0 ]]; then
  bad "facts: the tool exited $rc without a profile (only refusals may make it non-zero):"
  head -5 "$work/facts.json.err" | sed 's/^/     /'
else
  # name -> the marks the text renderer prints: A I U X R ~ S K
  python3 - "$work/facts.json" > "$work/facts.marks" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
rec = set(q for c in r['cycles'] for q in c)
for q in sorted(r['functions']):
    fa = r['functions'][q]
    print(q, ''.join([
        'A' if fa['alloc'] else '.', 'I' if fa['io'] else '.', 'U' if fa['unsafe'] else '.',
        'X' if fa['extern'] else '.', 'R' if q in rec else '.', '~' if fa['indirect'] else '.',
        'S' if (fa['spawn'] or fa['join']) else '.', 'K' if fa['kernel'] else '.'])
          + (' isr' if fa['isr'] else ''))
print('roots', ','.join(r['roots']))
PY
  while read -r name want; do
    got="$(grep -E "^$(printf '%s' "$name" | sed 's/[$.]/\\&/g') " "$work/facts.marks" | cut -d' ' -f2-)"
    if [[ "$got" == "$want" ]]; then
      ok "facts: $name $want"
    else
      bad "facts: $name is [$got], wanted [$want]"
    fi
  done <<'ROWS'
countdown ....R...
ping ....R...
pong ....R...
apply .....~..
build A.......
tick ........ isr
main AI....S.
peek AIU.....
Mem$memAlloc A.U.....
Sys$sysWriteFd AI.....K
roots main,tick
ROWS
fi
# `#extern` is the compiler's own marker: without it an extern row is a
# function with no calls and `#effects=IO`, which is also what a body
# writing one syscall looks like.
"$axc" --diagnostic-format=ai symbols --calls "$fxdir/rp3-foreign.ax" > "$work/ext.sym" 2>&1
if grep -qE '^F add .*#extern' "$work/ext.sym" && ! grep -qE '^F main .*#extern' "$work/ext.sym"; then
  ok "symbols marks the extern item #extern, and only it"
else
  bad "symbols does not mark the extern item alone:"; grep -E '^F (add|main) ' "$work/ext.sym" | sed 's/^/     /'
fi

echo
echo "== 3. the profile: conforming programs pass, each rule refuses its fixture =="
# fixture, extra args, the exact rule set (or 'none')
while IFS='|' read -r fx extra want; do
  [[ -z "$fx" ]] && continue
  # shellcheck disable=SC2086
  report "$tool" "$work/p-$fx.json" "$fxdir/$fx" --profile restricted $extra; rc=$?
  if [[ "$rc" == 2 ]]; then
    bad "$fx: the tool could not answer:"; head -5 "$work/p-$fx.json.err" | sed 's/^/     /'; continue
  fi
  got="$(rules_of "$work/p-$fx.json")"; [[ -z "$got" ]] && got=none
  wrc=1; [[ "$want" == none ]] && wrc=0
  if [[ "$got" == "$want" && "$rc" == "$wrc" ]]; then
    ok "$fx${extra:+ ($extra)}: refusals [$got], exit $rc"
  else
    bad "$fx${extra:+ ($extra)}: refusals [$got] exit $rc, wanted [$want] exit $wrc"
  fi
done <<'ROWS'
ok-periodic.ax||none
rp1-recursion.ax||RP-1
rp2-indirect.ax||RP-2
rp3-foreign.ax||RP-3
rp3-foreign.ax|--allow-foreign add|none
rp4-spawn.ax||RP-4
rp5-steady.ax|--steady step|RP-5
rp5-steady.ax||none
ROWS

echo
echo "== 4. the stack bound, from AArch64 machine code =="
bm=baremetal-aarch64
if ! command -v llc >/dev/null 2>&1 || ! command -v opt >/dev/null 2>&1; then
  skip "llc/opt not on PATH: the stack half cannot build its object here"
else
  for fx in "$fxdir/ok-periodic.ax" "$blink"; do
    n="$(basename "$fx")"
    report "$tool" "$work/s-$n.json" "$fx" --target $bm --profile restricted --stack --stack-budget 8192 --keep; rc=$?
    b="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))["stack"]["results"]["_start"]; print(r["bytes"] if r["bounded"] else "UNBOUNDED")' "$work/s-$n.json" 2>/dev/null)"
    if [[ "$rc" == 0 && "$b" =~ ^[0-9]+$ ]] && (( b > 0 && b <= 8192 )); then
      ok "$n: bounded at $b bytes from _start, under the 8 KiB the link reserves, no refusal"
    else
      bad "$n: exit $rc, bound [$b]:"; head -5 "$work/s-$n.json.err" | sed 's/^/     /'
    fi
  done
  report "$tool" "$work/s-fib.json" "$fxdir/rp1-recursion.ax" --target $bm --profile restricted --stack; rc=$?
  got="$(rules_of "$work/s-fib.json" 2>/dev/null)"
  if [[ "$rc" == 1 && "$got" == "RP-1 RP-7" ]]; then
    ok "rp1-recursion.ax under --stack: tree recursion is unbounded (RP-1 RP-7)"
  else
    bad "rp1-recursion.ax under --stack: exit $rc, refusals [$got], wanted RP-1 RP-7"
  fi
  report "$tool" "$work/s-budget.json" "$blink" --target $bm --profile restricted --stack --stack-budget 64; rc=$?
  if [[ "$rc" == 1 ]] && grep -q 'over the 64-byte budget' "$work/s-budget.json"; then
    ok "blink.ax against a 64-byte budget: refused as RP-7, over budget"
  else
    bad "blink.ax against a 64-byte budget: exit $rc, not refused as over budget"
  fi
  # Self-consistency: every bound is the sum of the frames on its own
  # path. A plain step contributes its frame; a tail step (`f~>`) and a
  # loop member reaching the loop's heaviest member (`f ~(loop)~>`)
  # contribute nothing, because their frame is gone by then.
  for n in ok-periodic.ax blink.ax; do
    if python3 - "$work/s-$n.json" > "$work/sum-$n.out" 2>&1 <<'PY'
import json, sys
st = json.load(open(sys.argv[1]))['stack']
fr = st['frames']
for root, res in st['results'].items():
    if not res['bounded']:
        continue
    total = sum(fr[f] for f in res['path'] if not f.endswith('~>'))
    if total != res['bytes']:
        print('%s: bound %d, but its path sums to %d' % (root, res['bytes'], total))
        sys.exit(1)
    print('%s: %d = %s' % (root, total, ' + '.join('%s(%d)' % (f, fr[f]) for f in res['path'] if not f.endswith('~>'))))
PY
    then
      ok "$n: the bound is the sum of its path's frames - $(head -1 "$work/sum-$n.out" | cut -c1-150)"
    else
      bad "$n: $(cat "$work/sum-$n.out")"
    fi
  done
  # An independent reader of the same object: every frame the tool read
  # from `.stack_sizes` equals what llvm-readobj says, and it read them
  # all. Two ELF parsers agreeing is the check on the first one.
  readobj="$(command -v llvm-readobj || true)"
  if [[ -z "$readobj" ]]; then
    skip "llvm-readobj not on PATH: the frame reader is not cross-checked here"
    for n in ok-periodic.ax blink.ax; do
      rm -rf "$(dirname "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["stack"]["obj"])' "$work/s-$n.json" 2>/dev/null)")" 2>/dev/null
    done
  else
    for n in ok-periodic.ax blink.ax; do
      objf="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["stack"]["obj"])' "$work/s-$n.json")"
      "$readobj" --stack-sizes "$objf" > "$work/ro-$n.txt" 2>&1
      if python3 - "$work/s-$n.json" "$work/ro-$n.txt" > "$work/ro-$n.out" 2>&1 <<'PY'
import json, re, sys
fr = json.load(open(sys.argv[1]))['stack']['frames']
txt = open(sys.argv[2]).read()
theirs = {}
for fn, sz in re.findall(r'Functions: \[([^\]]+)\]\s*\n\s*Size: (0x[0-9a-fA-F]+)', txt):
    theirs[fn] = int(sz, 16)
if not theirs:
    print('llvm-readobj reported no stack sizes'); sys.exit(1)
diff = sorted(set(fr) ^ set(theirs)) + [f for f in fr if f in theirs and fr[f] != theirs[f]]
if diff:
    print('disagree on %s' % diff[:8]); sys.exit(1)
print('%d functions, every frame equal' % len(fr))
PY
      then
        ok "$n: the tool's .stack_sizes reader agrees with llvm-readobj - $(cat "$work/ro-$n.out")"
      else
        bad "$n: the tool's frames and llvm-readobj's disagree - $(cat "$work/ro-$n.out")"
      fi
      rm -rf "$(dirname "$objf")"
    done
  fi
fi

echo
echo "== 5. ablations: each rule is what refuses its fixture =="
# A copy of the tool with ONE site disabled. The seam is an exact
# string and must match exactly once, or the ablation proves nothing.
ablate() {  # ablate <name> <from> <to>: writes $work/abl-<name>.py
  python3 - "$tool" "$work/abl-$1.py" "$2" "$3" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src).read()
n = s.count(a)
if n != 1:
    print('seam [%s] matches %d times' % (a, n)); sys.exit(1)
open(dst, 'w').write(s.replace(a, b))
PY
}
while IFS='|' read -r rule fx extra; do
  [[ -z "$rule" ]] && continue
  if ! ablate "$rule" "refuse('$rule'," "(lambda *a: None)('$rule',"; then
    bad "ablation $rule: the seam did not match exactly once"; continue
  fi
  # shellcheck disable=SC2086
  report "$work/abl-$rule.py" "$work/a-$rule.json" "$fxdir/$fx" --profile restricted $extra; rc=$?
  got="$(rules_of "$work/a-$rule.json" 2>/dev/null)"
  if [[ "$rc" == 0 && -z "$got" ]]; then
    ok "ablation $rule: with its refusal disabled, $fx passes - the fixture is caught by $rule and nothing else"
  else
    bad "ablation $rule: with its refusal disabled, $fx still exits $rc with [$got]"
  fi
done <<'ROWS'
RP-1|rp1-recursion.ax|
RP-2|rp2-indirect.ax|
RP-3|rp3-foreign.ax|
RP-4|rp4-spawn.ax|
RP-5|rp5-steady.ax|--steady step
ROWS
# The bound: a copy that ignores a call edge inside a cycle - treating
# recursion as if it held no frame - must answer the selftest wrong and
# call tree recursion bounded. Section 4's UNBOUNDED is then the
# algorithm's verdict, not an accident of the graph.
if ablate cycle "elif any(g in cs for g in calls.get(f, ())):" "elif False:"; then
  if python3 "$work/abl-cycle.py" --selftest > "$work/abl-self.out" 2>&1; then
    bad "ablation cycle: the selftest still passes with the call-cycle check removed"
  else
    ok "ablation cycle: the selftest fails - $(grep -c '^FAIL' "$work/abl-self.out") case(s) wrong without the check"
  fi
  if command -v llc >/dev/null 2>&1 && command -v opt >/dev/null 2>&1; then
    report "$work/abl-cycle.py" "$work/a-cycle.json" "$fxdir/rp1-recursion.ax" --target baremetal-aarch64 --stack
    b="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))["stack"]["results"]["_start"]; print(r["bounded"])' "$work/a-cycle.json" 2>/dev/null)"
    if [[ "$b" == "True" ]]; then
      ok "ablation cycle: tree recursion comes out BOUNDED without the check - section 4 is the check's verdict"
    else
      bad "ablation cycle: tree recursion is [$b] without the check; section 4's verdict is not the algorithm's"
    fi
  fi
else
  bad "ablation cycle: the seam did not match exactly once"
fi

echo
if (( failed > 0 )); then
  echo "check-report: $failed of $((checks + failed)) checks failed ($skipped skipped)"
  exit 1
fi
echo "check-report: $checks checks passed, $skipped skipped"
