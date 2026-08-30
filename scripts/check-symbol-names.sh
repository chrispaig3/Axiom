#!/usr/bin/env bash
# A name the frontend accepts is a name the backend can emit.
#
# Nothing in this repository asserted that, and it was false for twelve
# of the sixteen bytes `isIdentChar` admits. Axiom's identifier set is
# deliberately wide - `! * + / < > = % & | ' ^` are name characters, so
# that `(+ a b)` is a call and `set!` and `foo'` are names - and
# `codegen.ax` wrote every name into LLVM unquoted, where the legal set
# is only `[-A-Za-z0-9$._]`. So this was a complete program:
#
#   (:: foo' (-> Int Int))
#   (fn (foo' n) n)
#   (:: main Int)
#   (fn (main) (foo' 42))
#
# accepted by the lexer, the parser, the checker, `fmt` and `symbols`,
# and then:
#
#   opt: error: expected '(' in function argument list
#   define i64 @foo'(i64 %n) #0 {
#   error[AX4003]: opt failed  --> <toolchain>
#
# The compiler blaming the native toolchain for its own output, with no
# span into the source, for a program it had just called well typed.
# Measured 2026-08-09, one probe per shape as a function name and again
# as a parameter name: `plain` and `x-5` ran and answered 42; `foo'`,
# `a+b`, `set!`, `a*b`, `a=b`, `a^b`, `a<b`, `a|b`, `a&b`, `a%b`, `a/b`
# and `a>b` all exited 4. `x-5` survived only because `-` happens to be
# legal in both sets.
#
# WHY NO GATE COULD SEE IT. The same shape as the empty form, as block
# comments, as private declarations: all 1,625 distinct top-level names
# in `stdlib/` and `self_host/` are already inside LLVM's set - counted
# as the `fn`/`define` heads plus the `::` subjects over those two
# trees' 35 files, of which 0 carry an operator byte at all - and every
# apostrophe in either tree is inside a comment or a string. The corpus
# is written by people solving problems in Axiom, and nobody's problem
# needed a prime. A sweep over real code cannot find this; only a sweep
# over the *rule* can.
#
# So this gate asks the question the corpus does not. For every
# printable byte - all 94, not the sixteen the lexer happens to admit,
# because which bytes those are is the other side of the agreement and
# must be free to move - it builds three probes: the byte inside a
# function name, at the start of one, and inside a parameter name. Each
# one has to reach exactly one of two outcomes:
#
#   REFUSED  by `check`, with a diagnostic carrying a code and a span
#            into the probe. A refusal the user cannot act on is not an
#            outcome, it is a hang with an exit status.
#   ACCEPTED by `check`, and then it must BUILD and RUN and answer 42.
#
# There is no third outcome, and "accepted, then killed by `opt`" was
# the third outcome for twelve bytes. `symbols` decides which arm
# applies: if the frontend reports a function whose name is exactly the
# probe's, the frontend accepted that NAME, and the backend is then
# obliged to emit it. That is the whole property in one sentence, and
# it is deliberately not phrased in terms of `isIdentChar` - asking the
# lexer what it admits and then checking the backend against that
# answer is one implementation grading itself.
#
# WHAT WAS DONE ABOUT IT. `llvmSym` (codegen.ax) quotes a name LLVM
# cannot read bare, routed through the sites that write a user's name
# into IR: the function definition, the parameter list, the parameter
# reference, the tail-loop store, the `ptrtoint` of a function value,
# the three `call` sites, and the effect slot's global with its loads
# and stores. Compiler-generated names (`_lam_N`, `_thunk_N`, `%aN`,
# `label_N`) are not routed - they are inside the set by construction,
# and this gate is what proves the distinction holds.
#
# MEASURED, before the gate was written:
#   - quoted symbols assemble on ALL FOUR targets at -O0 and -O2.
#     `define i64 @"foo'"` and `%"n'"` and `@"g!x"` through
#     `llc -mtriple=<t> -relocation-model=pic -filetype=obj`, exit 0
#     for arm64-apple-macosx14.0.0, x86_64-apple-macosx14.0.0,
#     aarch64-unknown-linux-gnu and x86_64-unknown-linux-gnu, and `nm`
#     shows the names surviving into the object intact (`_foo'`,
#     `_a+b`, `_set!`). So the fix is quoting, not mangling: the symbol
#     a debugger shows is still the name the programmer wrote.
#   - the change is a no-op on this tree, to the byte. The compiler's
#     own IR - 2,342,271 bytes of it - is IDENTICAL emitted by a
#     compiler with `llvmSym` and one without, and contains zero quoted
#     names. That is why `check-bootstrap.sh`'s IR identity and
#     `check-reproducible.sh` cannot move.
#
# NEGATIVE TEST, run 2026-08-09 against this version of this script.
# `llvmSym` ablated to the identity - `(pub fn (llvmSym name) name)` -
# in a scratch COPY of the tree, and this script run with its repo root
# pointed at that copy, so the compiler under test is built from the
# ablated source rather than merely by it. Exit 1, 42 of 290:
#
#   35  sweep probes, every one "the frontend accepted this name and
#       the backend could not emit it (AX4003 from the toolchain)" -
#       which is exactly the 35 that need quoting in a good build, so
#       the two halves account for each other with nothing left over
#    5  self-tail-call, lambda-capture, nullary-call,
#       function-value-thunk and effect-slot, each ran to 4
#    1  opt-2, build failed on `define i64 @a+b(i64 %n)`
#    1  the quoted-path floor, 0 where the floor is 12
#
# Restored: 290/290, exit 0. Two of the checks here do NOT move under
# that ablation, and both are supposed not to: "plain names are
# unquoted" is an over-quoting check, which the identity satisfies; and
# the `constructor` probe passes, because a constructor is a tag rather
# than an emitted symbol - it is in the bank to show that a
# `Val'`-shaped constructor works at all, not to exercise quoting.
#
# The ablation is not re-run on every invocation because it costs a
# compiler build; it is reproduced by that one-line edit.
#
# Requires: a compiler, and the native toolchain (`opt`/`llc`/`cc`),
# since the accepting arm is only meaningful if it actually runs.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

# Built from the tree, the way every other self-hosting gate does it, so
# that an ablation of `self_host/` is visible here rather than hidden
# behind whatever binary `AXIOM` happens to name.
gate_build_axc axc "$work/axiom"

d="$work/p"; mkdir -p "$d"
probes=0; failed=0; accepted=0; refused=0; quoted=0
accepted_chars=""

# probe <label> <the name> <kind>
#   kind `fn`    - the name is a top-level function's
#   kind `param` - the name is a parameter's
#
# Writes the source with printf '%s' so that no byte of the name is ever
# read by the shell as a format, an escape or an expansion.
probe() {
  local label="$1" nm="$2" kind="$3"
  local out st symst runst runout
  probes=$((probes + 1))

  if [[ "$kind" == fn ]]; then
    { printf '(:: '; printf '%s' "$nm"; printf ' (-> Int Int))\n'
      printf '(fn ('; printf '%s' "$nm"; printf ' n) n)\n'
      printf '(:: main Int)\n'
      printf '(fn (main) ('; printf '%s' "$nm"; printf ' 42))\n'; } > "$d/p.ax"
  else
    { printf '(:: f (-> Int Int))\n'
      printf '(fn (f '; printf '%s' "$nm"; printf ') '; printf '%s' "$nm"; printf ')\n'
      printf '(:: main Int)\n'
      printf '(fn (main) (f 42))\n'; } > "$d/p.ax"
  fi

  out="$( (cd "$d" && "$axc" --diagnostic-format=ai check p.ax) 2>&1 )"; st=$?

  # 1. No signal, ever. A process killed by a signal produces no output,
  #    so it satisfies every assertion phrased about output - which is
  #    exactly how the empty form survived `check-fmt-selfhost.sh`.
  if [[ $st -ge 128 ]]; then
    echo "FAIL $label: check was killed by a signal (exit $st)"
    failed=$((failed + 1)); return
  fi

  # 2. The refusing arm: a code and a span into the probe.
  if [[ $st -ne 0 ]]; then
    refused=$((refused + 1))
    if ! grep -qE '^E AX[0-9]{4} p\.ax:[0-9]+:[0-9]+' <<<"$out"; then
      echo "FAIL $label: refused (exit $st) with no spanned diagnostic to act on"
      head -2 <<<"$out" | sed 's/^/     /'
      failed=$((failed + 1)); return
    fi
    return
  fi

  accepted=$((accepted + 1))

  # Did the frontend accept this as a NAME, or did it accept some other
  # program? `symbols` is the frontend's own answer, and it is the only
  # thing that makes 42 the right expectation.
  symst=0
  ( cd "$d" && "$axc" --diagnostic-format=ai symbols p.ax ) >"$d/sym.txt" 2>&1 || symst=$?
  if [[ $symst -ge 128 ]]; then
    echo "FAIL $label: symbols was killed by a signal (exit $symst)"
    failed=$((failed + 1)); return
  fi
  # For a parameter probe the name to look for is `f`, not the parameter:
  # `symbols` reports top-level declarations. That is not a weaker
  # assertion, because the parameter's acceptance is already proved by
  # `check` succeeding - the body IS the parameter, so a name that did
  # not bind is `AX3001`, and a name that split into two tokens changes
  # the arity and makes `(f 42)` a partial application (`AX3013`).
  # Either way the probe would have taken the refusing arm above.
  local want_name="$nm" is_name=0
  [[ "$kind" == param ]] && want_name="f"
  while read -r kindcol namecol _rest; do
    [[ "$kindcol" == "F" && "$namecol" == "$want_name" ]] && is_name=1
  done < "$d/sym.txt"

  # 3. The accepting arm. It has to run, and the toolchain has to not be
  #    the one to refuse it - that refusal is the defect this file is
  #    named after.
  runout="$( (cd "$d" && "$axc" --diagnostic-format=ai run p.ax) 2>&1 )"; runst=$?
  if [[ $runst -ge 128 ]]; then
    echo "FAIL $label: accepted, then run was killed by a signal (exit $runst)"
    failed=$((failed + 1)); return
  fi
  if grep -qE '^E AX4[0-9]{3} ' <<<"$runout"; then
    echo "FAIL $label: the frontend accepted this name and the backend could not emit it (AX4003 from the toolchain)"
    grep -E '^E AX4' <<<"$runout" | head -1 | sed 's/^/     /'
    failed=$((failed + 1)); return
  fi
  if [[ $is_name -eq 1 && $runst -ne 42 ]]; then
    echo "FAIL $label: accepted as a name and ran to $runst, want 42"
    head -2 <<<"$runout" | sed 's/^/     /'
    failed=$((failed + 1)); return
  fi

  # Anti-vacuousness: count the probes that actually exercised quoting.
  # A gate that never reaches the quoted path proves nothing about it.
  if [[ $is_name -eq 1 ]]; then
    accepted_chars="$accepted_chars$label"$'\n'
    # Both sigils. A parameter is quoted as `%"p+q"`, and counting only
    # `@` missed all twelve parameter probes - 23 where 35 were due,
    # which is how this line came to be written the long way.
    if ( cd "$d" && "$axc" emit-llvm p.ax -o ir.ll ) >/dev/null 2>&1; then
      grep -qE '[@%]"' "$d/ir.ll" && quoted=$((quoted + 1))
    fi
  fi
}

echo "== every printable byte, in three positions =="
for i in $(seq 33 126); do
  c="$(printf "\\$(printf '%03o' "$i")")"
  probe "byte-$i-mid-fn"    "a${c}b" fn
  probe "byte-$i-start-fn"  "${c}ab" fn
  probe "byte-$i-mid-param" "p${c}q" param
done

# ---------------------------------------------------------------
# The shapes a three-character sweep does not reach. Each uses a name
# LLVM cannot read bare, in a construct that emits it through a
# different site of `codegen.ax`.
# ---------------------------------------------------------------
echo "== the constructs that emit a name through another door =="

# struct <label> <expected exit>; source on stdin.
struct_probe() {
  local label="$1" want="$2" out st
  probes=$((probes + 1))
  cat > "$d/s.ax"
  out="$( (cd "$d" && "$axc" --diagnostic-format=ai check s.ax) 2>&1 )"; st=$?
  if [[ $st -ne 0 ]]; then
    echo "FAIL $label: check exited $st"
    head -2 <<<"$out" | sed 's/^/     /'
    failed=$((failed + 1)); return
  fi
  out="$( (cd "$d" && "$axc" --diagnostic-format=ai run s.ax) 2>&1 )"; st=$?
  if [[ $st -ge 128 ]]; then
    echo "FAIL $label: run was killed by a signal (exit $st)"
    failed=$((failed + 1)); return
  fi
  if [[ $st -ne $want ]]; then
    echo "FAIL $label: ran to $st, want $want"
    head -2 <<<"$out" | sed 's/^/     /'
    failed=$((failed + 1)); return
  fi
  accepted=$((accepted + 1))
  echo "ok   $label"
}

# A self tail call: the parameter is stored into its alloca by name in
# the tail-loop header, which is a site the straight-line probes miss.
struct_probe self-tail-call 42 <<'AXEOF'
(:: down (-> Int Int Int))
(fn (down n' acc) (if (== n' 0) acc (down (- n' 1) (+ acc 1))))
(:: main Int)
(fn (main) (down 42 0))
AXEOF

# A lambda captures a prime-suffixed binding and takes an operator-named
# parameter: the lifted function's own parameter list.
struct_probe lambda-capture 42 <<'AXEOF'
(:: main Int)
(fn (main) (let ((x' 42)) ((lambda (y+z) (+ x' (- y+z 0))) 0)))
AXEOF

# Constructors, nullary and with a field.
struct_probe constructor 42 <<'AXEOF'
(data D (Mk!) (Val' Int))
(:: main Int)
(fn (main) (match (Val' 42) ((Mk!) 0) ((Val' v) v)))
AXEOF

# A nullary function reference lowers to a call, not a value.
struct_probe nullary-call 42 <<'AXEOF'
(:: k' Int)
(fn (k') 42)
(:: main Int)
(fn (main) k')
AXEOF

# A function value: `ptrtoint ptr @name` plus a `_thunk_N` whose body
# calls the name. Two sites, one probe.
struct_probe function-value-thunk 42 <<'AXEOF'
(:: inc' (-> Int Int))
(fn (inc' a) (+ a 1))
(:: ap (-> (-> Int Int) Int Int))
(fn (ap f x) (f x))
(:: main Int)
(fn (main) (ap inc' 41))
AXEOF

# An effect slot is a global named after the effect, with loads and
# stores around the handler. The slot is ALSO the registry's key, so
# this pins that the quoting happens at emission and not in the key -
# get that wrong and the global's definition and its loads disagree.
#
# The handler takes ONE parameter because `op'` takes one argument.
# `emitApplyRegs` applies the handler to the OPERATION's arguments, one
# per indirect call, and every handler in the corpus is written that way
# - including `tests/selfhost/820-effect-handlers.ax`, which curries a
# two-argument operation's handler by hand as
# `(lambda (p) (lambda (q) ...))`.
#
# This probe used to be written `(lambda (v k) v)`, which answered 42
# only because a multi-parameter lambda silently DROPPED its surplus
# parameters - it had no representation at all, and the second one bound
# nothing. Now that `(lambda (v k) b)` means `(lambda (v) (lambda (k) b))`,
# applying it to `op'`'s single argument correctly yields the inner
# closure, and the probe read its address (48). The old spelling was
# asserting the bug; the subject of this probe - where the quoting
# happens - is untouched either way.
struct_probe effect-slot 42 <<'AXEOF'
(effect E' (op' :: (-> Int Int)))
(:: user (-> Int Int))
(fn (user n) (op' n))
(:: main Int)
(fn (main) (handle (user 42) (E') (lambda (v) v)))
AXEOF

# An imported name is mangled to `Mod$name` before it is emitted, so the
# `$` is safe and the half after it is not. Two files, so it does not fit
# the single-source helper above. Both spellings of the reference are
# here because they resolve through different paths: the bare name
# through the merged declaration list, `M::g+h` through the qualifier.
echo "== an imported name, mangled and still quoted =="
xm="$work/xm"; mkdir -p "$xm"
printf "(pub :: help' (-> Int Int))\n(pub fn (help' n) (+ n 1))\n(pub :: g+h (-> Int Int))\n(pub fn (g+h n) (help' n))\n" > "$xm/M.ax"
printf '(import M)\n(:: main Int)\n(fn (main) (g+h 41))\n'      > "$xm/bare.ax"
printf '(import M)\n(:: main Int)\n(fn (main) (M::g+h 41))\n'   > "$xm/qual.ax"
for f in bare qual; do
  probes=$((probes + 1))
  out="$( (cd "$xm" && "$axc" --diagnostic-format=ai run "$f.ax") 2>&1 )"; st=$?
  if [[ $st -eq 42 ]]; then
    echo "ok   cross-module-$f"
    accepted=$((accepted + 1))
  else
    echo "FAIL cross-module-$f: ran to $st, want 42"
    head -2 <<<"$out" | sed 's/^/     /'
    failed=$((failed + 1))
  fi
done
# The mangled form has to be the quoted one, not a bare `@M$g+h`. The
# failing branch of the emit is a FAILURE and not a skip: a check that
# quietly disappears when its command errors is the `check-tree-sitter`
# hazard, and reports success without having looked.
probes=$((probes + 1))
if ! ( cd "$xm" && "$axc" emit-llvm bare.ax -o xm.ll ) >/dev/null 2>&1; then
  echo "FAIL cross-module: emit-llvm failed, so the mangled name was never inspected"
  failed=$((failed + 1))
elif grep -q 'define i64 @"M\$g+h"(' "$xm/xm.ll"; then
  echo "ok   the mangled name is quoted as a whole"
else
  echo "FAIL cross-module: expected a quoted \`@\"M\$g+h\"\` definition"
  grep -E 'define i64 @.*g\+h' "$xm/xm.ll" | head -2 | sed 's/^/     /'
  failed=$((failed + 1))
fi

# Optimisation does not change the legal name set, but it does change
# which passes read it.
echo "== the same program at --opt 2 =="
probes=$((probes + 1))
{ printf "(:: a+b (-> Int Int))\n(fn (a+b n) n)\n(:: main Int)\n(fn (main) (a+b 42))\n"; } > "$d/o2.ax"
if ( cd "$d" && "$axc" --diagnostic-format=ai build --input o2.ax --output o2 --opt 2 ) >"$d/o2.log" 2>&1; then
  ( cd "$d" && ./o2 ); o2st=$?
  if [[ $o2st -eq 42 ]]; then echo "ok   opt-2 (ran to 42)"; accepted=$((accepted + 1))
  else echo "FAIL opt-2: ran to $o2st, want 42"; failed=$((failed + 1)); fi
else
  echo "FAIL opt-2: build failed"; sed 's/^/     /' "$d/o2.log" | head -3; failed=$((failed + 1))
fi

# ---------------------------------------------------------------
# The quoting has to be MINIMAL. Everything above passes just as well
# from a `llvmSym` that quotes unconditionally - and that version would
# rewrite every symbol in the bootstrap, so the property is not "it
# runs", it is "a name LLVM can read bare is emitted bare".
# ---------------------------------------------------------------
echo "== a plain name is still emitted bare =="
probes=$((probes + 1))
printf '(:: plain (-> Int Int))\n(fn (plain n) n)\n(:: main Int)\n(fn (main) (plain 42))\n' > "$d/plain.ax"
if ( cd "$d" && "$axc" emit-llvm plain.ax -o plain.ll ) >/dev/null 2>&1; then
  if grep -q 'define i64 @plain(' "$d/plain.ll"; then
    echo "ok   plain names are unquoted"
  else
    echo "FAIL plain: a name inside LLVM's own set was not emitted bare"
    grep -E 'define i64 @.*plain' "$d/plain.ll" | head -2 | sed 's/^/     /'
    failed=$((failed + 1))
  fi
else
  echo "FAIL plain: emit-llvm failed"; failed=$((failed + 1))
fi

# ---------------------------------------------------------------
# Floors. This section reports mostly by silence, and a sweep that
# stopped running reports the same silence from zero probes.
# ---------------------------------------------------------------
echo
echo "     $probes probes: $accepted accepted, $refused refused, $quoted needed quoting"

if [[ $probes -lt 282 ]]; then
  echo "FAIL: the sweep ran $probes probes; the floor is 282 (94 bytes x 3 positions)"
  failed=$((failed + 1))
fi
if [[ $refused -eq 0 || $accepted -eq 0 ]]; then
  echo "FAIL: the sweep produced one outcome only ($accepted accepted, $refused refused)"
  failed=$((failed + 1))
fi
# Twelve bytes of `isIdentChar` are outside LLVM's set, in three
# positions, so a correct compiler quotes on well over twelve probes.
# The floor is deliberately below the measured 36 so that widening
# `isIdentChar` does not have to move it.
if [[ $quoted -lt 12 ]]; then
  echo "FAIL: only $quoted probes exercised the quoted path; the floor is 12."
  echo "      A sweep that never reaches it proves nothing about it."
  failed=$((failed + 1))
else
  echo "ok   $quoted probes exercised the quoted path"
fi

echo
if [[ $failed -eq 0 ]]; then
  echo "PASS: $probes probes, every name the frontend accepts is one the backend emits"
  exit 0
fi
echo "FAIL: $failed of $probes checks failed"
exit 1
