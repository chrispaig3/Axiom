#!/usr/bin/env bash
# Axiom's FFI boundary is a C ABI, and this gate binds a plain C
# library to prove it.
#
# `docs/ffi.md` documents the boundary as one machine word per argument
# and one word back, `extern "C" fn(i64, ...) -> i64`, and the emitter
# writes an ordinary `declare i64 @sym(i64, ...)` for every `extern`.
# `check-ffi.sh` tests it through Rust crates. This gate uses only `cc`
# and `ar`, so the ABI keeps a test if the Rust workspace changes.
#
# It asserts:
#   1. A plain C static archive binds and answers, at three arities.
#   2. A `String` crosses and C reads it through the documented header
#      (word 0 the byte length, word 1 the NUL-terminated bytes), with
#      no helper library on the C side.
#   3. The emitted module carries `; axiom-extern-lib <name>`, which is
#      how `axiom build` knows what to link.
#   4. Negative: a symbol no archive defines is refused at `AX4004`
#      rather than in the linker.
#   5. Negative: dropping `--link-search` fails, so assertion 1 can't
#      pass for a reason other than the flag.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

for tool in cc ar; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "FAIL: no $tool on PATH; this gate's whole subject is a C toolchain" >&2
    exit 1
  }
done

lib="$work/clib"
mkdir -p "$lib"

# --------------------------------------------------------------------
echo "== a plain C archive, built with cc and ar =="
# --------------------------------------------------------------------
cat > "$lib/axc_probe.c" <<'C'
/* Plain C. No Rust, no cargo, no generated shim, no Axiom header. */
long axc_add(long a, long b)       { return a + b; }
long axc_mul3(long a, long b, long c) { return a * b * c; }
long axc_fib(long n)               { long a=0,b=1,t; while(n-->0){t=a+b;a=b;b=t;} return a; }

/* An Axiom `String` is a two-word header: word 0 is the byte length and
   word 1 addresses len+1 bytes with a NUL terminator. That is the whole
   contract, and it is readable from C with no helper. */
long axc_strlen(long h)            { return ((long*)h)[0]; }
long axc_countbyte(long h, long c) {
  long n = ((long*)h)[0];
  const unsigned char* p = (const unsigned char*)((long*)h)[1];
  long k = 0;
  for (long i = 0; i < n; i++) if (p[i] == (unsigned char)c) k++;
  return k;
}
C
if cc -c -O2 -fPIC -o "$lib/axc_probe.o" "$lib/axc_probe.c" 2>"$work/cc.err" \
   && ar rcs "$lib/libaxcprobe.a" "$lib/axc_probe.o" 2>>"$work/cc.err"; then
  ok "libaxcprobe.a built by cc and ar, $(wc -c < "$lib/libaxcprobe.a" | tr -d ' ') bytes"
else
  bad "the C archive did not build"; sed 's/^/     /' "$work/cc.err" | head -6; exit 1
fi

cat > "$work/usec.ax" <<'AX'
(import IO)

(import Fmt)

(pub extern "axcprobe"
  (cAdd  :: (-> Int Int Int) (symbol "axc_add"))
  (cMul3 :: (-> Int Int Int Int) (symbol "axc_mul3"))
  (cFib  :: (-> Int Int) (symbol "axc_fib"))
  (cLen  :: (-> String Int) (symbol "axc_strlen"))
  (cCnt  :: (-> String Int Int) (symbol "axc_countbyte")))

;@axiom:effect(io)
(:: main Int)

;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (main)
  (let ((s "hello, world"))
    {
      (println (fmtInt (cAdd 20 22)))
      (println (fmtInt (cMul3 2 3 7)))
      (println (fmtInt (cFib 30)))
      (println (fmtInt (cLen s)))
      (println (fmtInt (cCnt s 108)))
      0
    }
  )
)
AX

# --------------------------------------------------------------------
echo
echo "== it binds, links and answers =="
# --------------------------------------------------------------------
build_c() {  # <axfile> <output> [extra flags...] -> exit status, log at $work/build.log
  local src="$1" out="$2"; shift 2
  set +e
  ( cd "$work" && "$axc" build --input "$src" --output "$out" \
      --link-lib axcprobe --link-search "$lib" "$@" ) >"$work/build.log" 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc"
}

rc="$(build_c usec.ax usec)"
if (( rc == 0 )) && [[ -x "$work/usec" ]]; then
  ok "an Axiom program links a C archive with --link-lib/--link-search"
else
  bad "the build failed (exit $rc)"; sed 's/^/     /' "$work/build.log" | head -10
fi

if [[ -x "$work/usec" ]]; then
  got="$( "$work/usec" 2>&1 )"
  want=$'42\n42\n832040\n12\n3'
  if [[ "$got" == "$want" ]]; then
    ok "three arities and two String reads answer correctly"
  else
    bad "wrong answers"; printf '     got:\n%s\n     want:\n%s\n' "$got" "$want"
  fi
fi

# --------------------------------------------------------------------
echo
echo "== the mechanism, not only the outcome =="
# --------------------------------------------------------------------
# The library name reaches the driver through a comment the emitter
# writes beside the `declare` lines. Checking the emitted text catches
# a change that links by some other route.
# `--emit-llvm` writes the module beside the output as `<output>.ll`,
# so `--output emit` gives `emit.ll`, not `usec.ll`.
set +e
( cd "$work" && "$axc" build --input usec.ax --output emit --emit-llvm \
    --link-lib axcprobe --link-search "$lib" ) >"$work/emit.log" 2>&1
set -e
ll="$work/emit.ll"
if [[ -s "$ll" ]]; then
  ok "--emit-llvm wrote $(wc -l < "$ll" | tr -d ' ') lines of IR"
else
  bad "--emit-llvm wrote no module at $ll"; sed 's/^/     /' "$work/emit.log" | head -6
fi
if [[ -s "$ll" ]] && grep -q '; axiom-extern-lib axcprobe' "$ll"; then
  ok "the emitted module names the library: \`; axiom-extern-lib axcprobe\`"
else
  bad "the emitted module does not carry \`; axiom-extern-lib axcprobe\`"
fi
# The declaration is an ordinary C prototype over machine words.
if [[ -s "$ll" ]] && grep -qE '^declare i64 @axc_add\(i64, i64\)' "$ll"; then
  ok "and declares it with the C ABI: \`declare i64 @axc_add(i64, i64)\`"
else
  bad "no \`declare i64 @axc_add(i64, i64)\` in the emitted module"
  { grep -E '^declare .*axc_' "$ll" 2>/dev/null || true; } | sed 's/^/     /' | head -4
fi

# --------------------------------------------------------------------
echo
echo "== negative probes: each assertion above can fail =="
# --------------------------------------------------------------------
# A symbol no archive defines must be refused before the linker, at
# AX4004, by the grounding pass that reads `declare` lines.
sed 's/(symbol "axc_add")/(symbol "axc_not_there")/' "$work/usec.ax" > "$work/ghost.ax"
rc="$(build_c ghost.ax ghost)"
if (( rc != 0 )) && grep -q 'AX4004' "$work/build.log"; then
  ok "a symbol no archive defines is refused at AX4004, not by the linker"
else
  bad "the ungrounded symbol built or failed elsewhere (exit $rc)"
  sed 's/^/     /' "$work/build.log" | head -6
fi

# Without --link-search the same program must fail, so assertion 1
# can't pass for another reason.
set +e
( cd "$work" && "$axc" build --input usec.ax --output nolink --link-lib axcprobe ) \
  >"$work/nolink.log" 2>&1
rc=$?
set -e
if (( rc != 0 )); then
  ok "without --link-search the same program fails, so the flag is load-bearing"
else
  bad "it built with no --link-search; something else is supplying the archive"
fi

echo
if (( failed > 0 )); then
  echo "check-c-abi: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-c-abi: $checks checks - a plain C archive binds, links, answers,"
echo "             and reads an Axiom String through its documented header,"
echo "             with no Rust anywhere in the path"
