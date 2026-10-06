#!/usr/bin/env bash
# Check that `;@axiom:pre(...)` and `;@axiom:post(...)` are enforced:
# statically where the compiler can decide, and at run time where it
# cannot. A compiler that stops doing either fails here.
#
# This is its own gate, apart from `check-restrictions.sh`, which proves
# a restriction changes no emitted byte. A contract needs a check
# compiled into the body, because the compiler has no value analysis to
# decide `(> n 0)` about an unseen caller. `docs/reference.md` has the
# design note.
#
# Seven sections, each with a negative probe that shows it can go red:
#
#   1. A violated `pre` or `post` exits 80 at every `--opt` level and
#      names the kind, the function and the contract on fd 2. Inside
#      `__axiom_recover` it answers 80 to the arming call instead
#      (`docs/error-model.md` ERR-REC-6). 80 is the contract trap's own
#      status among those MM-EXEC-16 reserves in `docs/memory-model.md`.
#   2. A satisfied contract changes no answer.
#   3. `@__axiom_contract_fail` is defined where it is called, and
#      nowhere else.
#   4. The static half refuses each malformed contract with AX3050, and
#      the controls draw nothing.
#   5. A `pre` keeps the tail-call rewrite and a `post` spends it.
#   6. A program cannot turn its own contract off.
#   7. Compilers built with a hook removed, or the shape guard put back,
#      fail sections 1, 4 and 6. Without this the file is a compiler
#      agreeing with itself.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"

gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { checks=$((checks + 1)); echo "ok   $*"; }
bad() { checks=$((checks + 1)); failed=$((failed + 1)); echo "FAIL $*"; }

# `run_prog <compiler> <file> <opt>` -> writes stdout to $work/run.out
# and stderr to $work/run.err, and answers the exit status.
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

# Both halves of ERR-REC-6 in one program: the first call is inside a
# recovery point and its status comes back as a value, the second is
# outside every one and ends the program. They share a program for the
# reason `403-recover-div.ax` gives: with `__axiom_recover` unreferenced,
# the armed test folds to false and the trap has no branch to test.
# `@__axiom_contract_fail` opens with `__axiom_recover_abort`, as the
# division trap does.
cat > "$work/recover.ax" <<'AX'
(import IO)

(import Str)

;@axiom:pre((> n 0))
(:: half (-> Int Int))

(fn (half n) (/ n 2))

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let ((inside
    (__axiom_recover
      __axiom_arena_mark      (lambda (x) (half x))
    )
  ))
    {
      (println "recovered {inside}")
      (half 0)
      0
    }
  )
)
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
echo "== 1. a violated contract exits 80 and says which contract =="
# ---------------------------------------------------------------
# `section1 <compiler> [quiet]` answers 0 when every claim holds and 1
# otherwise. Section 7 runs the same claims against an ablated compiler
# and requires them to fail. Every `--opt` level is checked, since the
# check is ordinary emitted code that `opt` may move.
section1() {
  local cc="$1" quiet="${2:-0}" bad_here=0 o rc
  for o in 0 1 2 3; do
    rc=0; run_prog "$cc" pre.ax "$o" || rc=$?
    if (( rc != 80 )); then
      (( quiet )) || bad "a violated \`pre\` at --opt $o exits $rc, not 80"
      bad_here=1
    elif ! grep -qF 'axiom: precondition failed in `half`: (> n 0)' "$work/run.err"; then
      (( quiet )) || bad "a violated \`pre\` at --opt $o does not name itself on fd 2: $(head -1 "$work/run.err")"
      bad_here=1
    else
      (( quiet )) || ok "a violated \`pre\` at --opt $o exits 80 and names \`half\` and \`(> n 0)\`"
    fi

    rc=0; run_prog "$cc" post.ax "$o" || rc=$?
    if (( rc != 80 )); then
      (( quiet )) || bad "a violated \`post\` at --opt $o exits $rc, not 80"
      bad_here=1
    elif ! grep -qF 'axiom: postcondition failed in `dec`: (> result 0)' "$work/run.err"; then
      (( quiet )) || bad "a violated \`post\` at --opt $o does not name itself on fd 2: $(head -1 "$work/run.err")"
      bad_here=1
    else
      (( quiet )) || ok "a violated \`post\` at --opt $o exits 80 and names \`dec\` and \`(> result 0)\`"
    fi
  done

  rc=0; run_prog "$cc" recover.ax 1 || rc=$?
  if (( rc != 80 )); then
    (( quiet )) || bad "the recovery program exits $rc, not 80 - the SECOND violation, outside every recovery point, must still end it"
    bad_here=1
  elif ! grep -qF 'recovered 80' "$work/run.out"; then
    (( quiet )) || bad "a violated contract inside \`__axiom_recover\` did not answer 80 to the arming call: $(head -1 "$work/run.out")"
    bad_here=1
  else
    (( quiet )) || ok "a violated contract inside \`__axiom_recover\` answers 80 to the arming call, and outside one still exits 80"
  fi
  return $bad_here
}
section1 "$axc" || true

# ---------------------------------------------------------------
echo "== 2. a satisfied contract changes no answer =="
# ---------------------------------------------------------------
# Delete the tags instead of rewriting the file: the two programs differ
# by exactly the two comment lines, so any difference in the answer is
# the contract's.
grep -v '^;@axiom:' "$work/held.ax" > "$work/held-untagged.ax"
rc_t=0; run_prog "$axc" held.ax 1        || rc_t=$?
rc_u=0; run_prog "$axc" held-untagged.ax 1 || rc_u=$?
if (( rc_t == 20 && rc_u == 20 )); then
  ok "a satisfied \`pre\`+\`post\` answers 20, and so does the same program with the tags deleted"
else
  bad "tagged exits $rc_t and untagged exits $rc_u; both must be 20"
fi

# ---------------------------------------------------------------
echo "== 3. @__axiom_contract_fail is defined where it is called, and nowhere else =="
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
if (( n_call0 == 0 && n_def0 == 0 )); then
  ok "a program with no contract neither calls nor defines it - the emitter writes it unconditionally and \`pruneDeadDefs\` takes it back out"
else
  bad "a contract-free program has $n_call0 calls and $n_def0 definitions; expected 0 and 0"
fi
# The pruner makes that 0, not a conditional emitter. `emitContractTrap`
# runs unconditionally, beside the division trap, because a helper
# emitted only when the program seems to need it can leave a call to an
# undefined symbol that only `opt` finds. `pruneDeadDefs` then drops
# every `define` no root reaches. The untagged program divides, so its
# division trap must survive; `bare.ax` does nothing, so every
# unconditional helper must go. A conditional `emitContractTrap` would
# pass the count above, and these two notice.
cat > "$work/bare.ax" <<'AX'
(:: main Int)

(fn (main) 7)
AX
( cd "$work" && "$axc" emit-llvm --input bare.ax > "$work/bare.ll" 2>/dev/null )
n_div_used=$(grep -c 'define internal i64 @__axiom_div_by_zero' "$work/plain.ll" || true)
n_div_bare=$(grep -c '@__axiom_div_by_zero' "$work/bare.ll" || true)
n_streq_bare=$(grep -c '@__axiom_str_eq' "$work/bare.ll" || true)
n_ctr_bare=$(grep -c '@__axiom_contract_fail' "$work/bare.ll" || true)
if (( n_div_used == 1 )); then
  ok "a contract-free program that DIVIDES still defines the division trap - the pruner keeps what is reached"
else
  bad "a program that divides has $n_div_used definitions of @__axiom_div_by_zero, expected 1"
fi
if (( n_div_bare == 0 && n_streq_bare == 0 && n_ctr_bare == 0 )); then
  ok "a program that does neither carries none of the three unconditional helpers - so the 0 above is \`pruneDeadDefs\`, not a conditional emitter"
else
  bad "\`(fn (main) 7)\` still mentions the division trap ($n_div_bare), the string-equality helper ($n_streq_bare) or the contract trap ($n_ctr_bare); with the pruner working all three must be 0"
fi

# ---------------------------------------------------------------
echo "== 4. the static half answers, and the controls are silent =="
# ---------------------------------------------------------------
fixture="tests/diagnostics/385-contract-malformed.ax"
# The seven declarations whose contract must be refused, and the five
# controls that no diagnostic may name, so a control breaking some other
# way is caught too. The controls keep the rule from being a blanket
# refusal: `measures` shows a predicate can call `strLen`, whose effect
# row is empty. `constructs` checks that a fieldful `data` constructor
# counts in the effect row the purity rule reads (MM-EXEC-9a).
refused=(wrongType notOne noValue resultInPre noSignature allocates constructs)
controls=(guarded ensured measures onTheSig names)

section4() {
  local cc="$1" quiet="${2:-0}" bad_here=0 d n
  ( cd "$repo_root" && "$cc" --diagnostic-format=ai check --input "$fixture" ) \
      >"$work/fx.out" 2>"$work/fx.err" || true
  grep -E '^[EW] ' "$work/fx.err" > "$work/fx.axdl" || true
  n=$(grep -c '^E AX3050 ' "$work/fx.axdl" || true)
  if (( n == 7 )); then
    (( quiet )) || ok "385 draws seven AX3050s"
  else
    (( quiet )) || bad "385 draws $n AX3050s, expected 7"
    bad_here=1
  fi
  # Each refusal is anchored by its line, because three of the messages
  # lead with the offending text instead of the name. The line is read
  # out of the fixture, so editing the fixture cannot silently retarget
  # the check.
  for d in "${refused[@]}"; do
    local ln
    ln=$(grep -n "^(fn ($d " "$repo_root/$fixture" | head -1 | cut -d: -f1)
    if [[ -z "$ln" ]]; then
      (( quiet )) || bad "the fixture no longer declares \`$d\`"
      bad_here=1
      continue
    fi
    # The tag sits above the `::` above the `fn`, within the four lines
    # before it.
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
# `call ... @loop`. A postcondition must observe the result, so a `post`
# binds the body to `result` and the call moves into a `let`
# initialiser, which is not a tail position.
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
# One call in every version: `main`'s. The rewrite shows as the absence
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

cat > "$work/forge-pre.ax" <<'AX'
;@axiom:pre((> n 0))
(:: half (-> Int Int))

(fn (half n) { (__contract true "never\n") (/ n 2) })

(:: main Int)

(fn (main) (half 0))
AX

cat > "$work/forge-post.ax" <<'AX'
;@axiom:post((> result 0))
(:: dec (-> Int Int))

(fn (dec n) (let ((result (- n 1))) { (__contract true "never\n") result }))

(:: main Int)

(fn (main) (dec 1))
AX

# ---------------------------------------------------------------
echo "== 6. a program cannot turn its own contract off =="
# ---------------------------------------------------------------
# `__contract` is spellable: it is registered in `fns` and intercepted
# in `checkApp`, as `__streq` is. A lowering guard that reads the body's
# shape (a block whose first statement applies `__contract`, under an
# optional `result` binding) would skip the check for any body with that
# shape. Both files below are a violated contract in that shape, and
# both must abort.
section6() {
  local cc="$1" quiet="${2:-0}" bad_here=0 rc
  rc=0; run_prog "$cc" forge-pre.ax 1 || rc=$?
  if (( rc == 80 )); then
    (( quiet )) || ok "a violated \`pre\` still exits 80 with \`__contract\` written first in the body"
  else
    (( quiet )) || bad "a violated \`pre\` whose body opens with \`(__contract ...)\` exits $rc, not 80 - the contract was skipped"
    bad_here=1
  fi
  rc=0; run_prog "$cc" forge-post.ax 1 || rc=$?
  if (( rc == 80 )); then
    (( quiet )) || ok "a violated \`post\` still exits 80 with the body bound to \`result\` around a \`__contract\`"
  else
    (( quiet )) || bad "a violated \`post\` whose body is a \`result\` bind over \`(__contract ...)\` exits $rc, not 80 - the contract was skipped"
    bad_here=1
  fi
  return $bad_here
}
section6 "$axc" || true

# ---------------------------------------------------------------
echo "== 7. a compiler that stops answering fails sections 1, 4 and 6 =="
# ---------------------------------------------------------------
# `ablate <name> <file> <from> <to> <section>`: build a compiler from a
# copy of `self_host/` with `from` replaced by `to` in `file`, and
# require the named section to fail against it. Nothing here touches
# the tree.
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
  if ! gate_build_tree "$axc" "$dir" "$dir/stdlib" "$dir/axc" >"$dir/build.log" 2>&1; then
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

# The third ablation puts a defect back instead of removing a hook,
# because that is what section 6 watches: the shape guard, restored
# under two fresh names. It replaces `expLowerOne`'s header so the two
# helper definitions ride in with it; the `(pub :: expLowerOne ...)`
# signature above the anchor still covers the function it reopens.
#
# The guard reads a `TAG_E_BEGIN`'s statements through `nodeAVec`, and
# `expHeadIsContract` takes the `(Vec Int)` it answers. It still asks
# whether the body looks lowered, which keeps this a probe of section 6.
ablate "guard-restored" expand.ax \
  "(pub fn (expLowerOne d tags)
  (if (== (vecLen tags) 0)
    0" \
  "(pub :: expWasLowered (-> Int Int))

(pub fn (expWasLowered b)
  (if (== b 0)
    0
    (if (== (nodeTag b) TAG_E_BEGIN)
      (expHeadIsContract (nodeAVec b))
      (if (== (nodeTag b) TAG_E_LET)
        (if (strEq (nodeAName b) \"result\")
          (expWasLowered (nodeC b))
          0
        )
        0
      )
    )
  )
)

(pub :: expHeadIsContract (-> (Vec Int) Int))

(pub fn (expHeadIsContract v)
  (if (== (vecLen v) 0)
    0
    (let ((h (spineHead (vecGet v 0))))
      (if (== (nodeTag h) TAG_E_VAR)
        (if (strEq (nodeAName h) \"__contract\")
          1
          0
        )
        0
      )
    )
  )
)

(pub fn (expLowerOne d tags)
  (if (|| (== (vecLen tags) 0) (== (expWasLowered (nodeC d)) 1))
    0" \
  section6

echo
if (( failed )); then
  echo "FAILED: $failed of $checks checks"
  exit 1
fi
echo "PASSED: $checks checks"
