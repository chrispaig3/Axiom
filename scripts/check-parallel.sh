#!/usr/bin/env bash
# `parallel`: one surface, two lowerings, the same bytes out of both.
#
# `(parallel p ((a e1) (b e2)) body)` runs every binding beside the
# caller and joins them in argument order (docs/memory-model-v2-design.md
# MM-RGN-7, `self_host/parser.ax` `parseParallelExpr`). Codegen lowers
# the pair of primitives it desugars to in two ways - PROCESSES by
# default (fork, one shared page per binding, wait4) and THREADS under
# `--threads` (the platform's pthread, the eight runtime globals
# thread-local) - and the whole claim of "one surface, two lowerings"
# is that a program cannot tell which it got. This gate is where that
# is measured, on the two fixtures the runner already executes under
# the default lowering:
#
#   tests/stdlib/470-parallel.ax        seven terms, words in and out
#   tests/stdlib/471-parallel-trap.ax   a binding that traps, status 77
#
# THE ASSERTIONS, in the order a reader of the design would ask them:
#
#   1. the same stdout and the same exit status out of both lowerings,
#      byte for byte, for both fixtures - including the trap, which
#      under processes is a CHILD dying and the join re-raising its
#      status, and under threads is `exit_group` from a second thread;
#   2. the process lowering imports NOTHING the same program did not
#      import before `parallel` existed - it is fork and wait4 through
#      the syscall template, so `check-freestanding.sh`'s zero holds
#      for it - and the thread lowering imports exactly the two pthread
#      entry points and, on Darwin, the TLS bootstrap: the price of a
#      thread, enumerated;
#   3. the thread lowering moves exactly the eight runtime globals to
#      `thread_local(localexec)` and the process lowering moves none,
#      which is `cgThreads` following the PROGRAM AND THE FLAG rather
#      than the flag alone - and a program with no `parallel` built
#      under `--threads` is byte-identical to the same program built
#      without it, so the flag is inert where nothing spawns;
#   4. the targets that cannot: `--threads` for freebsd-x86_64 is
#      refused at build time as AX4006, before any IR is written, and
#      windows-x86_64 - no `fork`, no pthread - EMITS the program with
#      both primitives lowered to `@__axiom_par_unsupported`, which is
#      what keeps every cross-target sweep green and the answer honest:
#      the program links and dies at its first spawn saying why (79).
#      4b adds the build-time half of that second sentence: AX4007, a
#      WARNING and not a refusal, so the module still emits and a
#      program whose `parallel` is on a path it never takes still
#      builds and runs - what changes is that it is told at build time
#      rather than at the first spawn;
#   5. the negative half of 1: the trap fixture's 77 is the CHILD's
#      status re-raised, not the parent's own - a join that swallowed
#      the child's status would answer 0, and this arm asserts the
#      fixture's `.exit` is what the process lowering produces AND what
#      the thread lowering produces, against a control that exits 0.
#
#   6. AND THE POOL BUILT ON THOSE PRIMITIVES. `stdlib/Par.ax` replaced
#      `stdlib/Job.ax` at 0.7.4: a bounded pool over `__proc_spawn` /
#      `__proc_join` that runs an Axiom CLOSURE, which is the limit
#      `docs/memory-model.md` MM-PAR-2 named as Job's. Four arms, and
#      the second is the load-bearing one:
#        (a) `tests/stdlib/476-par-pool.ax` answers its golden - whose
#            first sixteen lines are the deleted `302-job` golden,
#            byte for byte;
#        (b) the pool is FLAG-INDEPENDENT: its module is BYTE-IDENTICAL
#            with and without `--threads`. That is not a nicety. AX3064
#            cannot see a capture through `parMapWords`, because
#            `checkSpawnCaptures` inspects argument 0 only when it is
#            literally a lambda and `parMapWords` spawns a PARAMETER -
#            so the safety of every caller's capture rests on this file
#            naming `__proc_spawn`, and nothing in the type system would
#            notice if that word changed. This arm is the check the rule
#            cannot make;
#        (c) the width bound is real, as a RATIO of wall times rather
#            than a wall time, so it survives a loaded battery;
#        (d) the pool adds no import over the same `plain.ax` control
#            arm 2 uses, so `check-freestanding.sh`'s zero holds for it.
#
#   7. FREEBSD IS MEASURED, and this is the leg that measures it.
#      `docs/status.md` said "freebsd is unmeasured" until 2026-09-04
#      and it was FALSE: `Tests (freebsd-x86_64)` boots FreeBSD 14.4
#      and runs `run-stdlib-tests.sh`, whose loop is a glob over
#      `tests/stdlib/`, so all three fixtures EXECUTE there on a real
#      kernel. This section holds the leg, because the leg IS the claim.
#
#   8. A BINDING THAT ALLOCATES, which nothing executed before. Every
#      `parallel` binding this repository ran was arithmetic, so no
#      test had ever called `axiom_alloc` from a second thread - the
#      one thing the eight thread-local globals exist for.
#
#   9. TWO bindings that trap, which is where "a program cannot tell
#      which lowering it got" STOPS being true. Processes are
#      deterministic and source-ordered; threads answer whichever trap
#      fired first. Measured, deliberately not fixed, and that section's
#      comment carries the reasoning.
#
#  10. A trap inside a THREAD, and where its backtrace ends. A pthread
#      stack has no `main` on it, so the walk's only stop could never
#      fire and it named two frames of libSystem with this module's
#      own symbols.
#
# NOTHING HERE IS LOAD-SENSITIVE, which is why this gate stays in
# `run-gates.sh`'s PARALLEL set even though sections 8-10 are about
# concurrency. Arm 6c is a RATIO for that reason and says so; section
# 8's arms are deterministic, because each binding allocates in an
# arena of its own and the answers are pure; section 9 asserts the
# process lowering's statuses exactly and only the MEMBERSHIP of the
# thread lowering's, so no arm predicts which thread wins a race;
# section 10 removes frames rather than counting a window. The one racy
# measurement made while writing this - section 8's storage-class
# ablation, which fired in one run of five - is recorded in that
# section's comment and asserted nowhere, for that reason.
#
# WHAT THIS GATE DOES NOT CLAIM. The thread lowering does not yet check
# what a binding captures: a heap value shared with the parent is
# touched from two threads with no fence, which the process lowering
# cannot suffer and the static rule that refuses it (MM-RGN-3 over
# sibling regions) is S3's. Both fixtures capture only words, on
# purpose, and `emitPrimPar`'s header in codegen.ax states the gap.
#
# NOR does it claim AX3064 is complete. Measured 2026-09-03 on this
# compiler: a literal `(__par_spawn (lambda (w) (+ (strLen s) w)) 1)`
# capturing a `String` draws AX3064, and the SAME lambda handed to a
# one-line wrapper `(fn (viaHop f w) (__par_join (__par_spawn f w)))`
# draws nothing and runs. The rule is bypassed by one hop. It is latent
# rather than live - the parser's desugaring always emits a literal
# lambda, so no `parallel` written in source reaches it - and closing it
# is its own workstream. Section 6b is what keeps `Par.ax` out of the
# hole in the meantime.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc
source "$(dirname "${BASH_SOURCE[0]}")/lib/imports.sh"

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

fx470="$repo_root/tests/stdlib/470-parallel.ax"
fx471="$repo_root/tests/stdlib/471-parallel-trap.ax"
[[ -f "$fx470" && -f "$fx471" ]] || { echo "FAIL: the two fixtures are missing"; exit 1; }

# --------------------------------------------------------------------
echo "== 1. both fixtures, both lowerings, the same bytes =="
# --------------------------------------------------------------------
run_case() {  # <fixture> <flag-or-empty> <tag> -> writes $work/<tag>.out and .status
  local fx="$1" flag="$2" tag="$3"
  if ! "$axc" build $flag --input "$fx" --output "$work/$tag.bin" > "$work/$tag.build" 2>&1; then
    bad "$tag: would not build"; sed 's/^/     /' "$work/$tag.build" | head -5; return 1
  fi
  ( cd "$work" && "./$tag.bin" > "$work/$tag.out" 2> "$work/$tag.err" ); echo $? > "$work/$tag.status"
  return 0
}
run_case "$fx470" ""          p470 || true
run_case "$fx470" "--threads" t470 || true
run_case "$fx471" ""          p471 || true
run_case "$fx471" "--threads" t471 || true

for c in 470 471; do
  if [[ -f "$work/p$c.status" && -f "$work/t$c.status" ]]; then
    if cmp -s "$work/p$c.out" "$work/t$c.out" && [[ "$(cat "$work/p$c.status")" == "$(cat "$work/t$c.status")" ]]; then
      ok "$c: processes and threads answer the same stdout ($(wc -l < "$work/p$c.out" | tr -d ' ') lines) and exit $(cat "$work/p$c.status")"
    else
      bad "$c: the two lowerings differ - processes exit $(cat "$work/p$c.status"), threads exit $(cat "$work/t$c.status")"
      diff "$work/p$c.out" "$work/t$c.out" | head -10 | sed 's/^/     /'
    fi
  fi
done
# And against the checked-in golden, so "the same" is not "the same wrong".
if cmp -s "$work/p470.out" "$repo_root/tests/stdlib/470-parallel.out"; then
  ok "470: and the bytes are the fixture's golden"
else
  bad "470: the process lowering disagrees with tests/stdlib/470-parallel.out"
  diff "$work/p470.out" "$repo_root/tests/stdlib/470-parallel.out" | head -10 | sed 's/^/     /'
fi

# --------------------------------------------------------------------
echo
echo "== 2. what each lowering imports =="
# --------------------------------------------------------------------
# The control: the same program with its `parallel` forms removed is
# not what is compared, because no such program exists; instead a
# program that spawns nothing at all, whose imports are the platform's
# baseline for this host (Linux: the six crt symbols; Darwin: none).
cat > "$work/plain.ax" <<'PLAIN'
(import IO)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println "plain")
    0
  }
)
PLAIN
"$axc" build --input "$work/plain.ax" --output "$work/plain.bin" > /dev/null 2>&1 || bad "the plain program would not build"
imports_of "$work/plain.bin" | LC_ALL=C sort > "$work/plain.imports"
imports_of "$work/p470.bin"  | LC_ALL=C sort > "$work/p470.imports"
imports_of "$work/t470.bin"  | LC_ALL=C sort > "$work/t470.imports"
added_p="$(comm -13 "$work/plain.imports" "$work/p470.imports" | tr '\n' ' ')"
if [[ -z "${added_p// /}" ]]; then
  ok "processes: the lowering adds no import (baseline $(grep -c . "$work/plain.imports" || true) on this host)"
else
  bad "processes: the lowering added imports: $added_p"
fi
added_t="$(comm -13 "$work/plain.imports" "$work/t470.imports")"
thread_syms='pthread_create|pthread_join|__tlv_bootstrap|_tlv_bootstrap|__tls_get_addr|__tlsdesc_resolve'
stray="$(printf '%s\n' "$added_t" | grep -vE "^($thread_syms)$" | grep . || true)"
if [[ -z "$stray" ]] && printf '%s\n' "$added_t" | grep -q '^pthread_create$'; then
  ok "threads: the lowering adds only the thread's own symbols: $(printf '%s\n' "$added_t" | tr '\n' ' ')"
else
  bad "threads: expected pthread_create (and pthread_join, plus the TLS bootstrap on Darwin), got: $(printf '%s\n' "$added_t" | tr '\n' ' ')"
  [[ -n "$stray" ]] && printf '%s\n' "$stray" | sed 's/^/     stray: /'
fi

# --------------------------------------------------------------------
echo
echo "== 3. the eight globals move under threads, none under processes, and the flag is inert without a spawn =="
# --------------------------------------------------------------------
"$axc" emit-llvm "$fx470" -o "$work/p470.ll" > /dev/null 2>&1
"$axc" --threads emit-llvm "$fx470" -o "$work/t470.ll" > /dev/null 2>&1
tl_p="$(grep -c 'thread_local' "$work/p470.ll" || true)"
tl_t="$(grep -c '= internal thread_local(localexec) global' "$work/t470.ll" || true)"
if [[ "$tl_p" == 0 ]]; then ok "processes: no thread_local in the module"; else bad "processes: $tl_p thread_local line(s)"; fi
# eight: the five allocator words, the slab array, @__axiom_recover_top,
# and one evidence slot per effect - the fixture declares none, so 7.
# check-thread-local.sh counts them by name; here the number is what a
# program with no effect must get.
if [[ "$tl_t" == 7 ]]; then ok "threads: 7 thread_local(localexec) globals - the eight less the evidence slot this fixture has no effect for"; else bad "threads: $tl_t thread_local globals, expected 7"; grep 'thread_local' "$work/t470.ll" | sed 's/^/     /' | head -10; fi
for g in __axiom_bump __axiom_bump_end __axiom_chunk __axiom_free __axiom_high __axiom_slabs __axiom_recover_top; do
  grep -q "^@$g = internal thread_local(localexec) global" "$work/t470.ll" || bad "threads: @$g did not move"
done
if grep -q '@__axiom_arg[cv] = internal thread_local' "$work/t470.ll"; then bad "threads: argc/argv moved; they are write-once and shared by design"; else ok "threads: @__axiom_argc/argv stayed shared"; fi
# The runtime halves: the process module carries no pthread declare and
# the thread module carries exactly two.
dp="$(grep -c '^declare i32 @pthread_' "$work/p470.ll" || true)"
dt="$(grep -c '^declare i32 @pthread_' "$work/t470.ll" || true)"
[[ "$dp" == 0 ]] && ok "processes: no pthread declare" || bad "processes: $dp pthread declare(s)"
[[ "$dt" == 2 ]] && ok "threads: two pthread declares, create and join" || bad "threads: $dt pthread declare(s), expected 2"
# Inert without a spawn.
"$axc" emit-llvm "$work/plain.ax" -o "$work/plain.ll" > /dev/null 2>&1
"$axc" --threads emit-llvm "$work/plain.ax" -o "$work/plain-t.ll" > /dev/null 2>&1
if cmp -s "$work/plain.ll" "$work/plain-t.ll"; then
  ok "a program that spawns nothing is byte-identical with and without --threads ($(wc -l < "$work/plain.ll" | tr -d ' ') lines)"
else
  bad "--threads changed a program that spawns nothing"
  diff "$work/plain.ll" "$work/plain-t.ll" | head -10 | sed 's/^/     /'
fi
if grep -q '@__axiom_par_' "$work/plain.ll"; then bad "the parallel runtime was emitted for a program that never spawns"; else ok "and no line of the parallel runtime is in it"; fi

# --------------------------------------------------------------------
echo
echo "== 4. the targets that cannot =="
# --------------------------------------------------------------------
set +e
"$axc" --target=freebsd-x86_64 --threads emit-llvm "$fx470" -o "$work/fbt.ll" > "$work/fbt.log" 2>&1
rc=$?
if [[ "$rc" != 0 ]] && grep -q 'AX4006' "$work/fbt.log"; then
  ok "freebsd-x86_64 --threads: refused as AX4006 (exit $rc), no IR written"
else
  bad "freebsd-x86_64 --threads: expected AX4006 and a non-zero exit, got exit $rc"
  sed 's/^/     /' "$work/fbt.log" | head -5
fi
if "$axc" --target=freebsd-x86_64 emit-llvm "$fx470" -o "$work/fbp.ll" > /dev/null 2>&1 \
   && grep -q '@__axiom_par_spawn_proc' "$work/fbp.ll" && ! grep -q 'pthread' "$work/fbp.ll"; then
  ok "freebsd-x86_64 without the flag: the process lowering, no pthread"
else
  bad "freebsd-x86_64 without the flag did not emit the process lowering"
fi
if "$axc" --target=windows-x86_64 emit-llvm "$fx470" -o "$work/win.ll" > /dev/null 2>&1; then
  n_unsup="$(grep -c 'call i64 @__axiom_par_unsupported()' "$work/win.ll" || true)"
  if [[ "$n_unsup" -gt 0 ]] && ! grep -q 'pthread\|__axiom_par_spawn_proc\|thread_local' "$work/win.ll"; then
    ok "windows-x86_64: emits, with $n_unsup spawn/join site(s) lowered to the status-79 trap and no fork, pthread or thread_local"
  else
    bad "windows-x86_64: expected only the unsupported trap ($n_unsup site(s))"
  fi
  if llc -O0 -filetype=obj -o "$work/win.o" "$work/win.ll" 2> "$work/win.llc"; then
    ok "windows-x86_64: and the module assembles"
  else
    bad "windows-x86_64: the module does not assemble"; sed 's/^/     /' "$work/win.llc" | head -3
  fi
else
  bad "windows-x86_64: would not emit"
fi
set +e
"$axc" --target=windows-x86_64 --threads emit-llvm "$fx470" -o "$work/wint.ll" > "$work/wint.log" 2>&1
rc=$?
if [[ "$rc" != 0 ]] && grep -q 'AX4006' "$work/wint.log"; then ok "windows-x86_64 --threads: refused as AX4006"; else bad "windows-x86_64 --threads: expected AX4006, exit $rc"; fi

# --- 4b. and the DEFAULT lowering says so at build time too: AX4007 ---
#
# Until 2026-09-04 the only notice a windows build gave about the
# process lowering was status 79 at the first spawn, at RUN time, on
# the lowering a program gets without asking. AX4007 moves that to
# build time - as a WARNING, not a refusal, because the module must
# still emit (arm 4 above, `check-freestanding.sh`'s windows sweep and
# `check-cross-targets.sh` all compile these fixtures for windows) and
# because a program whose `parallel` sits on a path it never takes
# builds and runs there today. An error would break such a program for
# a failure it would never suffer.
#
# THREE THINGS, and the third is the one that keeps it from being
# noise: the warning is emitted, the exit status is still 0 and the IR
# is still written, and a windows build of a program that names no
# spawn says NOTHING - the diagnostic follows the PROGRAM, exactly as
# `cgThreads` does, not the target.
"$axc" --target=windows-x86_64 --diagnostic-format=ai emit-llvm "$fx470" -o "$work/win4007.ll" > "$work/win4007.log" 2>&1
rc=$?
if [[ "$rc" == 0 ]] && grep -q 'W AX4007' "$work/win4007.log" && [[ -s "$work/win4007.ll" ]]; then
  ok "windows-x86_64: the default lowering warns AX4007 at build time, exit 0, and the IR is still written"
else
  bad "windows-x86_64: expected an AX4007 warning with exit 0 and IR written, got exit $rc"
  sed 's/^/     /' "$work/win4007.log" | head -5
fi
"$axc" --target=windows-x86_64 --diagnostic-format=ai emit-llvm "$work/plain.ax" -o "$work/winplain.ll" > "$work/winplain.log" 2>&1
if grep -q 'AX4007' "$work/winplain.log"; then
  bad "windows-x86_64: a program that names no spawn drew AX4007 - the warning is following the target, not the program"
else
  ok "windows-x86_64: and a program that names no spawn draws nothing"
fi
# The hosts that CAN spawn never see it, whatever they build.
if "$axc" --diagnostic-format=ai emit-llvm "$fx470" -o "$work/host4007.ll" > "$work/host4007.log" 2>&1 \
   && ! grep -q 'AX4007' "$work/host4007.log"; then
  ok "and this host, which can fork, draws nothing for the same fixture"
else
  bad "this host drew AX4007 for a fixture it can lower"
  sed 's/^/     /' "$work/host4007.log" | head -5
fi
set +e

# --------------------------------------------------------------------
echo
echo "== 5. the trap's status is the child's, re-raised =="
# --------------------------------------------------------------------
want="$(cat "$repo_root/tests/stdlib/471-parallel-trap.exit")"
for tag in p471 t471; do
  [[ -f "$work/$tag.status" ]] || continue
  got="$(cat "$work/$tag.status")"
  if [[ "$got" == "$want" ]] && grep -q 'vector index out of range' "$work/$tag.err"; then
    ok "$tag: exit $got with the child's message on fd 2"
  else
    bad "$tag: exit $got, wanted $want with the trap's message"
  fi
done
# The control: a binding that answers normally exits 0 - so 77 above is
# the child's status and not this gate's expectation of failure.
cat > "$work/fine.ax" <<'FINE'
(import IO)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (parallel p ((a 1) (b 2))
    (println (+ a b))
    0))
FINE
run_case "$work/fine.ax" "" fine || true
if [[ "$(cat "$work/fine.status" 2>/dev/null)" == 0 && "$(cat "$work/fine.out")" == 3 ]]; then
  ok "control: a binding that answers exits 0 and the body saw 3"
else
  bad "control: exit $(cat "$work/fine.status" 2>/dev/null) out [$(cat "$work/fine.out" 2>/dev/null)]"
fi

# --------------------------------------------------------------------
echo
echo "== 6. the pool built on those primitives: stdlib/Par.ax =="
# --------------------------------------------------------------------
fx476="$repo_root/tests/stdlib/476-par-pool.ax"
gold476="$repo_root/tests/stdlib/476-par-pool.out"
if [[ ! -f "$fx476" || ! -f "$gold476" ]]; then
  bad "6: tests/stdlib/476-par-pool.{ax,out} are missing"
else

# --- 6a. the fixture answers its golden ---
#
# 476 is the deleted `302-job` fixture with `Job` swapped for `Par`,
# plus one term Job could never run. Its first sixteen output lines ARE
# that fixture's golden, measured byte for byte before it was deleted,
# so this arm is
# the same three discriminating terms `Job` was gated on - submit order
# under a reversed completion order, a `strSlice` argument that must be
# `strDup`ed, and a missing program answering `-ENOENT` in its own slot -
# plus a fourth: an Axiom closure over a captured `Vec`, with no exec at
# all.
if run_case "$fx476" "" p476; then
  if cmp -s "$work/p476.out" "$gold476" && [[ "$(cat "$work/p476.status")" == 0 ]]; then
    ok "476: the pool answers its golden ($(wc -l < "$gold476" | tr -d ' ') lines) and exits 0"
  else
    bad "476: the pool disagrees with tests/stdlib/476-par-pool.out (exit $(cat "$work/p476.status"))"
    diff "$work/p476.out" "$gold476" | head -10 | sed 's/^/     /'
  fi
fi

# --- 6b. the pool is FLAG-INDEPENDENT, byte for byte ---
#
# THE ARM THAT MATTERS. `Par.ax` names `__proc_spawn`, the primitive
# `capSpawnHead` exempts from AX3064 because it NAMES the forked
# lowering - MM-PAR-3's isolation by construction. A pool that lowered
# to threads under a flag would be a pool whose safety depended on how
# it was built, and AX3064 cannot catch that here: `parMapWords` spawns
# a parameter, and `checkSpawnCaptures` only looks inside a literal
# lambda. So the fact is measured instead, at its strongest: the module
# the compiler emits is IDENTICAL with and without `--threads`.
"$axc" emit-llvm "$fx476" -o "$work/p476.ll" > /dev/null 2>&1
"$axc" --threads emit-llvm "$fx476" -o "$work/t476.ll" > /dev/null 2>&1
if cmp -s "$work/p476.ll" "$work/t476.ll"; then
  ok "476: the module is byte-identical with and without --threads ($(wc -l < "$work/p476.ll" | tr -d ' ') lines)"
else
  bad "476: --threads changed the pool's module - it is not naming __proc_spawn"
  diff "$work/p476.ll" "$work/t476.ll" | head -10 | sed 's/^/     /'
fi
n_pth="$(grep -c '^declare i32 @pthread_' "$work/t476.ll" || true)"
n_tl="$(grep -c 'thread_local' "$work/t476.ll" || true)"
n_proc="$(grep -c '@__axiom_par_spawn_proc' "$work/p476.ll" || true)"
if [[ "$n_pth" == 0 && "$n_tl" == 0 && "$n_proc" -gt 0 ]]; then
  ok "476: $n_proc fork-lowered spawn site(s), 0 pthread declares and 0 thread_local under --threads"
else
  bad "476: expected 0 pthread declares and 0 thread_local under --threads with fork-lowered spawns; got $n_pth, $n_tl, $n_proc"
fi

# --- 6c. the width bound is real ---
#
# Eight `sleep 0.2` at width 1 against the same eight at width 8. As a
# RATIO, not a wall time: this gate runs six-up in `run-gates.sh`'s
# parallel phase, where an absolute threshold is a flake. Measured
# unloaded on darwin-aarch64, 2026-09-03: width 1 = 3.37 s, width 2 =
# 1.08 s, width 4 = 1.00 s, width 8 = 0.43 s - a ratio near 8, against
# the 2.5 required here.
cat > "$work/width.ax" <<'WIDTH'
(import IO)

(import Sys)

(import Str)

(import Vec)

(import Par)

(pub :: main Int)

;@axiom:effect(io)
(pub fn (main)
  (let (
    (cmds vecNew)
    (mut i 0)
    (w (match (strParseInt (sysArg 1)) ((Some n) n) (None 1)))
  )
    {
      (while (< i 8)
        {
          (let ((v vecNew))
            {
              (vecPush v "/bin/sh")
              (vecPush v "-c")
              (vecPush v "sleep 0.2")
              (vecPush cmds v)
            })
          (set i (+ i 1))
        })
      (println (vecLen (parRunAll cmds w)))
      0
    }
  )
)
WIDTH
now() { python3 -c 'import time;print(time.time())'; }

# `<binary> -> "<ratio> <t_width1> <t_width8>"`, shared by the arm and by
# its ablation so the two measure the same way.
#
# THE WARM-UP RUN IS NOT OPTIONAL, and leaving it out was measurably
# wrong: the ablated pool - width bound deleted, so both widths should
# take the same 0.25 s - reported a 2.06x ratio on its first pass, 20%
# from this arm's 2.5 threshold. Measured cause: the FIRST execution of
# a freshly linked binary pays dyld and page-cache costs. Cold then warm
# on darwin-aarch64, 2026-09-03: 0.481 / 0.254 / 0.262 / 0.254 / 0.249 /
# 0.252 s. One discarded run and the ablated ratio is 1.0, where it
# belongs.
pool_ratio() {  # <binary> -> ratio t1 t8 on stdout
  local bin="$1"
  ( cd "$work" && "$bin" 8 > /dev/null 2>&1 )   # warm-up, discarded
  local a b c
  a="$(now)"; ( cd "$work" && "$bin" 1 > "$work/w1.out" ); b="$(now)"
  ( cd "$work" && "$bin" 8 > "$work/w8.out" ); c="$(now)"
  python3 -c "import sys;x=float(sys.argv[2])-float(sys.argv[1]);y=float(sys.argv[3])-float(sys.argv[2]);print('%.2f %.3f %.3f' % (x/y if y>0 else 0, x, y))" "$a" "$b" "$c"
}
if "$axc" build --input "$work/width.ax" --output "$work/width.bin" > "$work/width.build" 2>&1; then
  ratio="$(pool_ratio ./width.bin)"
  r="${ratio%% *}"; times="${ratio#* }"
  if [[ "$(cat "$work/w1.out")" == 8 && "$(cat "$work/w8.out")" == 8 ]]; then
    if python3 -c "import sys;sys.exit(0 if float(sys.argv[1]) > 2.5 else 1)" "$r"; then
      ok "width: 8 x sleep 0.2 takes ${r}x longer at width 1 than at width 8 (${times}s), so the bound blocks mid-run"
    else
      bad "width: the ratio is ${r}x (${times}s) - the pool is not bounding concurrency"
    fi
  else
    bad "width: the probe answered [$(cat "$work/w1.out")] and [$(cat "$work/w8.out")], expected 8 and 8"
  fi
else
  bad "width: the probe would not build"; sed 's/^/     /' "$work/width.build" | head -5
fi

# --- 6d. the pool imports nothing ---
#
# Arm 2's control and machinery, reused: `check-freestanding.sh`'s zero
# is a claim about the whole standard library, and a new module built on
# fork and wait4 through the syscall template must not move it.
if [[ -f "$work/p476.bin" && -f "$work/plain.imports" ]]; then
  imports_of "$work/p476.bin" | LC_ALL=C sort > "$work/p476.imports"
  added_pool="$(comm -13 "$work/plain.imports" "$work/p476.imports" | tr '\n' ' ')"
  if [[ -z "${added_pool// /}" ]]; then
    ok "476: the pool adds no import over the plain control"
  else
    bad "476: the pool added imports: $added_pool"
  fi
fi
fi

# --------------------------------------------------------------------
echo
echo "== 6e. the ablations: each of section 6's claims, deliberately broken =="
# --------------------------------------------------------------------
# Every edit lands in a COPY of `stdlib/`, the way `check-compat.sh`
# plants its negative probes, and this checkout is never touched. Each
# ablation ASSERTS THAT ITS EDIT LANDED (`cmp -s` before and after)
# before believing the result - `check-web.sh`'s rule, and the reason is
# that a `sed` that matched nothing produces a green "ablation failed to
# fail" that reads exactly like a passing gate.
abl_run() {  # <tag> <sed-program> <what-must-change> -> 0 when the ablation is red
  local tag="$1" prog="$2" what="$3"
  local copy="$work/abl-$tag"
  rm -rf "$copy"; mkdir -p "$copy"
  cp -r "$repo_root/stdlib" "$copy/stdlib"
  sed -e "$prog" "$repo_root/stdlib/Par.ax" > "$copy/stdlib/Par.ax"
  if cmp -s "$repo_root/stdlib/Par.ax" "$copy/stdlib/Par.ax"; then
    bad "ablation $tag: the edit did not land - $what was never broken, so the arm proved nothing"
    return 1
  fi
  return 0
}

# ABLATION 1 (arm 6a, term 1): the submit order is reversed. `parRunAll`
# maps slot `i` to `cmds[n-1-i]`, so the same eight children run and the
# same eight codes come back - in the other order. That is precisely the
# pool `Job.ax`'s header refused to be, and it is what a golden
# comparing bytes exists to catch. Each handle is still joined exactly
# once, so the ablation is a WRONG ANSWER rather than a crash - which is
# what an ablation should be, or it is proving that the program died
# rather than that the arm can see.
if abl_run order 's|(lambda (i) (parRunWord (vecGet cmds i)))|(lambda (i) (parRunWord (vecGet cmds (- (- (vecLen cmds) 1) i))))|' "submit order"; then
  if AXIOM_STDLIB="$work/abl-order/stdlib" "$axc" build --input "$fx476" --output "$work/abl-order.bin" > "$work/abl-order.build" 2>&1 \
     && ( cd "$work" && ./abl-order.bin > "$work/abl-order.out" 2>/dev/null ) \
     && cmp -s "$work/abl-order.out" "$gold476"; then
    bad "ablation order: reversing the submit mapping still answers the golden - arm 6a cannot fail"
  else
    ok "ablation order: a reversed submit mapping breaks the golden ($(diff "$work/abl-order.out" "$gold476" 2>/dev/null | grep -c '^<') line(s) differ), so arm 6a is measuring order"
  fi
fi

# ABLATION 1b (arm 6a, term 2): the `strDup` in `parArgvVector` dropped.
# `strCStr` is `strData` and nothing more, so a `strSlice` handed to the
# kernel runs on into whatever follows it in memory. 476's term 2 exists
# for exactly this, and it shows up as a WRONG CODE rather than a crash,
# which is the only reason the fixture can pin it.
if abl_run slice 's|(strCStr (strDup (vecGetStr argv i)))|(strCStr (vecGetStr argv i))|' "the argv strDup"; then
  if AXIOM_STDLIB="$work/abl-slice/stdlib" "$axc" build --input "$fx476" --output "$work/abl-slice.bin" > "$work/abl-slice.build" 2>&1 \
     && ( cd "$work" && ./abl-slice.bin > "$work/abl-slice.out" 2>/dev/null ) \
     && cmp -s "$work/abl-slice.out" "$gold476"; then
    bad "ablation slice: a non-NUL-terminated argv still answers the golden - term 2 is not discriminating"
  else
    ok "ablation slice: dropping the argv strDup breaks the golden, so term 2 is measuring the slice"
  fi
fi

# ABLATION 2 (arm 6b): `__proc_spawn` swapped for `__par_spawn`. The
# module then FOLLOWS the flag - measured 2 pthread declares and 7
# thread-local globals under `--threads` - which is the pool whose
# safety depends on how it was built, and the one arm 6b exists to
# refuse.
if abl_run flag 's/__proc_spawn/__par_spawn/g; s/__proc_join/__par_join/g' "the choice of primitive"; then
  AXIOM_STDLIB="$work/abl-flag/stdlib" "$axc" emit-llvm "$fx476" -o "$work/abl-flag-p.ll" > /dev/null 2>&1
  AXIOM_STDLIB="$work/abl-flag/stdlib" "$axc" --threads emit-llvm "$fx476" -o "$work/abl-flag-t.ll" > /dev/null 2>&1
  if [[ -f "$work/abl-flag-t.ll" ]] && cmp -s "$work/abl-flag-p.ll" "$work/abl-flag-t.ll"; then
    bad "ablation flag: __par_spawn still gives a flag-independent module - arm 6b cannot fail"
  else
    ok "ablation flag: __par_spawn makes the module follow --threads ($(grep -c '^declare i32 @pthread_' "$work/abl-flag-t.ll" || true) pthread declare(s), $(grep -c 'thread_local' "$work/abl-flag-t.ll" || true) thread_local), so arm 6b is measuring the primitive"
  fi
fi

# ABLATION 3 (arm 6c): the pre-spawn blocking loop deleted. Every task
# is forked at once whatever `width` says, so the two wall times
# converge and the ratio collapses toward 1.
if abl_run bound 's|(while (>= (- i joined) w)|(while (>= (- i joined) 999999)|' "the width bound"; then
  if AXIOM_STDLIB="$work/abl-bound/stdlib" "$axc" build --input "$work/width.ax" --output "$work/abl-bound.bin" > "$work/abl-bound.build" 2>&1; then
    abl_ratio="$(pool_ratio ./abl-bound.bin)"
    ar="${abl_ratio%% *}"
    if python3 -c "import sys;sys.exit(0 if float(sys.argv[1]) > 2.5 else 1)" "$ar"; then
      bad "ablation bound: with the blocking loop gone the ratio is still ${ar}x - arm 6c cannot fail"
    else
      ok "ablation bound: with the blocking loop gone the ratio collapses to ${ar}x, so arm 6c is measuring the bound"
    fi
  else
    bad "ablation bound: the ablated pool would not build"; sed 's/^/     /' "$work/abl-bound.build" | head -5
  fi
fi

# ABLATION 4 (the clamp): `(if (< width 1) 1 width)` deleted. A width of
# 0 then makes the submit loop join before it has spawned anything -
# `(>= 0 0)` is true - and the program traps on an empty handle vector
# instead of behaving like width 1. The clamp is not decoration.
if abl_run clamp 's|(w (if (< width 1)|(w (if (< width -1)|' "the width clamp"; then
  if AXIOM_STDLIB="$work/abl-clamp/stdlib" "$axc" build --input "$work/width.ax" --output "$work/abl-clamp.bin" > "$work/abl-clamp.build" 2>&1; then
    ( cd "$work" && ./abl-clamp.bin 0 > "$work/abl-clamp.out" 2> "$work/abl-clamp.err" ); crc=$?
    if [[ "$crc" == 0 ]]; then
      bad "ablation clamp: width 0 still answered [$(cat "$work/abl-clamp.out")] - the clamp is not load-bearing"
    else
      ok "ablation clamp: without it, width 0 dies (exit $crc), so the clamp is doing work"
    fi
  else
    bad "ablation clamp: the ablated pool would not build"; sed 's/^/     /' "$work/abl-clamp.build" | head -5
  fi
fi

# --------------------------------------------------------------------
echo
echo "== 7. freebsd: the process lowering is EXECUTED, and this is the leg that does it =="
# --------------------------------------------------------------------
# `docs/status.md` said "freebsd is unmeasured" until 2026-09-04 and it
# was FALSE. `Tests (freebsd-x86_64)` boots FreeBSD 14.4 in a VM and
# runs `scripts/run-stdlib-tests.sh`, whose loop is `for case_file in
# tests/stdlib/*.ax` with no skip list - so `470-parallel`,
# `471-parallel-trap` and `476-par-pool` EXECUTE there, on a real
# kernel, every run. Measured on trunk at run 33914283389, job
# 101157875183 (2026-09-04): `ok 470-parallel`, `ok 471-parallel-trap`,
# `ok 476-par-pool`, `109 passed, 0 failed`. That is exactly what
# README's *Targets* section means by SUPPORTED, and freebsd has been
# supported since 2026-08-30.
#
# What IS unavailable there is the THREAD lowering, and it is refused
# rather than untried - arm 4 above measures the AX4006.
#
# THIS ARM IS THE CLAIM'S GATE. The fact lives in a CI file this gate
# cannot run, so what is checked here is the thing that would silently
# take it away: the leg existing, being blocking, and still running the
# runner. A `continue-on-error:` line or a dropped step would turn
# "measured on freebsd" back into prose, and nothing else in the tree
# would notice - `check-release-targets.sh` holds the leg's EXISTENCE
# for the target list, not what it runs.
ci_yml="$repo_root/.github/workflows/ci.yml"
runner="$repo_root/scripts/run-stdlib-tests.sh"
if [[ ! -f "$ci_yml" || ! -f "$runner" ]]; then
  bad "7: .github/workflows/ci.yml or scripts/run-stdlib-tests.sh is missing"
else
  leg="$(awk '
    index($0, "name: Tests (freebsd-x86_64)") { found = 1; next }
    found && /^  [a-z]/ { exit }
    found { print }
  ' "$ci_yml")"
  if [[ -z "$leg" ]]; then
    bad "7: ci.yml has no 'Tests (freebsd-x86_64)' job - nothing executes what the compiler emits for freebsd"
  else
    if grep -q 'run-stdlib-tests\.sh' <<<"$leg"; then
      ok "freebsd: the leg runs run-stdlib-tests.sh, which is what executes the parallel fixtures there"
    else
      bad "freebsd: the leg no longer runs run-stdlib-tests.sh - the process lowering is unexecuted again"
    fi
    if grep -q 'continue-on-error' <<<"$leg"; then
      bad "freebsd: the leg is continue-on-error, so it cannot fail the workflow and measures nothing"
    else
      ok "freebsd: and the leg is blocking, so a failure there is a failure"
    fi
  fi
  # The runner reaches the three by a GLOB, which is why no fixture has
  # to be named in it. Asserting the glob is asserting that a fixture
  # added to `tests/stdlib/` is run on freebsd by construction.
  if grep -q 'for case_file in tests/stdlib/\*\.ax' "$runner"; then
    ok "freebsd: the runner's loop is the tests/stdlib/*.ax glob, so 470, 471 and 476 are in it by construction"
  else
    bad "freebsd: run-stdlib-tests.sh no longer loops over tests/stdlib/*.ax - which cases the leg runs is now a list somebody maintains"
  fi
fi

# --------------------------------------------------------------------
echo
echo "== 8. a binding that ALLOCATES: one arena per thread, executed =="
# --------------------------------------------------------------------
# THE PROPERTY THE THREAD LOWERING EXISTS FOR, AND NOTHING RAN IT.
# `cgMutGlobal` moves the eight runtime globals to
# `thread_local(localexec)` so that each thread's first `axiom_alloc`
# maps a chunk of its own - MM-PAR-6, "one arena per thread, with no
# code written for it". Until 2026-09-04 every executed `parallel`
# binding in the tree was ARITHMETIC: `470-parallel`'s seven terms
# capture and answer words, and `471-parallel-trap`'s binding traps. So
# `check-thread-local.sh` inspected the storage class and this gate
# inspected the module, and no test in the repository ever called
# `axiom_alloc` from a second thread.
#
# This arm does. Three bindings each push 20,000 words into a `Vec` of
# their own and sum it back, and a fourth concatenates a 16 KB `String`
# eight bytes at a time - so all four are in the allocator at once,
# through both the slab path and the large-block path - and the answers
# must be the process lowering's, byte for byte, out of a lowering
# where the four share one address space.
#
# WHY THERE IS NO ABLATION HERE, stated because every other section has
# one. The ablation exists and was run: `cgMutGlobal` forced to
# `"internal global"` for both branches, a compiler rebuilt from it,
# this probe built `--threads` against it - and it answered correctly
# in 4 runs of 5, dying with SIGSEGV in the fifth (2026-09-04,
# darwin-aarch64, unloaded). That is a RACE, and a gate whose negative
# probe fires one time in five is a gate that reports a false green
# four times in five. The measurement belongs in this comment; the
# assertion does not. What makes this arm able to fail is the same
# thing that makes arm 1 able to fail: two lowerings compared byte for
# byte against a recorded answer, where the thread half is the one
# doing something the process half cannot.
cat > "$work/arena.ax" <<'ARENA'
(import IO)

(import Str)

(import Vec)

(:: build (-> Int Int))

(fn (build n)
  (let (
    (v vecNew)
    (mut i 0)
    (mut acc 0)
  )
    {
      (while (< i n)
        {
          (vecPush v (% (* i 7) 1000))
          (set i (+ i 1))
        })
      (set i 0)
      (while (< i (vecLen v))
        {
          (set acc (+ acc (vecGet v i)))
          (set i (+ i 1))
        })
      acc
    }
  )
)

(:: strwork (-> Int Int))

(fn (strwork n)
  (let (
    (mut i 0)
    (mut s "")
  )
    {
      (while (< i n)
        {
          (set s (strConcat s "abcdefgh"))
          (set i (+ i 1))
        })
      (strLen s)
    }
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (parallel p ((a (build 20000)) (b (build 20000)) (c (build 20000)) (d (strwork 2000)))
      (println a)
      (println b)
      (println c)
      (println d))
    (println (build 100))
    0
  }
)
ARENA
run_case "$work/arena.ax" ""          parena || true
run_case "$work/arena.ax" "--threads" tarena || true
# The recorded answer: three sums of 20,000 pushes, one 16 KB string's
# length, and the parent allocating again AFTER the join - which is the
# tripwire for a child that allocated in the parent's arena.
want_arena=$'9990000\n9990000\n9990000\n16000\n34650'
if [[ -f "$work/parena.status" && -f "$work/tarena.status" ]]; then
  if [[ "$(cat "$work/parena.out")" == "$want_arena" && "$(cat "$work/parena.status")" == 0 ]]; then
    ok "arena: the process lowering allocates in four bindings and answers the recorded five lines"
  else
    bad "arena: processes answered [$(tr '\n' ' ' < "$work/parena.out")] exit $(cat "$work/parena.status")"
  fi
  if [[ "$(cat "$work/tarena.out")" == "$want_arena" && "$(cat "$work/tarena.status")" == 0 ]]; then
    ok "arena: and the THREAD lowering answers the same five lines - four concurrent allocators, one arena each"
  else
    bad "arena: threads answered [$(tr '\n' ' ' < "$work/tarena.out")] exit $(cat "$work/tarena.status"), wanted the process lowering's bytes"
    diff "$work/parena.out" "$work/tarena.out" | head -10 | sed 's/^/     /'
  fi
fi

# --------------------------------------------------------------------
echo
echo "== 9. TWO bindings that trap: what the two lowerings do NOT share =="
# --------------------------------------------------------------------
# THE LIMIT OF "ONE SURFACE, TWO LOWERINGS", MEASURED. Arm 1 compares
# the two lowerings on a fixture with ONE trapping binding and they
# agree. With TWO they do not, and this section is where that is
# written down rather than discovered.
#
# The probe runs two bindings that both trap with DIFFERENT statuses -
# one slow, ending in `vecGet` out of range (77), one immediate,
# ending in a division by zero (72) - and takes an argument that swaps
# which is written first.
#
#   processes   the status is the FIRST-WRITTEN binding's, always. The
#               joins run in argument order, the first join re-raises
#               its child's status, and nothing after it runs.
#               Measured 10 runs per order, 2026-09-04: 77 ten times
#               with the index binding first, 72 ten times with the
#               division first.
#   threads     the status is whichever thread traps FIRST, because a
#               trap under threads is `exit_group` from that thread and
#               there is no join to reach. Same binary, same machine,
#               same order: 72 in 6 of 10 runs and 77 in 4 with the
#               index binding written first, 72 in 9 of 10 with the
#               division first. The two backtraces interleave on fd 2
#               as well, mid-line.
#
# NOT BUILT, AND THE MEASUREMENT IS WHY. Making the thread lowering
# agree means a trapping thread must NOT end the process: it would have
# to record its status in the handle page and `pthread_exit`, leaving
# the join to re-raise it - which changes the meaning of a trap in a
# thread nobody joins (the program would carry on), entangles the
# recovery point (`@__axiom_recover_top` is thread-local, the abort is
# not), and needs the trap's own write serialised. That is a redesign
# of the trap path for a divergence that appears only when two bindings
# fail at once, under a lowering that is opt-in, in a program that is
# already ending. The default lowering is the deterministic one, and
# `docs/reference.md` now says so.
#
# SO THIS ARM ASSERTS THE DETERMINISTIC HALF AND ONLY THE MEMBERSHIP OF
# THE OTHER. Nothing here depends on scheduling: the process arms are
# deterministic, and the thread arm requires the status to be one of
# the two bindings' traps - which rules out 0 (a join that swallowed
# it), 78 (a spawn that failed) and 139 (a crash) without predicting
# which thread won. That is why this gate stays in `run-gates.sh`'s
# PARALLEL set: it has no arm whose verdict moves with load.
cat > "$work/traps.ax" <<'TRAPS'
(import IO)

(import Str)

(import Vec)

(import Sys)

(:: slowZero (-> Int Int))

(fn (slowZero n)
  (let (
    (mut i 0)
    (mut acc 0)
  )
    {
      (while (< i n)
        {
          (set acc (+ acc (% i 7)))
          (set i (+ i 1))
        })
      (% acc 1)
    }
  )
)

(:: slowIndex (-> Int Int))

(fn (slowIndex n)
  (let ((v vecNew))
    {
      (vecPush v 1)
      (vecGet v (+ 5 (slowZero n)))
    }
  )
)

(:: fastDiv (-> Int Int))

(fn (fastDiv z) (/ 10 z))

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let (
    (zero 0)
    (order (match (strParseInt (sysArg 1)) ((Some n) n) (None 0)))
  )
    {
      (println "before")
      (if (== order 0)
        (parallel p ((a (slowIndex 40000000)) (b (fastDiv zero)))
          (println (+ a b)))
        (parallel q ((a (fastDiv zero)) (b (slowIndex 40000000)))
          (println (+ a b))))
      (println "UNREACHABLE")
      0
    }
  )
)
TRAPS
if "$axc" build --input "$work/traps.ax" --output "$work/traps-p.bin" > "$work/traps.build" 2>&1 \
   && "$axc" --threads build --input "$work/traps.ax" --output "$work/traps-t.bin" >> "$work/traps.build" 2>&1; then
  # processes, both orders, five runs each: one status, and it is the
  # first-written binding's.
  for pair in "0 77" "1 72"; do
    set -- $pair; order="$1"; want="$2"
    got=""
    for _ in 1 2 3 4 5; do
      ( cd "$work" && ./traps-p.bin "$order" > /dev/null 2>/dev/null ); got="$got $?"
    done
    uniq_got="$(printf '%s\n' $got | LC_ALL=C sort -u | tr '\n' ' ')"
    if [[ "${uniq_got// /}" == "$want" ]]; then
      ok "traps/processes: order $order exits $want five times out of five - the status is the binding written first"
    else
      bad "traps/processes: order $order gave [${got# }], wanted $want every time"
    fi
  done
  # threads: a trap status, not a swallowed one, and NOT pinned.
  for order in 0 1; do
    got=""
    for _ in 1 2 3 4 5; do
      ( cd "$work" && ./traps-t.bin "$order" > /dev/null 2>/dev/null ); got="$got $?"
    done
    stray="$(printf '%s\n' $got | grep -vE '^(72|77)$' | tr '\n' ' ' || true)"
    if [[ -z "${stray// /}" ]]; then
      ok "traps/threads: order $order exits [${got# }] - one of the two bindings' traps every time, and which one is the race this arm does not predict"
    else
      bad "traps/threads: order $order produced [${got# }]; a status outside {72,77} means the trap was swallowed or the program crashed"
    fi
  done
else
  bad "traps: the probe would not build"; sed 's/^/     /' "$work/traps.build" | head -5
fi

# --------------------------------------------------------------------
echo
echo "== 10. a trap inside a THREAD: the walk stops at the thread's entry =="
# --------------------------------------------------------------------
# `@__axiom_backtrace` walks the frame chain and stops at `main`,
# because above `main` are the C runtime's frames and this module's
# symbol table cannot name them - it would answer with whichever of OUR
# functions happens to precede a libc address, which `emitBtName`'s
# header calls the one output a backtrace must never produce.
#
# A PTHREAD STACK HAS NO `main` ON IT. So the one guard that ends the
# walk could never fire for a trap inside a `parallel` binding built
# `--threads`, and the walk ran off the top into libSystem. Measured on
# `471-parallel-trap.ax`, 2026-09-04, before the fix:
#
#     at __axiom_index_out_of_range
#     at _lam_0
#     at __axiom_par_entry
#     at __axiom_out_of_memory      <- libSystem, named as ours
#     at __axiom_out_of_memory      <- libSystem, named as ours
#
# `emitBtWalk` now stops at `@__axiom_par_entry` as well, emitted only
# under `cgThreads` because that is the only module the symbol exists
# in. The frames it removes were never on the stack.
#
# WHAT THIS ARM DOES NOT CLAIM. The process lowering's trace can end in
# the same stray name, and it is NOT concurrency's: the walk loses
# `main` whenever the optimiser elides `main`'s frame, which reproduces
# with no `parallel` in the program at all (a two-line `vecGet` out of
# range printed `at __axiom_user_main / at __axiom_out_of_memory` on
# this compiler, 2026-09-04). That is `emitBtName`'s "an address
# outside this module resolves to whichever of ours precedes it", it
# needs function EXTENTS in the symbol table to fix, and it is its own
# workstream.
if "$axc" --threads build --input "$fx471" --output "$work/bt471.bin" > "$work/bt471.build" 2>&1; then
  ( cd "$work" && ./bt471.bin > /dev/null 2> "$work/bt471.err" ) || true
  last="$(grep '^  at ' "$work/bt471.err" | tail -1 | sed 's/^  at //')"
  nframes="$(grep -c '^  at ' "$work/bt471.err" || true)"
  if [[ "$last" == "__axiom_par_entry" ]]; then
    ok "threads: the trap's backtrace is $nframes frames and ends at __axiom_par_entry, with nothing above it"
  else
    bad "threads: the backtrace's last frame is '$last', not __axiom_par_entry - the walk is running past the thread's entry again"
    sed 's/^/     /' "$work/bt471.err" | head -10
  fi
else
  bad "10: 471 would not build under --threads"; sed 's/^/     /' "$work/bt471.build" | head -5
fi

# --- 10b. the ablation: delete the stop and the frames come back ---
#
# A COMPILER, because no program can select this: the stop is a line of
# `emitBtWalk`'s emitted IR. The copy is of the WORKING TREE, the way
# `check-thread-local.sh`'s assertion 6 makes its general-dynamic
# compiler, so an uncommitted change to the walker is ablated too. The
# edit ASSERTS THAT IT LANDED before the result is believed: a `sed`
# that matched nothing produces a green "the ablation failed to fail"
# that reads exactly like a passing gate.
#
# Deterministic, unlike section 8's: removing the stop always adds the
# frames the walk was already reaching, so this costs one compiler
# build (~40s here) and buys the arm above the ability to fail.
abl_bt="$work/abl-bt"
rm -rf "$abl_bt"; mkdir -p "$abl_bt"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl_bt/"
if python3 - "$abl_bt/self_host/codegen.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '(emitLine cg "  %inside = and i1 %ismain0, %isentry0")'
new = '(emitLine cg "  %inside = and i1 %ismain0, %ismain0")'
if s.count(old) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
then
  if (cd "$abl_bt" && "$axiom" build --input self_host/main.ax --output "$work/axc-nostop") \
       > "$work/abl-bt.build" 2>&1; then
    AXIOM_STDLIB="$abl_bt/stdlib" "$work/axc-nostop" --threads build --input "$fx471" \
      --output "$work/bt471-nostop.bin" > "$work/abl-bt.build2" 2>&1
    ( cd "$work" && ./bt471-nostop.bin > /dev/null 2> "$work/bt471-nostop.err" ) || true
    abl_last="$(grep '^  at ' "$work/bt471-nostop.err" | tail -1 | sed 's/^  at //')"
    abl_n="$(grep -c '^  at ' "$work/bt471-nostop.err" || true)"
    if [[ "$abl_last" == "__axiom_par_entry" ]]; then
      bad "ablation bt: the walk still stops at the thread entry with the stop deleted - arm 10 cannot fail"
    else
      ok "ablation bt: without the stop the walk reaches $abl_n frames and ends at '$abl_last', so arm 10 is measuring the stop"
    fi
  else
    bad "ablation bt: the compiler with the stop deleted would not build"
    sed 's/^/     /' "$work/abl-bt.build" | head -10
  fi
else
  bad "ablation bt: the edit did not land - emitBtWalk's thread-entry stop was never broken, so the arm proved nothing"
fi

echo
if (( failed > 0 )); then
  echo "check-parallel: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-parallel: $checks checks - one surface, two lowerings, the same bytes;"
echo "                processes import nothing and threads import their pthread;"
echo "                seven globals move under threads and none without a spawn;"
echo "                a child's trap is the program's, and the targets that cannot"
echo "                say so at build time or at the first spawn; the pool over"
echo "                those primitives answers Job's golden, imports nothing, bounds"
echo "                its width, and emits the same module with the flag and without;"
echo "                freebsd's leg still executes the fixtures, four concurrent"
echo "                allocators answer as four processes do, two failing bindings"
echo "                are deterministic under processes and are not under threads,"
echo "                and a thread's backtrace stops where its stack does"
