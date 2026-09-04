#!/usr/bin/env bash
#
# "This binary needs at most N bytes of stack", computed rather than
# measured, and checked against a measurement.
#
# WHY THIS EXISTS. `scripts/check-stack-depth.sh` answers the same
# question DYNAMICALLY, by bisecting `ulimit -s` until the compiler
# stops working. That is the only honest answer for a program that
# recurses, and the compiler does. But it is useless to the embedded
# reader docs/embedded-proposal.md is written for: you cannot bisect a
# microcontroller, and "run it and see" is not a bound. A program that
# declares `;@axiom:restrict(no-recursion)` has already had its call
# graph proved acyclic by the compiler (AX3049, scripts/check-restrictions.sh),
# and an acyclic weighted graph has a longest path. This gate computes
# it, and then proves the computation right by measuring the same
# program the slow way.
#
# WHAT THE PROPOSAL GOT WRONG, and why this gate is not where 4.6 said
# it would be. Section 4.6 said "the emitter knows each frame's size".
# It does not. `axiom` emits LLVM *text* IR and shells out
# (self_host/driver.ax, `IR -> opt -> llc -> cc`); frame layout is
# LLVM's register allocator's decision, taken after codegen.ax has
# stopped running. So the sizes come from the same llc invocation the
# driver already makes - either llc's own `--stack-usage-file`, or a
# prologue parse of `llc -filetype=asm`. The analysis lives in
# `scripts/lib/stack-bound.py`; no compiler source is touched.
#
# The other correction the proposal needs: its "32 KiB hello world"
# stack figure is the HOST process's dyld and libc startup, not the
# Axiom program. The program's own need is 192 bytes, and A6 gates it.
#
# WHAT IT ASSERTS.
#   A1  ARITHMETIC. Two generated no-recursion chain programs, 400 and
#       1200 frames deep, built at --opt 0. Each computed bound is
#       within 32 KiB of that binary's bisected `ulimit -s` floor, and
#       the DIFFERENCE of the two bounds matches the difference of the
#       two floors within 16 KiB. The difference is the sharper half:
#       it cancels the per-process constant entirely.
#   A2  THE EXTRACTOR IS RIGHT. Over all ~3,767 functions of the
#       compiler itself, the portable prologue parse agrees with llc's
#       own stack-usage table function for function. This is what earns
#       the portable path its trust on a toolchain that has no such
#       table - and it is SKIPPED LOUDLY, never silently, when llc
#       cannot produce one.
#   A3  NO DYNAMIC FRAMES. Every one of those frames is reported
#       `static`. If emitted IR ever grew a variable-sized alloca, no
#       static bound would exist at all, and nothing else in the tree
#       asserts that it has not.
#   A4  IT REFUSES RATHER THAN GUESSES. The compiler's own IR must be
#       REFUSED with a named cycle, not handed a number.
#   A5  THE TWO HALVES AGREE. A recursive fixture under
#       `restrict(no-recursion)` is refused by the COMPILER as AX3049
#       naming the cycle; the same source with the tag deleted compiles
#       and is then refused by the ANALYZER with a cycle. The static
#       claim and the static analysis reach the same verdict.
#   A6  THE HEADLINE, GATED. Hello world at --opt 1 gets a bound under
#       a ceiling, reported either way.
#
# ABLATIONS. `AXIOM_ABLATE_STACK_BOUND` is read by the analyzer and
# nowhere else, and each of the three is asserted here to turn a
# specific assertion red:
#   flat        charge only the root's own frame  -> A1 collapses
#   nocycle     do not refuse a cyclic graph      -> A4 gets a number
#   noindirect  drop the symbol-table exclusion   -> A6 unboundable
#
# WHY THE TOLERANCE IS TWO-SIDED, and must stay that way. The measured
# floor is sometimes BELOW the computed bound: `ulimit -s L` does not
# grant exactly L. Measured with a C recursion probe, darwin hands back
# roughly L + 3-4 KiB and the Linux gate container roughly L - 13 KiB,
# and the offset is per-BINARY, scattering about 12 KiB peak-to-peak.
# The bisection itself is exactly reproducible (three consecutive runs
# of the same binary all answered 193 KiB). So a one-sided assertion
# here would be a statement about the host's stack accounting, not
# about the bound. Do not "fix" this into `bound <= measured`.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

analyzer="$repo_root/scripts/lib/stack-bound.py"
failed=0
checks=0

note() { echo "$@"; }
fail() { echo "FAIL: $*" >&2; failed=$((failed + 1)); }

# --------------------------------------------------------------------
# Toolchain probe. `llc --stack-usage-file` exists in LLVM 23 (Homebrew,
# darwin) and NOT in LLVM 18.1.3, which is what the Linux gate image and
# CI's apt llvm carry. A2 and A3 need it; everything else runs from the
# prologue parse alone. A silent skip here would be exactly the vacuous
# check this repository keeps finding in itself, so it is announced.
# --------------------------------------------------------------------
# NOTE the redirection to a file rather than a pipe. Under `pipefail`,
# `llc --help-list-hidden | grep -q X` reports FAILURE when grep matches:
# grep exits at the first hit, llc dies of SIGPIPE, and 141 propagates.
# Written as a pipe, this probe answered "no such flag" on the LLVM 23
# that has it, and silently skipped A2 and A3 on the only leg that can
# run them - a vacuous skip rather than a vacuous check, and just as bad.
su_ok=0
llc --help-list-hidden >"$work/llc-help.txt" 2>/dev/null || true
if grep -q -- '--stack-usage-file' "$work/llc-help.txt"; then su_ok=1; fi
llcver="$(llc --version 2>/dev/null | grep -i 'LLVM version' | head -1 | sed 's/^ *//')"
note "== llc: ${llcver:-unknown} ; stack-usage-file: $([[ $su_ok == 1 ]] && echo yes || echo no) =="

# Reproduce the driver's pipeline exactly: emit-llvm gives PRE-opt IR
# (driver.ax keeps that, not what llc consumed), so opt and llc must be
# run here at the same level `axiom build --opt N` would use.
#   pipeline <source> <optlevel> <prefix>
pipeline() {
  local src="$1" lvl="$2" pre="$3"
  if ! "$axc" emit-llvm "$src" >"$work/$pre.raw.ll" 2>"$work/$pre.emit.err"; then
    fail "emit-llvm failed for $src"; sed 's/^/    /' "$work/$pre.emit.err" | head -5 >&2; return 1
  fi
  if ! opt "-O$lvl" "$work/$pre.raw.ll" -S -o "$work/$pre.ll" 2>"$work/$pre.opt.err"; then
    fail "opt -O$lvl failed for $src"; return 1
  fi
  if ! llc "$work/$pre.ll" -filetype=asm -o "$work/$pre.s" \
         "-O$lvl" -relocation-model=pic 2>"$work/$pre.llc.err"; then
    fail "llc -filetype=asm failed for $src"; return 1
  fi
  if (( su_ok )); then
    llc "$work/$pre.ll" -filetype=obj -o "$work/$pre.o" \
        "-O$lvl" -relocation-model=pic --stack-usage-file="$work/$pre.su" \
        2>>"$work/$pre.llc.err" || true
  fi
  return 0
}

# Run the analyzer over a prefix produced by `pipeline`, passing the
# stack-usage table only when the toolchain made one.
bound_args() {
  local pre="$1"
  printf '%s --asm %s' "$work/$pre.ll" "$work/$pre.s"
  if (( su_ok )) && [[ -s "$work/$pre.su" ]]; then printf ' --su %s' "$work/$pre.su"; fi
}

# The smallest `ulimit -s` at which a binary still exits 0, bisected.
# The half-limit run must die by SIGNAL, for the same reason
# check-stack-depth.sh insists on it: without that, a binary that fails
# for an unrelated reason is indistinguishable from one that ran out of
# stack, and the number below would mean nothing.
run_at() {
  local kib="$1"
  # stderr of the whole subshell is discarded: the runs BELOW the floor
  # die by SIGSEGV on purpose, and bash announces each one. The exit
  # status is what is being read, not the message.
  ( ulimit -s "$kib" 2>/dev/null || exit 200; "$2" >/dev/null 2>&1 ) 2>/dev/null
  echo $?
}
bisect() {
  local bin="$1" lo=8 hi=4096 mid
  if [[ "$(run_at "$hi" "$bin")" == 200 ]]; then echo unsettable; return; fi
  if [[ "$(run_at "$hi" "$bin")" != 0 ]]; then echo topfails; return; fi
  while (( hi - lo > 1 )); do
    mid=$(( (lo + hi) / 2 ))
    if [[ "$(run_at "$mid" "$bin")" == 0 ]]; then hi=$mid; else lo=$mid; fi
  done
  echo "$hi"
}

# --------------------------------------------------------------------
# The chain fixtures. Generated, not checked in: at K=60 live locals
# they are ~700 KB of source, and every path a document names is
# resolved by check-doc-drift.sh, so no document may name these.
# K=60 is chosen to make each frame fat (512 bytes on aarch64) so the
# 400-frame difference is far larger than the host's per-process
# scatter; the combining `+` after the call is what keeps the frame
# alive across it, so neither tail-call rewrite can flatten the chain.
# --------------------------------------------------------------------
gen_chain() {
  python3 - "$1" "$2" <<'PY'
import sys
N, path = int(sys.argv[1]), sys.argv[2]
K = 60
L = ["(import Sys)", ""]
L += [";@axiom:restrict(no-recursion)", "(:: f0 (-> Int Int))", "(fn (f0 x) (+ x 1))", ""]
for i in range(1, N + 1):
    lets = " ".join("(v%d (* (+ x %d) %d))" % (j, j, j + 3) for j in range(K))
    expr = "(f%d (+ x 1))" % (i - 1)
    for j in range(K):
        expr = "(+ v%d %s)" % (j, expr)
    L += [";@axiom:restrict(no-recursion)", "(:: f%d (-> Int Int))" % i,
          "(fn (f%d x) (let (%s) %s))" % (i, lets, expr), ""]
L += [";@axiom:restrict(no-recursion)", "(:: run (-> Int Int))",
      "(fn (run n) (f%d n))" % N, ""]
L += [";@axiom:effect(io)", "(:: main Int)",
      "(fn (main) (if (== 0 (run sysArgc)) 0 0))"]
open(path, "w").write("\n".join(L) + "\n")
PY
}

# ====================================================================
# A1 - the arithmetic, against a measurement.
#
# --opt 0 IS REQUIRED and is not a convenience. At --opt 1 the LLVM
# inliner flattens a deep arithmetic chain to `ret i64 0` (measured: a
# 300-function chain's bound falls from 9,664 bytes to 16). Both
# answers are correct - the flattened program really does need 16 bytes
# - but only --opt 0 exercises the path arithmetic this assertion is
# about.
# ====================================================================
# Plain variables, not an associative array: the gates run under
# /bin/bash, which on darwin is 3.2 and has no `declare -A`.
b400=""; b1200=""; m400=""; m1200=""
a1_ok=1
for n in 400 1200; do
  gen_chain "$n" "$work/chain$n.ax"
  if ! "$axc" build --input "$work/chain$n.ax" --output "$work/chain$n" --opt 0 \
        >"$work/chain$n.build.log" 2>&1; then
    fail "could not build the $n-frame chain fixture"
    sed 's/^/    /' "$work/chain$n.build.log" | head -10 >&2
    a1_ok=0; continue
  fi
  pipeline "$work/chain$n.ax" 0 "chain$n" || { a1_ok=0; continue; }
  out="$(python3 "$analyzer" $(bound_args "chain$n") 2>&1)"
  b="$(sed -n 's/^BOUND from main: \([0-9]*\) bytes$/\1/p' <<<"$out")"
  if [[ -z "$b" ]]; then
    fail "no bound for the $n-frame chain; analyzer said:"; sed 's/^/    /' <<<"$out" >&2
    a1_ok=0; continue
  fi
  m="$(bisect "$work/chain$n")"
  if [[ "$m" == unsettable ]]; then
    note "SKIP: this shell cannot set ulimit -s, so A1 cannot be measured"
    a1_ok=0; break
  fi
  if [[ "$m" == topfails ]]; then
    fail "the $n-frame chain does not run even with 4 MiB of stack"; a1_ok=0; continue
  fi
  eval "b$n=\$b"; eval "m$n=\$m"
  note "A1: $n frames - computed $b bytes ($((b / 1024)) KiB), measured floor $m KiB"
done

if (( a1_ok )) && [[ -n "$b400" && -n "$b1200" ]]; then
  for n in 400 1200; do
    checks=$((checks + 1))
    eval "bn=\$b$n; mn=\$m$n"
    d=$(( bn / 1024 - mn ))
    (( d < 0 )) && d=$(( -d ))
    if (( d <= 32 )); then
      note "ok   A1: $n frames agree within ${d} KiB (tolerance 32)"
    else
      fail "A1: $n frames - computed $(( bn / 1024 )) KiB vs measured ${mn} KiB differ by ${d} KiB, over the 32 KiB tolerance"
    fi
  done
  checks=$((checks + 1))
  db=$(( (b1200 - b400) / 1024 ))
  dm=$(( m1200 - m400 ))
  slope=$(( db - dm )); (( slope < 0 )) && slope=$(( -slope ))
  if (( slope <= 16 )); then
    note "ok   A1: the SLOPE agrees - 800 more frames cost ${db} KiB computed, ${dm} KiB measured (within ${slope}, tolerance 16)"
  else
    fail "A1: 800 more frames cost ${db} KiB computed but ${dm} KiB measured, differing by ${slope} KiB"
  fi

  # ABLATION for A1. `flat` charges only the root's own frame, so the
  # chain's bound collapses to a couple of words and the agreement above
  # becomes impossible. If this still passed, A1 would be measuring
  # nothing.
  checks=$((checks + 1))
  fb="$(AXIOM_ABLATE_STACK_BOUND=flat python3 "$analyzer" $(bound_args chain400) 2>&1 |
        sed -n 's/^BOUND from main: \([0-9]*\) bytes$/\1/p')"
  if [[ -n "$fb" ]] && (( fb / 1024 + 32 < m400 )); then
    note "ok   A1 ablation: =flat collapses the bound to ${fb} bytes, which A1 rejects"
  else
    fail "A1 ablation: =flat still produced ${fb:-no} bound that A1 would accept"
  fi
fi

# ====================================================================
# A2, A3, A4 - all three from ONE emit of the compiler's own IR.
# ====================================================================
if pipeline "self_host/main.ax" 0 "selfhost"; then
  if (( su_ok )) && [[ -s "$work/selfhost.su" ]]; then
    checks=$((checks + 1))
    cc_out="$(python3 "$analyzer" "$work/selfhost.ll" --asm "$work/selfhost.s" \
              --su "$work/selfhost.su" --cross-check --quiet 2>&1)"
    line="$(grep '^cross-check:' <<<"$cc_out")"
    if grep -q '^cross-check: agree [0-9]* disagree 0 missing 0' <<<"$cc_out"; then
      note "ok   A2: $line"
    else
      fail "A2: the prologue parse and llc disagree - $line"
      sed -n '2,8p' <<<"$cc_out" | sed 's/^/    /' >&2
    fi

    # A3. The `.su` table's third column is `static` or `dynamic`; a
    # dynamic frame is a variable-sized alloca, and one anywhere in
    # emitted IR would mean no static bound exists for any program
    # reaching it. The analyzer refuses on one (exit 2); here we assert
    # the stronger structural fact directly, over every row.
    checks=$((checks + 1))
    ndyn="$(awk -F'\t' '$3 != "static" && NF >= 3' "$work/selfhost.su" | wc -l | tr -d ' ')"
    nrow="$(wc -l <"$work/selfhost.su" | tr -d ' ')"
    if [[ "$ndyn" == 0 ]]; then
      note "ok   A3: all $nrow frames of the compiler are static - no dynamic alloca in emitted IR"
    else
      fail "A3: $ndyn of $nrow frames are dynamic, so no static bound exists for them"
      awk -F'\t' '$3 != "static" && NF >= 3' "$work/selfhost.su" | head -5 | sed 's/^/    /' >&2
    fi
  else
    note "SKIP: A2 and A3 need \`llc --stack-usage-file\`, which this llc does not"
    note "      have (LLVM 18 has no such flag; LLVM 23 does). The prologue parse"
    note "      is therefore UNCROSS-CHECKED on this leg, and A3's no-dynamic-frame"
    note "      claim is unverified here. Run this gate on a leg with LLVM 19+ to"
    note "      cover them; run-gates.sh on darwin does."
  fi

  # A4. The compiler recurses, so it has no static bound - and the
  # analyzer must say so, naming a cycle vertex, rather than returning
  # some number derived from a partial walk.
  checks=$((checks + 1))
  a4_out="$(python3 "$analyzer" $(bound_args selfhost) 2>&1)"
  a4_rc=$?
  if (( a4_rc == 3 )) && grep -q '^REFUSE: cycle at ' <<<"$a4_out"; then
    note "ok   A4: the compiler is refused - $(grep '^REFUSE:' <<<"$a4_out")"
  else
    fail "A4: the compiler was not refused with a cycle (rc=$a4_rc)"
    tail -3 <<<"$a4_out" | sed 's/^/    /' >&2
  fi

  # ABLATION for A4. `nocycle` closes the cycle silently and returns a
  # number. A4 must reject that.
  checks=$((checks + 1))
  nb="$(AXIOM_ABLATE_STACK_BOUND=nocycle python3 "$analyzer" $(bound_args selfhost) 2>&1 |
        sed -n 's/^BOUND from main: \([0-9]*\) bytes$/\1/p')"
  if [[ -n "$nb" ]]; then
    note "ok   A4 ablation: =nocycle hands the compiler a bound of ${nb} bytes, which A4 rejects"
  else
    fail "A4 ablation: =nocycle did not produce a bound, so A4's refusal is not what is being tested"
  fi
fi

# ====================================================================
# A5 - the compiler's static claim and this static analysis agree.
# ====================================================================
cat >"$work/rec.ax" <<'AX'
;@axiom:restrict(no-recursion)
(:: countdown (-> Int Int))
(fn (countdown x) (if (== x 0) 0 (+ 1 (countdown (- x 1)))))

(:: main Int)
(fn (main) (countdown 3))
AX
checks=$((checks + 1))
rec_out="$("$axc" check "$work/rec.ax" 2>&1)"
if grep -q 'AX3049' <<<"$rec_out" && grep -q 'countdown -> countdown' <<<"$rec_out"; then
  note "ok   A5: the COMPILER refuses the tagged fixture with AX3049 naming the cycle"
else
  fail "A5: the compiler did not refuse the no-recursion fixture with AX3049 and a cycle path"
  sed 's/^/    /' <<<"$rec_out" | head -6 >&2
fi

# The same source with the claim deleted compiles, and is then refused
# by the ANALYZER for the same reason the compiler gave.
grep -v 'restrict(no-recursion)' "$work/rec.ax" >"$work/rec2.ax"
checks=$((checks + 1))
if pipeline "$work/rec2.ax" 0 "rec2"; then
  r2="$(python3 "$analyzer" $(bound_args rec2) 2>&1)"; r2rc=$?
  if (( r2rc == 3 )) && grep -q 'REFUSE: cycle at countdown' <<<"$r2"; then
    note "ok   A5: the ANALYZER refuses the untagged fixture at the same cycle"
  else
    fail "A5: untagged, the analyzer did not refuse at countdown (rc=$r2rc)"
    tail -3 <<<"$r2" | sed 's/^/    /' >&2
  fi
fi

# ====================================================================
# A6 - the embedded headline, gated.
#
# The ceiling is deliberately loose: the point is that the number is
# REPORTED every run, so a regression is visible in the log long before
# it is red. 192 bytes today against a 4 KiB ceiling.
# ====================================================================
cat >"$work/hi.ax" <<'AX'
(import IO)

;@axiom:effect(io)
(:: main Int)
(fn (main) { (println "hi") 0 })
AX
hi_ceiling=4096
if pipeline "$work/hi.ax" 1 "hi"; then
  checks=$((checks + 1))
  hi_out="$(python3 "$analyzer" $(bound_args hi) 2>&1)"
  hb="$(sed -n 's/^BOUND from main: \([0-9]*\) bytes$/\1/p' <<<"$hi_out")"
  if [[ -z "$hb" ]]; then
    fail "A6: hello world got no bound"
    sed 's/^/    /' <<<"$hi_out" | head -6 >&2
  else
    note "A6: hello world needs ${hb} bytes of stack (ceiling ${hi_ceiling})"
    if (( hb <= hi_ceiling )); then
      note "ok   A6: under the ceiling"
    else
      fail "A6: ${hb} bytes is over the ${hi_ceiling}-byte ceiling"
    fi
  fi

  # ABLATION for A6. `noindirect` stops excluding @__axiom_symtab, the
  # backtrace table that lists EVERY function in the program. Every
  # function then looks address-taken, the one indirect call site in
  # the runtime's drop glue resolves to all of them, and hello world
  # stops being boundable. This is the assertion that the exclusion is
  # doing real work rather than being decoration.
  checks=$((checks + 1))
  ab="$(AXIOM_ABLATE_STACK_BOUND=noindirect python3 "$analyzer" $(bound_args hi) 2>&1 |
        sed -n 's/^BOUND from main: \([0-9]*\) bytes$/\1/p')"
  if [[ -z "$ab" ]]; then
    note "ok   A6 ablation: =noindirect makes hello world unboundable, which A6 rejects"
  else
    fail "A6 ablation: =noindirect still bounded hello world at ${ab} bytes"
  fi
fi

# --------------------------------------------------------------------
# A GATE THAT RAN NOTHING MUST NOT REPORT SUCCESS.
#
# Every assertion above is guarded by something that can decline to run
# it: a fixture that would not build, a shell that cannot set
# `ulimit -s`, a toolchain with no stack-usage table. Each of those
# prints a reason - but a run in which HALF of them declined still
# reached the bottom of this file and said "passed", and nothing here
# would have noticed. That is this repository's most common defect
# arriving by the back door: not a check that cannot fail, but a check
# that was never reached.
#
# So the count is asserted. Twelve assertions when llc offers a
# stack-usage table, ten without it (A2 and A3 are the two that need
# one, and they announce themselves when they skip). Anything less means
# a guard above declined silently, and the reason is in the log.
# --------------------------------------------------------------------
expected=10
(( su_ok )) && expected=12
if (( checks < expected )); then
  echo "FAIL: only $checks of $expected assertions ran. Something above declined" >&2
  echo "      to run rather than failing - a fixture that would not build, or a" >&2
  echo "      shell that cannot set ulimit -s. Read the log above for which; a" >&2
  echo "      gate that skipped its way to green is not a passing gate." >&2
  failed=$((failed + 1))
fi

echo
if (( failed )); then
  echo "check-stack-bound: $failed of $checks assertions FAILED" >&2
  exit 1
fi
echo "check-stack-bound: gate passed ($checks assertions, $expected expected)"
