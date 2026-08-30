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
# LOCAL-EXEC IS NOT A PREFERENCE. A bare `thread_local` takes the
# general-dynamic model, which needs a dynamic resolver, which is a
# dynamic link, which `scripts/check-freestanding.sh` refuses at zero
# undefined symbols. Assertion 5 requires the resolver to be absent and
# assertion 6 requires it to APPEAR when `(localexec)` is dropped -
# because an assertion that a symbol is missing is satisfied by a
# compiler that emits nothing at all, and this gate exists to hold a
# storage class rather than to observe one.
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
probe="$work/probe.ax"
cat > "$probe" <<'PROBE'
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
    (__axiom_recover __axiom_arena_mark (lambda (x) (build 2)))
    (cast Int (handle (log "y") (Console Alloc IO) (lambda (s) 0)))
  }
)
PROBE

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

# --------------------------------------------------------------------
echo
echo "== 2. off: and links nothing =="
# --------------------------------------------------------------------
"$axc" build --input "$probe" --output "$work/off.bin" >/dev/null 2>&1
u_off="$(nm -u "$work/off.bin" 2>/dev/null | grep -c . || true)"
if [[ "$u_off" == 0 ]]; then
  ok "0 undefined symbols - MM-FFI-1 tier 1, unchanged"
else
  bad "$u_off undefined symbol(s) in a program that spawns no thread"
  nm -u "$work/off.bin" 2>/dev/null | head -5 | sed 's/^/     /'
fi

# --------------------------------------------------------------------
echo
echo "== 3. on: exactly the eight move, and nothing else =="
# --------------------------------------------------------------------
# `cgThreads` is not a command-line flag, deliberately - whether a
# program spawns a thread is a fact about the program, and a switch
# would let a spawning one be emitted with shared allocator words.  So
# the ON path is reached by ablation, anchored on the flag's own body.
abl="$work/on"
mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/"
seam='(pub fn (cgThreads) false)'
n_seam="$(grep -c -F -x "$seam" "$abl/self_host/codegen.ax" || true)"
if [[ "$n_seam" != 1 ]]; then
  bad "codegen.ax holds $n_seam copies of the cgThreads seam; this gate expects exactly 1"
else
  python3 - "$abl/self_host/codegen.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old, new = "(pub fn (cgThreads) false)", "(pub fn (cgThreads) true)"
assert s.count(old) == 1
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  if ! (cd "$abl" && "$axiom" build --input self_host/main.ax --output "$work/axc-on") \
       > "$work/on.build.log" 2>&1; then
    bad "the thread-on compiler would not build"
    sed 's/^/     /' "$work/on.build.log" | head -10
  else
    "$work/axc-on" emit-llvm "$probe" > "$work/on.ll" 2>/dev/null

    # Every changed line, both sides, and what it must be.
    diff "$work/off.ll" "$work/on.ll" | grep '^[<>]' > "$work/moved" || true
    moved="$(grep -c . "$work/moved" || true)"
    # Each of the eight appears once as `<` and once as `>`.
    wrong=0
    for g in __axiom_bump __axiom_bump_end __axiom_chunk __axiom_free \
             __axiom_high __axiom_slabs __axiom_recover_top __axiom_ev_Console; do
      a="$(grep -c "^< @$g = internal global\|^< @$g = internal thread_local" "$work/moved" || true)"
      b="$(grep -c "^> @$g = internal thread_local(localexec) global" "$work/moved" || true)"
      if [[ "$a" != 1 || "$b" != 1 ]]; then
        bad "@$g did not move exactly once (off:$a on:$b)"
        wrong=1
      fi
    done
    if [[ "$wrong" == 0 ]]; then
      ok "all eight globals moved to thread_local(localexec)"
    fi
    if [[ "$moved" == 16 ]]; then
      ok "and $moved changed line(s) in the whole module - eight globals, nothing else"
    else
      bad "$moved changed lines, expected 16 (eight globals, one line each side)"
      sed 's/^/     /' "$work/moved" | head -20
    fi
    # argc/argv must NOT have moved: they are written once in @main's
    # prologue, before any thread exists.
    if grep -q '@__axiom_arg' "$work/moved"; then
      bad "@__axiom_argc/argv moved; they are write-once and shared by design"
    else
      ok "@__axiom_argc and @__axiom_argv stayed shared"
    fi

    # ----------------------------------------------------------------
    echo
    echo "== 4. on: and the program still answers the same =="
    # ----------------------------------------------------------------
    "$work/axc-on" build --input "$probe" --output "$work/on.bin" >/dev/null 2>&1
    set +e
    o_off="$("$work/off.bin" 2>/dev/null)"; r_off=$?
    o_on="$("$work/on.bin" 2>/dev/null)";  r_on=$?
    set -e
    if [[ "$o_off" == "$o_on" && "$r_off" == "$r_on" ]]; then
      ok "one thread: same stdout, same exit ($r_off)"
    else
      bad "behaviour moved: off exit $r_off [$o_off], on exit $r_on [$o_on]"
    fi
    u_on="$(nm -u "$work/on.bin" 2>/dev/null | grep -c . || true)"
    echo "     (this host: $u_off undefined off, $u_on on$( [[ "$u_on" != 0 ]] && printf ' - %s' "$(nm -u "$work/on.bin" 2>/dev/null | tr -d ' ' | tr '\n' ' ')" ))"

    # ----------------------------------------------------------------
    echo
    echo "== 5. on: local-exec, so no dynamic TLS resolver, on any target =="
    # ----------------------------------------------------------------
    # Both markers on both targets: x86-64 general-dynamic calls
    # `__tls_get_addr`, AArch64 uses TLS descriptors and never names it.
    dyn_tls() {  # <compiler> <target> -> count of dynamic-TLS markers
      local c="$1" t="$2"
      "$c" --target="$t" emit-llvm "$probe" > "$work/t.ll" 2>/dev/null
      llc -O2 -relocation-model=pic -filetype=asm -o "$work/t.s" "$work/t.ll" 2>/dev/null
      grep -coE '__tls_get_addr|tlsdesc' "$work/t.s" || true
    }
    for t in linux-x86_64 linux-aarch64 freebsd-x86_64; do
      n="$(dyn_tls "$work/axc-on" "$t")"
      if [[ "$n" == 0 ]]; then
        ok "$t: no __tls_get_addr and no tlsdesc"
      else
        bad "$t: $n dynamic-TLS marker(s) - the model is not local-exec, and check-freestanding would fail"
      fi
    done

    # ----------------------------------------------------------------
    echo
    echo "== 6. and assertion 5 can fail: drop (localexec) and they appear =="
    # ----------------------------------------------------------------
    gd="$work/gd"
    mkdir -p "$gd"
    cp -R "$abl/self_host" "$abl/stdlib" "$gd/"
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
          n="$(dyn_tls "$work/axc-gd" "$t")"
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
  fi
fi

echo
if (( failed > 0 )); then
  echo "check-thread-local: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-thread-local: $checks checks - eight globals move under the flag and nothing else does,"
echo "                    a program that spawns no thread is unchanged and links nothing,"
echo "                    and the model is local-exec on every target that has one"
