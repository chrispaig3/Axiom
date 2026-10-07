#!/usr/bin/env bash
# Check which runtime globals become thread-local, and that a program
# without threads pays nothing for it.
#
# MM-PAR-3 (`docs/memory-model.md`) gets private globals per process
# from `fork`. Threads need the same set made thread-local: the eight
# `@__axiom_` globals in `self_host/codegen.ax`.
#
#   @__axiom_bump  _bump_end  _chunk  _free  _high   the allocator's
#   @__axiom_slabs                                   4,097 class heads
#   @__axiom_recover_top                             the armed point
#   @__axiom_ev_<Effect>                             one per effect
#
# A threaded program also moves the child registry's two globals
# (MM-PAR-7), for ten, and one that makes resource owners and resets
# the arena moves the owner registry's three (MM-EXEC-20), for
# thirteen. `@__axiom_argc` and `@__axiom_argv` stay shared:
# `@main`'s prologue writes them once, before any thread can exist.
#
# A program that spawns no thread must emit no thread-local storage. On
# Darwin a thread-local access is an indirect call through libSystem's
# `__tlv_bootstrap`, and paying that unasked would take every program
# out of `MM-FFI-1`'s tier 1. `ERR-REC-6` sets the same rule for
# recovery points.
#
# `cgThreads` (`parScan` in codegen.ax) scans the resolved declarations,
# so the compiler under test reaches the ON path unedited: the ON probe
# is the OFF one with a joined `(__thread_spawn ...)` in its body.
#
# The TLS model must be local-exec. General-dynamic needs a dynamic
# resolver and so a dynamic link, which `scripts/check-freestanding.sh`
# refuses. Assertion 5 requires the resolver to be absent, which a
# compiler that emitted nothing would also satisfy. So assertion 6
# rebuilds the compiler without `(localexec)`, a spelling no program can
# select, and requires the resolver to appear. x86-64 marks it with
# `__tls_get_addr`, while AArch64 uses TLS descriptors (`tlsdesc`) and
# never names it, so both markers are checked on both targets.
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
# The spawn line is the only difference in the ON program: it runs
# `build` on a thread and joins it before the answer is printed, so both
# programs write the same bytes.
mkprobe() {  # <path> <spawn-line> <extra-effects>
  cat > "$1" <<PROBE
(import IO)

(import Str)

(effect Console
  (log :: (-> String Int)))

(:: build (-> Int Int))

(fn (build n) (strLen (concat "a" "b")))

(:: main Int)

;@axiom:effect(io)
$3
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
mkprobe "$probe" "(build 3)" ""
mkprobe "$probe_on" "(__thread_join (__thread_spawn (lambda (x) (build 3)) 0))" ";@axiom:effect(spawn)
;@axiom:effect(block)"

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
# The claim is about TLS and thread symbols only. On Linux this probe
# imports crt hooks (`_ITM_*`, `__gmon_start__`, `__cxa_finalize`),
# `__libc_start_main` and `abort` with or without threads, so a
# zero-import check would fail there. `imports_of` is `check-freestanding.sh`'s
# reader: it dispatches on the object's own magic, not the host, and
# strips ELF's `@GLIBC_2.34` versions and Mach-O's leading underscore.
# Assertion 4 checks the delta, where Darwin's extra symbol shows up.
source "$(dirname "${BASH_SOURCE[0]}")/lib/imports.sh"
tls_syms='__tlv_bootstrap|__tls_get_addr|__tlsdesc_resolve|_tlv_bootstrap'
# `fork` too, on Darwin: a module with threads forks its process
# children through libSystem there (MM-PAR-7, `parLibcFork`).
thread_syms="$tls_syms|pthread_create|pthread_join|fork"

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
# The floor: a reader that answered nothing would satisfy the line
# above whatever the binary held. On Darwin an executable that calls no
# libc function imports nothing, so the floor applies only elsewhere.
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
         __axiom_high __axiom_slabs __axiom_recover_top __axiom_ev_Console \
         __axiom_par_live __axiom_par_seq \
         __axiom_res_head __axiom_res_seq __axiom_res_unwinding; do
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
  ok "all thirteen globals moved to thread_local(localexec)"
fi
# Thirteen: the eight, the child registry's head and sequence counter
# (MM-PAR-7), and the owner registry's head, counter and unwinding flag
# (MM-EXEC-20): the probe imports IO, which makes owners, and arms a
# recovery point. Both registries are per thread because each thread
# sweeps the children it spawned and resets its own arena. A shared list
# would have two threads linking into one unsynchronised structure.
if [[ "$tl_on" == 13 ]]; then
  ok "and $tl_on thread_local global(s) in the whole module - the eight and the registries' five, nothing else"
else
  bad "$tl_on thread_local globals, expected exactly 13"
  grep 'thread_local' "$work/on.ll" | sed 's/^/     /' | head -12
fi
# argc/argv must not move: they are written once in @main's prologue,
# before any thread exists.
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
# strip_rt drops the thread runtime's globals, declares and definitions,
# and turns each local-exec global back into a plain one.
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
# The two probes differ in their spawn line, so the modules cannot be
# compared line for line. Instead, assert that nothing outside the
# runtime and the moved globals grew a `thread_local`.
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
# What a thread costs is the imports the ON binary has and the OFF one
# lacks: the pthread pair everywhere, plus `__tlv_bootstrap` on Darwin.
# Local-exec TLS on Linux and FreeBSD needs no resolver, so there the
# delta is the pthread pair alone. Anything outside `thread_syms` is the
# runtime pulling in machinery nobody asked for.
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
# Both markers on both targets, as the header explains. The ON program
# emits only for a target with a thread runtime (AX4006 elsewhere, see
# `scripts/check-parallel.sh`), so the two Linux targets are checked.
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
  if ! gate_build_tree "$axiom" "$gd" "$AXIOM_STDLIB" "$work/axc-gd" \
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
