#!/usr/bin/env bash
# A name the frontend accepts is a name the backend can emit.
#
# Axiom's identifier set is wide: `! * + / < > = % & | ' ^` are name
# characters, so `(+ a b)` is a call and `set!` and `foo'` are names.
# LLVM's bare symbol set is only `[-A-Za-z0-9$._]`. Written unquoted, a
# name outside it passes the lexer, the parser, the checker, `fmt` and
# `symbols`, and then fails in `opt`:
#
#   opt: error: expected '(' in function argument list
#   define i64 @foo'(i64 %n) #0 {
#   error[AX4003]: opt failed  --> <toolchain>
#
# That blames the toolchain for the compiler's own output, with no span
# into the source.
#
# A sweep over real code cannot find this. Every top-level name in
# `stdlib/` and `self_host/` is already inside LLVM's set, and every
# apostrophe there is in a comment or a string. Only a sweep over the
# rule can.
#
# So for every printable byte the gate builds three probes: the byte
# inside a function name, at the start of one, and inside a parameter
# name. It tries all 94 bytes, not only those `isIdentChar` admits,
# because that set is the other side of the agreement and may change.
# Each probe must reach one of two outcomes:
#
#   refused   by `check`, with a diagnostic carrying a code and a span
#             into the probe. A refusal the user cannot act on does not
#             count.
#   accepted  by `check`, and then it must build, run and answer 42.
#
# `symbols` decides which arm applies. If the frontend reports a
# function whose name is exactly the probe's, it accepted that name, and
# the backend must emit it. The property is not phrased in terms of
# `isIdentChar`: asking the lexer what it admits and checking the
# backend against that answer is one implementation grading itself.
#
# `llvmSym` (codegen.ax) quotes a name LLVM cannot read bare. Every site
# that writes a user's name into IR goes through it: the function
# definition, the parameter list, the parameter reference, the tail-loop
# store, the `ptrtoint` of a function value, the three `call` sites, and
# the effect slot's global with its loads and stores. Compiler-generated
# names (`_lam_N`, `_thunk_N`, `%aN`, `label_N`) are inside the set by
# construction and skip it; this gate shows that distinction holds.
#
# Quoting rather than mangling keeps the symbol a debugger shows equal to
# the name the programmer wrote. Quoted symbols assemble on every target,
# and `nm` shows them intact (`_foo'`, `_a+b`, `_set!`). The compiler's
# own IR contains no quoted names, so `check-bootstrap.sh`'s IR identity
# and `check-reproducible.sh` are unaffected.
#
# Negative test: ablate `llvmSym` to the identity,
# `(pub fn (llvmSym name) name)`, in a scratch copy of the tree, and run
# this script with its repo root pointed at the copy, so the compiler
# under test is built from the ablated source. It fails every sweep probe
# that needs quoting, the self-tail-call, lambda-capture, nullary-call,
# function-value-thunk and effect-slot probes, `opt-2`, and the
# quoted-path floor. Two checks still pass, as they should: "plain names
# are unquoted" catches over-quoting, which the identity cannot do; and
# a constructor is a tag, not an emitted symbol. The ablation costs a
# compiler build, so it is not run on every invocation.
#
# Requires a compiler and the native toolchain (`opt`, `llc`, `cc`),
# since the accepting arm means something only if it runs.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

# Built from the tree, like every other self-hosting gate, so an ablation
# of `self_host/` shows here instead of hiding behind whatever binary
# `AXIOM` names.
gate_build_axc axc "$work/axiom"

d="$work/p"; mkdir -p "$d"
probes=0; failed=0; accepted=0; refused=0; quoted=0
accepted_chars=""

# probe <label> <the name> <kind>
#   kind `fn`:    the name is a top-level function's
#   kind `param`: the name is a parameter's
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
  #    so it satisfies every assertion phrased about output.
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

  # Did the frontend accept this as a name, or as some other program?
  # `symbols` is the frontend's own answer, and only that makes 42 the
  # right expectation.
  symst=0
  ( cd "$d" && "$axc" --diagnostic-format=ai symbols p.ax ) >"$d/sym.txt" 2>&1 || symst=$?
  if [[ $symst -ge 128 ]]; then
    echo "FAIL $label: symbols was killed by a signal (exit $symst)"
    failed=$((failed + 1)); return
  fi
  # For a parameter probe the name to look for is `f`, since `symbols`
  # reports top-level declarations. `check` succeeding already proves the
  # parameter was accepted. The body is the parameter, so a name that did
  # not bind is `AX3001`, and a name split into two tokens changes the
  # arity and makes `(f 42)` a partial application (`AX3013`). Either way
  # the probe takes the refusing arm above.
  local want_name="$nm" is_name=0
  [[ "$kind" == param ]] && want_name="f"
  while read -r kindcol namecol _rest; do
    [[ "$kindcol" == "F" && "$namecol" == "$want_name" ]] && is_name=1
  done < "$d/sym.txt"

  # 3. The accepting arm. It has to run, and the toolchain must not
  #    refuse it: that refusal is the defect this gate exists for.
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
    # Both sigils: a parameter is quoted as `%"p+q"`, so counting only
    # `@` would miss every parameter probe.
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

# struct_probe <label> <expected exit>; source on stdin.
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
# stores around the handler. The slot is also the registry's key, so
# this pins that quoting happens at emission, not in the key. Otherwise
# the global's definition and its loads disagree.
#
# The handler takes one parameter because `op'` takes one argument.
# `emitApplyRegs` applies the handler to the operation's arguments, one
# per indirect call. `(lambda (v k) b)` means
# `(lambda (v) (lambda (k) b))`, so a two-parameter handler here would
# answer with the inner closure's address.
# `tests/selfhost/820-effect-handlers.ax` curries a two-argument
# operation's handler by hand as `(lambda (p) (lambda (q) ...))`.
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
# The mangled form must be quoted as a whole, not a bare `@M$g+h`. A
# failed emit counts as a failure: a check that quietly disappears when
# its command errors reports success without having looked.
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
# The quoting must be minimal. Everything above passes just as well with
# a `llvmSym` that always quotes, which would rewrite every symbol in the
# bootstrap. So a name LLVM can read bare must be emitted bare.
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
# Twelve bytes of `isIdentChar` are outside LLVM's set, each in three
# positions, so a correct compiler quotes on well over twelve probes.
# The floor of 12 sits well below that, so changing `isIdentChar` need
# not move it.
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
