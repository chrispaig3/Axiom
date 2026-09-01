#!/usr/bin/env bash
# Assert that `;@axiom:pre(...)` and `;@axiom:post(...)` are CHECKED -
# statically where the compiler can decide, and at RUN TIME where it
# cannot - and that a compiler which stops doing either fails here
# rather than passing in silence.
#
# WHY THIS GATE IS NOT A SECTION OF `check-restrictions.sh`. A
# restriction is a claim the checker refutes from analysis it already
# performs, and `check-restrictions.sh` section 1 spends its largest
# section proving that a restriction "changes no emitted byte". A
# contract is the opposite kind of claim: this compiler has no value
# analysis at all, so `(> n 0)` about an unseen caller cannot be
# decided, and the only honest enforcement is a check compiled INTO the
# body. Those two invariants contradict each other by construction, and
# a gate whose sections disagree about what it is asserting is worse
# than two gates. `docs/contracts-design.md` is the design note.
#
# Six sections, each with the negative probe that proves it can go red,
# because `CONTRIBUTING.md`'s rule is that a gate can only see what it
# actually looks at:
#
#   1. A VIOLATED CONTRACT ABORTS, WITH ITS OWN STATUS AND ITS OWN
#      SENTENCE. A `pre` that does not hold and a `post` that does not
#      hold each exit 75 - a status of its own beside 70/71/72
#      (MM-EXEC-16), 73 (the FFI boundary) and 74 (no syscall ABI) -
#      and write a line on fd 2 naming the KIND, the FUNCTION and the
#      CONTRACT AS WRITTEN. Asserted at every optimisation level, since
#      the check is ordinary emitted code and `opt` is free to move it.
#
#   2. A SATISFIED CONTRACT CHANGES NO ANSWER. The same programs with
#      the contract satisfied exit with the value the body computes,
#      and a copy with every contract tag DELETED emits the same answer
#      - so a contract that holds is invisible to the program, which
#      is the half section 1 cannot state.
#
#   3. THE SYMBOL IS DEFINED WHERE IT IS CALLED. A program with a
#      contract emits `call ... @__axiom_contract_fail` AND
#      `define internal ... @__axiom_contract_fail`. `emitDivTrap`'s
#      own note records the failure this closes: a runtime helper
#      emitted only when the program looks like it needs one is a call
#      to a symbol nothing defines, found at `opt` rather than here.
#      A program with NO contract must still define it and must not
#      call it.
#
#   4. THE STATIC HALF ANSWERS, AND THE CONTROLS ARE SILENT.
#      `tests/diagnostics/384-contract-malformed.ax` must draw AX3050
#      on each of its six malformed contracts and NOTHING on any of its
#      controls - `guarded`, `ensured`, `measures`, `onTheSig` and
#      `names` are what keep the rule from being a blanket refusal, and
#      `measures` in particular is the measurement behind the purity
#      rule: `strLen` carries an empty effect row, so a predicate can
#      be written at all.
#
#   5. THE COST IS THE ONE THE DESIGN NAMES. A `pre` does not cost the
#      tail-call rewrite and a `post` does, measured on one
#      self-recursive function three ways: bare and under a `pre` its
#      IR holds no call to itself, and under a `post` it does. That is
#      inherent - a postcondition must observe the result, so the call
#      it wraps is not in tail position - and stating it in a gate is
#      what keeps it from being rediscovered as a regression.
#
#   6. THE COMPILER THAT STOPS ANSWERING IS CAUGHT. Two compilers are
#      built from copies of `self_host/`: one whose `expandProgram` no
#      longer calls `expLowerContracts` (the single lowering hook), and
#      one whose `tcCheckFn` no longer calls `checkContracts` (the
#      single checking hook). Section 1 must fail against the first and
#      section 4 against the second. Without this the whole file is a
#      compiler agreeing with itself.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"

gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { checks=$((checks + 1)); echo "ok   $*"; }
bad() { checks=$((checks + 1)); failed=$((failed + 1)); echo "FAIL $*"; }

# stage1 resolves `(import Foo)` against its working directory, so the
# programs below are compiled from a directory that can see the tree's
# own stdlib - the same link `check-self-host.sh` makes.
ln -s "$repo_root/stdlib" "$work/stdlib"

# `run_prog <compiler> <file> <opt>` -> writes stdout+stderr to
# $work/run.err and answers the exit status.
run_prog() {
  local cc="$1" f="$2" o="$3" rc=0
  ( cd "$work" && "$cc" run --opt "$o" --input "$f" >"$work/run.out" 2>"$work/run.err" ) || rc=$?
  return $rc
}

cat > "$work/pre.ax" <<'AX'
;@axiom:pre((> n 0))
(:: half (-> Int Int))

(fn (half n) (/ n 2))

(:: main Int)

(fn (main) (half 0))
AX

cat > "$work/post.ax" <<'AX'
;@axiom:post((> result 0))
(:: dec (-> Int Int))

(fn (dec n) (- n 1))

(:: main Int)

(fn (main) (dec 1))
AX

cat > "$work/held.ax" <<'AX'
;@axiom:pre((> n 0))
;@axiom:post((>= result 0))
(:: half (-> Int Int))

(fn (half n) (/ n 2))

(:: main Int)

(fn (main) (half 40))
AX

# ---------------------------------------------------------------
echo "== 1. a violated contract exits 75 and says which contract =="
# ---------------------------------------------------------------
# `section1 <compiler>` -> 0 when every claim holds, 1 otherwise. It is
# a function so that section 6 can run the SAME claims against an
# ablated compiler and require them to fail.
section1() {
  local cc="$1" quiet="${2:-0}" bad_here=0 o rc
  for o in 0 1 2 3; do
    rc=0; run_prog "$cc" pre.ax "$o" || rc=$?
    if (( rc != 75 )); then
      (( quiet )) || bad "a violated \`pre\` at --opt $o exits $rc, not 75"
      bad_here=1
    elif ! grep -qF 'axiom: precondition failed in `half`: (> n 0)' "$work/run.err"; then
      (( quiet )) || bad "a violated \`pre\` at --opt $o does not name itself on fd 2: $(head -1 "$work/run.err")"
      bad_here=1
    else
      (( quiet )) || ok "a violated \`pre\` at --opt $o exits 75 and names \`half\` and \`(> n 0)\`"
    fi

    rc=0; run_prog "$cc" post.ax "$o" || rc=$?
    if (( rc != 75 )); then
      (( quiet )) || bad "a violated \`post\` at --opt $o exits $rc, not 75"
      bad_here=1
    elif ! grep -qF 'axiom: postcondition failed in `dec`: (> result 0)' "$work/run.err"; then
      (( quiet )) || bad "a violated \`post\` at --opt $o does not name itself on fd 2: $(head -1 "$work/run.err")"
      bad_here=1
    else
      (( quiet )) || ok "a violated \`post\` at --opt $o exits 75 and names \`dec\` and \`(> result 0)\`"
    fi
  done
  return $bad_here
}
section1 "$axc" || true

# ---------------------------------------------------------------
echo "== 2. a satisfied contract changes no answer =="
# ---------------------------------------------------------------
# The tags DELETED, not the file rewritten: the two programs differ by
# exactly the two comment lines, so a difference in the answer is the
# contract's and nothing else's.
grep -v '^;@axiom:' "$work/held.ax" > "$work/held-untagged.ax"
rc_t=0; run_prog "$axc" held.ax 1        || rc_t=$?
rc_u=0; run_prog "$axc" held-untagged.ax 1 || rc_u=$?
if (( rc_t == 20 && rc_u == 20 )); then
  ok "a satisfied \`pre\`+\`post\` answers 20, and so does the same program with the tags deleted"
else
  bad "tagged exits $rc_t and untagged exits $rc_u; both must be 20"
fi

# ---------------------------------------------------------------
echo "== 3. @__axiom_contract_fail is defined wherever it is called =="
# ---------------------------------------------------------------
( cd "$work" && "$axc" emit-llvm --input held.ax > "$work/held.ll" 2>/dev/null )
( cd "$work" && "$axc" emit-llvm --input held-untagged.ax > "$work/plain.ll" 2>/dev/null )
n_call=$(grep -c 'call i64 @__axiom_contract_fail' "$work/held.ll" || true)
n_def=$(grep -c 'define internal i64 @__axiom_contract_fail' "$work/held.ll" || true)
if (( n_call == 2 && n_def == 1 )); then
  ok "a program with two contracts emits two calls to @__axiom_contract_fail and one definition"
else
  bad "expected 2 calls and 1 definition of @__axiom_contract_fail, found $n_call and $n_def"
fi
n_call0=$(grep -c 'call i64 @__axiom_contract_fail' "$work/plain.ll" || true)
n_def0=$(grep -c 'define internal i64 @__axiom_contract_fail' "$work/plain.ll" || true)
if (( n_call0 == 0 && n_def0 == 1 )); then
  ok "a program with no contract calls it nowhere and still defines it (emitted unconditionally, like the division trap)"
else
  bad "a contract-free program has $n_call0 calls and $n_def0 definitions; expected 0 and 1"
fi

# ---------------------------------------------------------------
echo "== 4. the static half answers, and the controls are silent =="
# ---------------------------------------------------------------
fixture="tests/diagnostics/384-contract-malformed.ax"
# The six declarations whose contract must be refused, and the five
# whose contract must not be mentioned by ANY code - not just by
# AX3050, so that a control breaking some other way is caught here too.
refused=(wrongType notOne noValue resultInPre noSignature allocates)
controls=(guarded ensured measures onTheSig names)

section4() {
  local cc="$1" quiet="${2:-0}" bad_here=0 d n
  ( cd "$repo_root" && "$cc" --diagnostic-format=ai check --input "$fixture" ) \
      >"$work/fx.out" 2>"$work/fx.err" || true
  grep -E '^[EW] ' "$work/fx.err" > "$work/fx.axdl" || true
  n=$(grep -c '^E AX3050 ' "$work/fx.axdl" || true)
  if (( n == 6 )); then
    (( quiet )) || ok "384 draws six AX3050s"
  else
    (( quiet )) || bad "384 draws $n AX3050s, expected 6"
    bad_here=1
  fi
  # Each refusal names its own declaration, or - for the three whose
  # message leads with the offending TEXT rather than the name - is
  # anchored by its line. The line is read out of the fixture so that
  # editing the fixture cannot silently retarget the check.
  for d in "${refused[@]}"; do
    local ln
    ln=$(grep -n "^(fn ($d " "$repo_root/$fixture" | head -1 | cut -d: -f1)
    if [[ -z "$ln" ]]; then
      (( quiet )) || bad "the fixture no longer declares \`$d\`"
      bad_here=1
      continue
    fi
    # The tag sits above the `::` above the `fn`, within the four lines
    # before it. The line is read out of the fixture rather than
    # written down here, so editing the fixture cannot silently
    # retarget the check at a line that no longer holds the contract.
    if grep -E "^E AX3050 [^ ]*:($((ln - 4))|$((ln - 3))|$((ln - 2))|$((ln - 1))):" "$work/fx.axdl" >/dev/null; then
      (( quiet )) || ok "\`$d\`'s contract is refused"
    else
      (( quiet )) || bad "\`$d\`'s contract draws no AX3050 (fn at line $ln)"
      bad_here=1
    fi
  done
  for d in "${controls[@]}"; do
    if grep -qF "\`$d\`" "$work/fx.axdl"; then
      (( quiet )) || bad "the control \`$d\` is named by a diagnostic: $(grep -F "\`$d\`" "$work/fx.axdl" | head -1)"
      bad_here=1
    else
      (( quiet )) || ok "the control \`$d\` draws nothing"
    fi
  done
  return $bad_here
}
section4 "$axc" || true

# ---------------------------------------------------------------
echo "== 5. a \`pre\` keeps the tail-call rewrite and a \`post\` spends it =="
# ---------------------------------------------------------------
# One function, three ways. `tailCallsSelf` rewrites a self tail call
# into a loop, so the IR of the bare and `pre`-tagged versions holds no
# `call ... @loop`; a `post` binds the body to `result` and the call
# moves into a `let` INITIALISER, which is not a tail position.
mk_loop() {  # <tag-lines> <out>
  { printf '%s' "$1"
    cat <<'AX'
(:: loop (-> Int Int Int))

(fn (loop n acc) (if (== n 0) acc (loop (- n 1) (+ acc 1))))

(:: main Int)

(fn (main) (loop 3 0))
AX
  } > "$2"
}
mk_loop ""                              "$work/loop-bare.ax"
mk_loop ";@axiom:pre((>= n 0))"$'\n'    "$work/loop-pre.ax"
mk_loop ";@axiom:post((>= result 0))"$'\n' "$work/loop-post.ax"
for v in bare pre post; do
  ( cd "$work" && "$axc" emit-llvm --input "loop-$v.ax" > "$work/loop-$v.ll" 2>/dev/null )
done
self_bare=$(grep -c 'call i64 @loop(' "$work/loop-bare.ll" || true)
self_pre=$(grep -c 'call i64 @loop(' "$work/loop-pre.ll" || true)
self_post=$(grep -c 'call i64 @loop(' "$work/loop-post.ll" || true)
# One call in every version: `main`'s. The rewrite shows as the ABSENCE
# of a second one, inside `loop` itself.
if (( self_bare == 1 && self_pre == 1 )); then
  ok "a \`pre\` keeps the tail-call rewrite (one @loop call, main's, in both)"
else
  bad "bare has $self_bare @loop calls and \`pre\` has $self_pre; both must be 1"
fi
if (( self_post == 2 )); then
  ok "a \`post\` spends it, as the design says it must (two @loop calls: main's and the recursion)"
else
  bad "\`post\` has $self_post @loop calls, expected 2 - if the rewrite now survives a \`post\`, the design note and docs/reference.md say otherwise and one of them is wrong"
fi

# ---------------------------------------------------------------
echo "== 6. a compiler that stops answering fails sections 1 and 4 =="
# ---------------------------------------------------------------
# `ablate <name> <sed-script> <section>`: build a compiler from a copy
# of `self_host/` with one hook removed, and require the named section
# to FAIL against it. The copy is a copy; nothing here touches the
# tree.
ablate() {
  local name="$1" file="$2" from="$3" to="$4" section="$5"
  local dir="$work/ablate-$name"
  rm -rf "$dir"; mkdir -p "$dir"
  cp -R "$repo_root/self_host" "$dir/self_host"
  cp -R "$repo_root/stdlib" "$dir/stdlib"
  if ! grep -qF "$from" "$dir/self_host/$file"; then
    bad "ablation \`$name\`: \`$from\` is not in self_host/$file any more, so this probe watches nothing"
    return
  fi
  python3 - "$dir/self_host/$file" "$from" "$to" <<'PY'
import sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
assert s.count(a) == 1, (p, s.count(a))
open(p, 'w').write(s.replace(a, b))
PY
  if ! ( cd "$dir" && AXIOM_STDLIB="$dir/stdlib" "$axc" build --input self_host/main.ax -o "$dir/axc" ) >"$dir/build.log" 2>&1; then
    bad "ablation \`$name\`: the ablated compiler did not build"
    head -20 "$dir/build.log"
    return
  fi
  if "$section" "$dir/axc" 1; then
    bad "ablation \`$name\`: section ${section#section} still PASSES with the hook removed - it watches nothing"
  else
    ok "ablation \`$name\`: section ${section#section} goes red with the hook removed"
  fi
}

ablate "no-lowering" expand.ax \
  "(expLowerContracts decls (contractSigIndex decls) 0)" \
  "0" \
  section1

# The call site and not the definition: `(checkContracts tc d resTy)`
# is also the `fn`'s own header, so the anchor carries the call site's
# indentation and the replacement asserts it matched exactly once.
ablate "no-checking" typecheck.ax \
  "              (checkContracts tc d resTy)" \
  "              0" \
  section4

echo
if (( failed )); then
  echo "FAILED: $failed of $checks checks"
  exit 1
fi
echo "PASSED: $checks checks"
