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
#      the program links and dies at its first spawn saying why (79);
#   5. the negative half of 1: the trap fixture's 77 is the CHILD's
#      status re-raised, not the parent's own - a join that swallowed
#      the child's status would answer 0, and this arm asserts the
#      fixture's `.exit` is what the process lowering produces AND what
#      the thread lowering produces, against a control that exits 0.
#
# WHAT THIS GATE DOES NOT CLAIM. The thread lowering does not yet check
# what a binding captures: a heap value shared with the parent is
# touched from two threads with no fence, which the process lowering
# cannot suffer and the static rule that refuses it (MM-RGN-3 over
# sibling regions) is S3's. Both fixtures capture only words, on
# purpose, and `emitPrimPar`'s header in codegen.ax states the gap.
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

echo
if (( failed > 0 )); then
  echo "check-parallel: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-parallel: $checks checks - one surface, two lowerings, the same bytes;"
echo "                processes import nothing and threads import their pthread;"
echo "                seven globals move under threads and none without a spawn;"
echo "                a child's trap is the program's, and the targets that cannot"
echo "                say so at build time or at the first spawn"
