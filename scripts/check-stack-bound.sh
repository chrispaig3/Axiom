#!/usr/bin/env bash
#
# Compute "this binary needs at most N bytes of stack", and check the
# computation against a measurement.
#
# `scripts/check-stack-depth.sh` bisects `ulimit -s`, which suits the
# recursive compiler but not a microcontroller (docs/embedded-guide.md).
# Under `;@axiom:restrict(no-recursion)` the compiler proves the call
# graph acyclic (AX3049, scripts/check-restrictions.sh), so it has a
# longest path, and `scripts/lib/stack-bound.py` computes it.
#
# Frame sizes come from llc, which lays out frames after `axiom` hands
# over text IR (self_host/driver.ax, `IR -> opt -> llc -> cc`). They are
# read from llc's `--stack-usage-file`, or parsed from the prologues in
# `llc -filetype=asm`.
#
# Assertions:
#   A1  Two no-recursion chains, 400 and 1200 frames, at --opt 0. Each
#       bound is within 32 KiB of the bisected `ulimit -s` floor, and
#       the two bounds' difference matches the floors' within 16 KiB,
#       which cancels the per-process constant.
#   A2  Over every compiler function, the prologue parse agrees with
#       llc's stack-usage table, which is what lets the parse stand alone
#       where llc has no table. Without a table it is skipped, loudly.
#   A3  Every frame is `static`: a variable-sized alloca would leave no
#       static bound. A3b checks the line-table rule has stores to see.
#   A4  The compiler's own IR is refused with a named cycle.
#   A5  A recursive fixture under `restrict(no-recursion)` draws AX3049
#       from the compiler. Untagged, the analyzer refuses the same cycle.
#   A6  Hello world at --opt 1 gets a bound under a ceiling.
#
# Ablations. `AXIOM_ABLATE_STACK_BOUND` is read only by the analyzer,
# and each value must turn one assertion red:
#   flat        charge only the root's own frame  -> A1 collapses
#   nocycle     do not refuse a cyclic graph      -> A4 gets a number
#   noindirect  drop the symbol-table exclusion   -> A6 unboundable
#
# Keep the tolerance two-sided. `ulimit -s L` does not grant exactly L:
# darwin grants a few KiB more, the Linux gate container about 13 KiB
# less, and the offset varies by binary over about 12 KiB. A one-sided
# check would test the host's stack accounting, not the bound.
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
# Toolchain probe. LLVM 18's llc, in the Linux gate image and CI's apt
# llvm, has no `--stack-usage-file`; newer ones such as Homebrew's do.
# A2, A3 and A3b need it. Everything else runs from the prologue parse.
# The skip is announced, never silent.
# --------------------------------------------------------------------
# Write llc's help to a file, not a pipe. Under `pipefail`,
# `llc --help-list-hidden | grep -q X` fails when grep matches: grep
# exits at the first hit, llc dies of SIGPIPE, and 141 propagates. The
# flag would then read as missing on every llc, skipping A2, A3 and A3b.
su_ok=0
llc --help-list-hidden >"$work/llc-help.txt" 2>/dev/null || true
if grep -q -- '--stack-usage-file' "$work/llc-help.txt"; then su_ok=1; fi
llcver="$(llc --version 2>/dev/null | grep -i 'LLVM version' | head -1 | sed 's/^ *//')"
note "== llc: ${llcver:-unknown} ; stack-usage-file: $([[ $su_ok == 1 ]] && echo yes || echo no) =="

# Reproduce the driver's pipeline. emit-llvm gives pre-opt IR, so opt
# and llc run here at the level `axiom build --opt N` would use.
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

# bisect <binary>: the smallest `ulimit -s`, in KiB, at which the binary
# still exits 0. Any non-zero exit below that reads as out of stack, so
# a binary that fails for another reason gives a meaningless floor.
run_at() {
  local kib="$1"
  # Discard the subshell's stderr: runs below the floor die by SIGSEGV,
  # and bash announces each one. Only the exit status matters.
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
# The chain fixtures are generated, not checked in: at K=60 live locals
# they are about 700 KB of source. Documents must not name them, since
# check-doc-drift.sh resolves every path a document names. K=60 makes
# each frame fat, so the difference between the chains dwarfs the host's
# per-process scatter. The `+` after each call keeps the frame live
# across it, so no tail-call rewrite can flatten the chain.
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
# A1: the arithmetic, against a measurement.
#
# --opt 0 is required. At --opt 1 the inliner flattens a deep chain to
# `ret i64 0`, whose bound is correctly a few bytes, so only --opt 0
# exercises the path arithmetic.
# ====================================================================
# Plain variables rather than an associative array: darwin's /bin/bash
# is 3.2 and has no `declare -A`.
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

  # Ablation for A1. `flat` charges only the root's own frame, so the
  # chain's bound collapses to a couple of words and A1 must reject it.
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
# A2, A3 and A4, all from one emit of the compiler's own IR.
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

    # A3. The `.su` table's third column is `static` or `dynamic`. A
    # dynamic frame is a variable-sized alloca, and no program reaching
    # one has a static bound. The analyzer refuses on one (exit 2); this
    # asserts the stronger fact over every row.
    checks=$((checks + 1))
    ndyn="$(awk -F'\t' '$3 != "static" && NF >= 3' "$work/selfhost.su" | wc -l | tr -d ' ')"
    nrow="$(wc -l <"$work/selfhost.su" | tr -d ' ')"
    if [[ "$ndyn" == 0 ]]; then
      note "ok   A3: all $nrow frames of the compiler are static - no dynamic alloca in emitted IR"
    else
      fail "A3: $ndyn of $nrow frames are dynamic, so no static bound exists for them"
      awk -F'\t' '$3 != "static" && NF >= 3' "$work/selfhost.su" | head -5 | sed 's/^/    /' >&2
    fi

    # A3b. The analyzer's blockaddress rule (line-table stores) must
    # have stores to act on. If the emitter stops marking calls, this
    # trips. The floor of 100 is about two orders below self_host's
    # count, so only losing the markers can reach it.
    checks=$((checks + 1))
    nba="$(grep -c 'blockaddress(@' "$work/selfhost.ll" || true)"
    if (( nba >= 100 )); then
      note "ok   A3b: $nba blockaddress stores in the analyzed IR - the line-table rule fired"
    else
      fail "A3b: only $nba blockaddress stores in the analyzed IR - the line-table rule ran vacuous"
    fi
  else
    note "SKIP: A2 and A3 need \`llc --stack-usage-file\`, which this llc does not"
    note "      have (LLVM 18 has no such flag; LLVM 23 does). The prologue parse"
    note "      is therefore UNCROSS-CHECKED on this leg, and A3's no-dynamic-frame"
    note "      claim is unverified here. Run this gate on a leg with LLVM 19+ to"
    note "      cover them; run-gates.sh on darwin does."
  fi

  # A4. The compiler recurses, so it has no static bound. The analyzer
  # must say so and name a cycle vertex, not return a number from a
  # partial walk.
  checks=$((checks + 1))
  a4_out="$(python3 "$analyzer" $(bound_args selfhost) 2>&1)"
  a4_rc=$?
  if (( a4_rc == 3 )) && grep -q '^REFUSE: cycle at ' <<<"$a4_out"; then
    note "ok   A4: the compiler is refused - $(grep '^REFUSE:' <<<"$a4_out")"
  else
    fail "A4: the compiler was not refused with a cycle (rc=$a4_rc)"
    tail -3 <<<"$a4_out" | sed 's/^/    /' >&2
  fi

  # Ablation for A4. `nocycle` closes the cycle silently and returns a
  # number, which A4 must reject.
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
# A5: the compiler's static claim and this analysis agree.
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

# The same source with the tag deleted compiles, and the analyzer then
# refuses it for the reason the compiler gave.
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
# A6: hello world's bound, under a ceiling.
#
# The ceiling is loose. The number is printed every run, so a regression
# shows in the log long before it turns red.
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

  # Ablation for A6. `noindirect` stops excluding @__axiom_symtab, the
  # backtrace table that lists every function. Every function then looks
  # address-taken, the one indirect call in the runtime's drop glue
  # resolves to all of them, and hello world becomes unboundable.
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
# A gate that ran nothing must not pass.
#
# Every assertion above has a guard that can decline to run it: a
# fixture that would not build, a shell that cannot set `ulimit -s`, a
# toolchain with no stack-usage table. Each prints a reason, and this
# count fails the run when any declined. It is one per `checks`
# increment above: ten, or thirteen when llc offers a stack-usage table
# for A2, A3 and A3b.
# --------------------------------------------------------------------
expected=10
(( su_ok )) && expected=13
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
