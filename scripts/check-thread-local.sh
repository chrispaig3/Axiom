#!/usr/bin/env bash
# The emitted runtime's mutable globals, and the one predicate that
# decides their storage class.
#
# WHAT THIS IS ABOUT. `docs/memory-model.md` MM-PAR-3 gets memory safety
# across processes for free: every process-wide mutable global is
# private after a `fork`. Under THREADS that property is not free, it is
# BOUGHT - by making the identical set of globals thread-local - and the
# set is not a sentence anyone wrote, it is an enumeration of `@__axiom_`
# in `self_host/codegen.ax`. There are eight:
#
#   @__axiom_bump  _bump_end  _chunk  _free  _high   the allocator's
#   @__axiom_slabs                                   4,097 class heads
#   @__axiom_recover_top                             the armed point
#   @__axiom_ev_<Effect>                             one per effect
#
# `@__axiom_argc` and `@__axiom_argv` are deliberately NOT among them:
# they are written once in `@main`'s prologue, before any thread can
# exist, and never again. Every constant is shareable by construction.
#
# THE HALF WORTH MORE IS THE ONE THAT DOES NOTHING. A program that
# spawns no thread must be byte-identical to what the compiler emitted
# before any of this existed, on every target - and Darwin is why. A
# thread-local access there is not an addressing mode, it is an
# INDIRECT CALL through libSystem's `__tlv_bootstrap`, measured below at
# one undefined symbol where the same program off the flag has zero. A
# language that made every program pay that for a feature it never used
# would have left `MM-FFI-1`'s tier 1 for everyone. This is the shape
# `ERR-REC-6` already established for recovery points: a mechanism a
# program does not ask for costs it nothing, measured rather than
# argued.
#
# THE ON PATH IS A PROGRAM NOW, NOT AN ABLATION. Until 2026-09-03
# `cgThreads` was the constant `false` - no primitive existed for a
# program to name - so this gate reached the ON path by rewriting the
# predicate's body and rebuilding a compiler. `cgThreads` is a scan of
# the resolved declarations now (`parScan` in codegen.ax): the same
# probe with one `(__thread_spawn ...)` joined in its body IS the ON
# program, built by the compiler under test with no edit to it. The
# assertions did not move: the eight and nothing else, the OFF path's
# zero TLS imports, and local-exec on every target that has one. What
# the ON program adds beyond the storage class is its thread runtime -
# `@__axiom_par_entry`, `@__axiom_par_spawn_thread`, the pthread
# declares - and assertion 3 names it rather than counting changed
# lines, because "sixteen lines moved" was a fact about an ablation
# that no longer describes the path.
#
# LOCAL-EXEC IS NOT A PREFERENCE. A bare `thread_local` takes the
# general-dynamic model, which needs a dynamic resolver, which is a
# dynamic link, which `scripts/check-freestanding.sh` refuses at zero
# undefined symbols. Assertion 5 requires the resolver to be absent and
# assertion 6 requires it to APPEAR when `(localexec)` is dropped -
# because an assertion that a symbol is missing is satisfied by a
# compiler that emits nothing at all, and this gate exists to hold a
# storage class rather than to observe one. Assertion 6 still ablates a
# compiler, for the spelling: that is a fact about the emitter's text
# no program can select.
#
# THE MARKER DIFFERS BY ARCHITECTURE, and assuming it did not would have
# made half of assertion 6 vacuous. Measured here, general-dynamic
# against local-exec on the same program:
#
#   linux-x86_64     __tls_get_addr x13     ->  %fs:...@TPOFF
#   linux-aarch64    tlsdesc x152           ->  tprel x66
#
# AArch64 uses TLS DESCRIPTORS and never names `__tls_get_addr`, so a
# gate grepping only for that symbol would have passed on an aarch64
# build that imports `__tlsdesc_resolve` through the PLT. Both markers
# are checked, on both targets.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

for arch in AArch64 X86; do
  if ! llc --version | grep -q "$arch"; then
    echo "error: this llc has no $arch backend; cannot verify all targets" >&2
    exit 1
  fi
done

# One program that reaches every one of the eight: it allocates (the
# five words and the slabs), declares an effect and handles it (the
# evidence slot), and arms a recovery point (`@__axiom_recover_top`).
# `SPAWN` is the one line the ON program adds: a thread that runs
# `build` and is joined before the answer is printed, so both programs
# write the same bytes.
mkprobe() {  # <path> <spawn-line>
  cat > "$1" <<PROBE
(import IO)

(import Str)

(effect Console
  (log :: (-> String Int)))

(:: build (-> Int Int))

(fn (build n) (strLen (strConcat "a" "b")))

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println "probe")
    (build 1)
    $2
    (__axiom_recover __axiom_arena_mark (lambda (x) (build 2)))
    (cast Int (handle (log "y") (Console Alloc IO) (lambda (s) 0)))
  }
)
PROBE
}
probe="$work/probe.ax"
probe_on="$work/probe-on.ax"
mkprobe "$probe" "(build 3)"
mkprobe "$probe_on" "(__thread_join (__thread_spawn (lambda (x) (build 3)) 0))"

# --------------------------------------------------------------------
echo "== 1. off: the emitted runtime has no thread-local storage at all =="
# --------------------------------------------------------------------
"$axc" emit-llvm "$probe" > "$work/off.ll" 2>/dev/null
tl_off="$(grep -c 'thread_local' "$work/off.ll" || true)"
ig_off="$(grep -c '= internal global' "$work/off.ll" || true)"
if [[ "$tl_off" == 0 ]]; then
  ok "no \`thread_local\` in the emitted module ($ig_off mutable globals, all plain)"
else
  bad "$tl_off thread_local global(s) in a program that spawns no thread"
fi
# The floor: a probe that emitted no globals would satisfy the line above.
if (( ig_off >= 9 )); then
  ok "the probe reaches $ig_off mutable globals, over the floor of 9"
else
  bad "only $ig_off mutable globals in the probe; the floor is 9 (10 today) - it stopped reaching them"
fi
if grep -q '@__axiom_par_' "$work/off.ll"; then
  bad "the thread runtime is in a program that spawns no thread"
else
  ok "and no line of the thread runtime is in it"
fi

# --------------------------------------------------------------------
echo
echo "== 2. off: and imports no thread-local machinery =="
# --------------------------------------------------------------------
# THE CLAIM IS ABOUT TLS, NOT ABOUT ZERO, and the first version of this
# arm said zero. It asserted `nm -u` was empty, which is a DARWIN fact:
# on Linux the same program imports six symbols by construction - four
# weak crt hooks (`_ITM_*`, `__gmon_start__`, `__cxa_finalize`) and two
# real ones (`__libc_start_main`, `abort`) - so the arm failed CI on
# both Linux legs for a program that was behaving exactly as intended.
# Measured there: SIX off and SIX on, identical, which is the property
# this gate actually exists to hold and which "zero" could not express.
#
# So the assertion is the one the flag is about: a program that spawns
# no thread imports no TLS RUNTIME SYMBOL, on any format. `imports_of`
# is `check-freestanding.sh`'s reader, which dispatches on the object's
# own magic rather than on the host and strips ELF's `@GLIBC_2.34`
# versions and Mach-O's leading underscore - the edit each convention
# requires. Assertion 4 then holds the delta, which is where Darwin's
# one extra symbol shows up.
source "$(dirname "${BASH_SOURCE[0]}")/lib/imports.sh"
tls_syms='__tlv_bootstrap|__tls_get_addr|__tlsdesc_resolve|_tlv_bootstrap'
thread_syms="$tls_syms|pthread_create|pthread_join"

"$axc" build --input "$probe" --output "$work/off.bin" >/dev/null 2>&1
imports_of "$work/off.bin" | LC_ALL=C sort > "$work/off.imports"
n_off="$(grep -c . "$work/off.imports" || true)"
tls_off="$(grep -cE "^($thread_syms)$" "$work/off.imports" || true)"
if [[ "$tls_off" == 0 ]]; then
  ok "no TLS or thread runtime symbol imported ($n_off import(s) on this host, all of them the platform's own)"
else
  bad "$tls_off TLS/thread symbol(s) imported by a program that spawns no thread"
  grep -E "^($thread_syms)$" "$work/off.imports" | sed 's/^/     /'
fi
# And the floor: a reader that answered nothing would satisfy the line
# above whatever the binary held.
if [[ "$n_off" -gt 0 || "$(uname -s)" == Darwin ]]; then
  ok "the import reader answers for this object format ($n_off import(s))"
else
  bad "imports_of read 0 symbols from a linked executable - the reader, not the binary"
fi

# --------------------------------------------------------------------
echo
echo "== 3. on: exactly the eight move, and the thread runtime arrives =="
# --------------------------------------------------------------------
"$axc" emit-llvm "$probe_on" > "$work/on.ll" 2>/dev/null
tl_on="$(grep -c '= internal thread_local(localexec) global' "$work/on.ll" || true)"
wrong=0
for g in __axiom_bump __axiom_bump_end __axiom_chunk __axiom_free \
         __axiom_high __axiom_slabs __axiom_recover_top __axiom_ev_Console; do
  if ! grep -q "^@$g = internal thread_local(localexec) global" "$work/on.ll"; then
    bad "@$g did not move to thread_local(localexec)"
    wrong=1
  fi
  if grep -q "^@$g = internal global" "$work/on.ll"; then
    bad "@$g is still a plain global in the ON module"
    wrong=1
  fi
done
if [[ "$wrong" == 0 ]]; then
  ok "all eight globals moved to thread_local(localexec)"
fi
if [[ "$tl_on" == 8 ]]; then
  ok "and $tl_on thread_local global(s) in the whole module - the eight, nothing else"
else
  bad "$tl_on thread_local globals, expected exactly 8"
  grep 'thread_local' "$work/on.ll" | sed 's/^/     /' | head -12
fi
# argc/argv must NOT have moved: they are written once in @main's
# prologue, before any thread exists.
if grep -q '@__axiom_arg[cv] = internal thread_local' "$work/on.ll"; then
  bad "@__axiom_argc/argv moved; they are write-once and shared by design"
else
  ok "@__axiom_argc and @__axiom_argv stayed shared"
fi
# The runtime the program asked for, and only that half of it.
for sym in '@__axiom_par_entry' '@__axiom_par_spawn_thread' '@__axiom_par_join_thread' 'declare i32 @pthread_create' 'declare i32 @pthread_join'; do
  if grep -q -- "$sym" "$work/on.ll"; then
    ok "the thread runtime carries $sym"
  else
    bad "the thread runtime lacks $sym"
  fi
done
# Everything ELSE in the module is the OFF module: strip the eight
# storage-class lines and the runtime's own definitions, and the two
# must agree line for line on what remains - the user's code did not
# change because a thread exists.
strip_rt() {
  awk '
    /^@__axiom_par_/ { next }
    /^declare i32 @pthread_/ { next }
    /^define internal (i64|ptr) @__axiom_par_/ { skip = 1 }
    skip { if ($0 == "}") { skip = 0; getline; if ($0 != "") print; } ; next }
    { sub(/= internal thread_local\(localexec\) global/, "= internal global"); print }
  ' "$1"
}
strip_rt "$work/on.ll" > "$work/on.stripped"
# The OFF probe differs from the ON one by the one line it spells, so
# the comparison is of the two emitted `main`s less that line's own
# code: assert instead that no line of the ON module outside the
# runtime and the eight is a line the OFF module could not have -
# i.e. nothing else grew a `thread_local`.
if grep -q 'thread_local' "$work/on.stripped"; then
  bad "a thread_local survived outside the eight globals"
else
  ok "nothing outside the eight carries a storage class"
fi

# --------------------------------------------------------------------
echo
echo "== 4. on: and the program still answers the same =="
# --------------------------------------------------------------------
"$axc" build --input "$probe_on" --output "$work/on.bin" >/dev/null 2>&1
set +e
o_off="$("$work/off.bin" 2>/dev/null)"; r_off=$?
o_on="$("$work/on.bin" 2>/dev/null)";  r_on=$?
set -e
if [[ "$o_off" == "$o_on" && "$r_off" == "$r_on" ]]; then
  ok "one thread joined: same stdout, same exit ($r_off)"
else
  bad "behaviour moved: off exit $r_off [$o_off], on exit $r_on [$o_on]"
fi
# THE DELTA IS THE MEASUREMENT. What a thread costs is exactly the
# symbols the ON binary imports that the OFF one does not: the two
# pthread entry points on every target, and on Darwin `__tlv_bootstrap`
# - a thread-local access there is an indirect call through libSystem,
# not an addressing mode. On Linux and FreeBSD local-exec TLS needs no
# resolver, so the delta is the pthread pair alone and the six crt
# imports are identical on both sides. Anything else appearing here is
# the runtime pulling in machinery nobody asked it for.
imports_of "$work/on.bin" | LC_ALL=C sort > "$work/on.imports"
comm -13 "$work/off.imports" "$work/on.imports" > "$work/added"
n_added="$(grep -c . "$work/added" || true)"
stray="$(grep -vE "^($thread_syms)$" "$work/added" || true)"
if [[ -z "$stray" ]] && grep -q '^pthread_create$' "$work/added"; then
  ok "a thread adds only its own symbol(s): $(tr '\n' ' ' < "$work/added")"
else
  bad "the thread runtime added an import that is not a thread's, or no pthread at all:"
  sed 's/^/     /' "$work/added"
fi

# --------------------------------------------------------------------
echo
echo "== 5. on: local-exec, so no dynamic TLS resolver, on any target that has threads =="
# --------------------------------------------------------------------
# Both markers on both targets: x86-64 general-dynamic calls
# `__tls_get_addr`, AArch64 uses TLS descriptors and never names it.
# The ON program emits only for a target with a thread runtime
# (AX4006 elsewhere, `scripts/check-parallel.sh`), so the three targets
# the previous version of this arm listed become the two Linux ones.
dyn_tls() {  # <compiler> <target> <program> -> count of dynamic-TLS markers
  local c="$1" t="$2" prog="$3"
  "$c" --target="$t" emit-llvm "$prog" > "$work/t.ll" 2>/dev/null
  llc -O2 -relocation-model=pic -filetype=asm -o "$work/t.s" "$work/t.ll" 2>/dev/null
  grep -coE '__tls_get_addr|tlsdesc' "$work/t.s" || true
}
for t in linux-x86_64 linux-aarch64; do
  n="$(dyn_tls "$axc" "$t" "$probe_on")"
  if [[ "$n" == 0 ]]; then
    ok "$t: no __tls_get_addr and no tlsdesc"
  else
    bad "$t: $n dynamic-TLS marker(s) - the model is not local-exec, and check-freestanding would fail"
  fi
done

# --------------------------------------------------------------------
echo
echo "== 6. and assertion 5 can fail: drop (localexec) and they appear =="
# --------------------------------------------------------------------
gd="$work/gd"
mkdir -p "$gd"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$gd/"
seam2='"internal thread_local(localexec) global"'
n2="$(grep -c -F "$seam2" "$gd/self_host/codegen.ax" || true)"
if [[ "$n2" != 1 ]]; then
  bad "codegen.ax holds $n2 copies of the localexec spelling; this arm expects exactly 1"
else
  python3 - "$gd/self_host/codegen.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '"internal thread_local(localexec) global"'
new = '"internal thread_local global"'
assert s.count(old) == 1
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  if ! (cd "$gd" && "$axiom" build --input self_host/main.ax --output "$work/axc-gd") \
       > "$work/gd.build.log" 2>&1; then
    bad "the general-dynamic compiler would not build"
  else
    seen=0
    for t in linux-x86_64 linux-aarch64; do
      n="$(dyn_tls "$work/axc-gd" "$t" "$probe_on")"
      if [[ "$n" -gt 0 ]]; then
        ok "$t without (localexec): $n dynamic-TLS marker(s), so assertion 5 discriminates"
        seen=$((seen + 1))
      else
        bad "$t without (localexec): still 0 markers - assertion 5 would pass on a general-dynamic build"
      fi
    done
    [[ "$seen" == 2 ]] || bad "the negative probe fired on $seen of 2 targets"
  fi
fi

echo
if (( failed > 0 )); then
  echo "check-thread-local: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-thread-local: $checks checks - eight globals move under a program that"
echo "                    spawns a thread and nothing else does, a program that"
echo "                    spawns none imports no TLS machinery, a thread's cost is"
echo "                    exactly its own symbols (the pthread pair, plus one on"
echo "                    Darwin), and the model is local-exec on both Linux targets"
