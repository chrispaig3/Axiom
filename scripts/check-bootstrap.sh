#!/usr/bin/env bash
# The self-hosting fixpoint.
#
#   stage0  the Rust compiler in this repository        - trusted
#   stage1  the Axiom compiler, built by stage0         - the new code
#   stage2  the Axiom compiler, built by stage1
#   stage3  the Axiom compiler, built by stage2
#
# Self-hosting is reached when stage2 and stage3 are byte-identical: at
# that point the compiler reproduces itself exactly, so nothing about it
# depends on stage0 any longer except the trust placed in it. Comparing
# stage1 against stage2 would prove less - stage1 was built by a
# different compiler and may legitimately differ - which is why the
# classic criterion starts one stage later.
#
# Every stage is also run on the conformance corpus, because two
# compilers can agree byte-for-byte on their own source and still both be
# wrong. `check-self-host.sh` covers stage1; this covers stage2 and
# stage3 by re-running one case through each.

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "building the compiler first (no binary at $axiom)" >&2
  cargo build --release
fi

export AXIOM_STDLIB="$repo_root/stdlib"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# stage1 resolves imports relative to its working directory.
ln -s "$repo_root/stdlib" "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"

fail() { echo "FAIL: $*" >&2; exit 1; }

# Build stage N+1 from stage N: the stage reads `in.ax` and writes LLVM
# to stdout, so compiling the compiler means feeding it its own entry
# point.
build_next() {
  local from="$1" out_ll="$2" out_bin="$3"
  cp "$repo_root/self_host/main.ax" "$work/in.ax"
  (cd "$work" && "./$from" >"$out_ll" 2>"$out_ll.err") || fail "$from could not compile self_host/main.ax"
# `llc` carries an explicit relocation model, which axiom-cli documents
# as required of every `llc` invocation in the project including these.
#
# It deliberately does NOT carry -O0, even though the emitted bump
# allocator is miscompiled by `llc` at -O1 and above (two consecutive
# `memAlloc 64` calls come back a whole 1 MiB chunk apart). The two
# hazards pull opposite ways: at -O0 the allocator is correct but there
# is no tail-call elimination, and stage2 compiling its own source
# overflows its stack - measured, it segfaults. `axiom build` escapes
# both by running `opt` over the IR before `llc`, which these scripts
# cannot assume is installed (axiom-cli treats a missing `opt` as a
# warning). Small programs get -O0 in check-stdlib-selfhost.sh, where
# the allocator matters and the stack does not.
  llc -filetype=obj -relocation-model=pic "$work/$out_ll" -o "$work/$out_bin.o" 2>"$work/llc.err" \
    || { head -3 "$work/llc.err" >&2; fail "llc rejected the IR $from produced"; }
  cc "$work/$out_bin.o" -o "$work/$out_bin" -e _main 2>"$work/cc.err" \
    || { head -3 "$work/cc.err" >&2; fail "could not link $out_bin"; }
}

# A stage has to compile and run something real, not just reproduce
# itself.
check_runs() {
  local stage="$1"
  cat >"$work/in.ax" <<'CASE'
(:: add (-> Int Int Int))
(fn (add x y) (+ x y))
(:: main Int)
(fn (main) (add 40 2))
CASE
  (cd "$work" && "./$stage" >"prog.ll" 2>/dev/null) || fail "$stage could not compile the probe"
  llc -filetype=obj -relocation-model=pic "$work/prog.ll" -o "$work/prog.o" 2>/dev/null || fail "$stage emitted IR llc rejects"
  cc "$work/prog.o" -o "$work/prog" -e _main 2>/dev/null || fail "$stage emitted an object that will not link"
  (cd "$work" && ./prog)
  local got=$?
  [[ "$got" == 42 ]] || fail "a program built by $stage answered $got, want 42"
  echo "ok   $stage compiles and runs a program correctly"
}

"$axiom" build --input self_host/main.ax --output "$work/stage1" >"$work/build.log" 2>&1 \
  || { tail -20 "$work/build.log" >&2; fail "stage0 could not build stage1"; }
echo "ok   stage1 built by the Rust compiler"
check_runs stage1

build_next stage1 stage2.ll stage2
echo "ok   stage2 built by stage1"
check_runs stage2

build_next stage2 stage3.ll stage3
echo "ok   stage3 built by stage2"
check_runs stage3

if ! cmp -s "$work/stage2.ll" "$work/stage3.ll"; then
  echo "FAIL: stage2 and stage3 differ" >&2
  cmp "$work/stage2.ll" "$work/stage3.ll" >&2 | head -3
  exit 1
fi
echo "ok   stage2 and stage3 emit identical IR"

if ! cmp -s "$work/stage2.o" "$work/stage3.o"; then
  fail "stage2 and stage3 IR matched but their objects differ"
fi
echo "ok   stage2 and stage3 are byte-identical binaries"

# ---------------------------------------------------------------
# stage2's formatter produces the golden zoo.
#
# check-fmt-selfhost.sh proves stage1's `fmt` - compiled by stage0 -
# is the same function as stage0's. Nothing there runs the printer AS
# COMPILED BY THE AXIOM COMPILER: a stage1 miscompile of format.ax
# could leave the fixpoint intact (stage2 and stage3 are built by
# equally-affected parents) while stage2's `fmt` writes different
# bytes. One zoo pass through stage2 closes that hole: same golden,
# third compiler. `fmt` resolves no imports, so it needs none of the
# module plumbing the compile steps set up.
# ---------------------------------------------------------------
cp "$repo_root/tests/fmt/syntax-zoo.ax" "$work/zoo2.ax"
if ! (cd "$work" && ./stage2 fmt zoo2.ax >/dev/null 2>&1); then
  fail "stage2's fmt refused the zoo that stage0 and stage1 format"
fi
if ! cmp -s "$work/zoo2.ax" "$repo_root/tests/fmt/syntax-zoo.expected.ax"; then
  fail "stage2's fmt does not produce the golden zoo"
fi
echo "ok   stage2's fmt produces the golden zoo"

# The ladder again, this time driven by the compiler itself.
#
# Everything above proves the fixpoint but NOT that the compiler is
# usable, and the difference is the whole of phase 5. The `build_next`
# above runs `llc` and `cc` on stage1's behalf: what it demonstrates is
# that stage1 emits good IR, not that stage1 can produce an executable.
# For most of this project's life stage1 could not - it wrote LLVM text
# to stdout and stopped, and every gate here finished the job for it.
#
# `stage1 build` does the whole job: writes the IR, runs `opt`, runs
# `llc`, runs `cc`, and cleans up after itself, spawning each child
# through `Sys.sysRunPath`. This section is kept separate from the one
# above rather than replacing it, so that a bug in the driver cannot
# hide a bug in the compiler by taking the fixpoint signal down with it.
#
# The two stages are built to the same BASENAME in different
# directories, and that is load-bearing on macOS: `ld` derives the
# Mach-O `LC_UUID` from the output path, so building `stage2` and
# `stage3` side by side makes two byte-identical compilers differ in 48
# bytes - 16 of UUID and the ad-hoc code signature that covers it -
# for a reason neither compiler caused. Measured; the emitted IR was
# identical throughout.
mkdir -p "$work/d2" "$work/d3"

if ! "$work/stage1" build --input "$repo_root/self_host/main.ax" \
     --output "$work/d2/axc" >"$work/drv2.log" 2>&1; then
  sed 's/^/    /' "$work/drv2.log" | head -5 >&2
  fail "stage1 could not build its successor through its own driver"
fi
echo "ok   stage1 built stage2 by itself - no llc or cc from this script"

if ! "$work/d2/axc" build --input "$repo_root/self_host/main.ax" \
     --output "$work/d3/axc" >"$work/drv3.log" 2>&1; then
  sed 's/^/    /' "$work/drv3.log" | head -5 >&2
  fail "the self-built compiler could not build its own successor"
fi
echo "ok   stage2 built stage3 by itself, with no Rust compiler involved"

if ! cmp -s "$work/d2/axc" "$work/d3/axc"; then
  fail "the self-driven stage2 and stage3 binaries differ"
fi
echo "ok   the self-driven stage2 and stage3 are byte-identical"

# And it compiles a real program end to end, because two compilers can
# agree on their own source and still both be wrong.
cat >"$work/d3/prog.ax" <<'CASE'
(import IO)
(:: main Int)
;@axiom:effect(io)
(fn (main) { (println "self-hosted") 42 })
CASE
(cd "$work/d3" && ./axc build --input prog.ax --output prog >build.log 2>&1) \
  || { sed 's/^/    /' "$work/d3/build.log" | head -5 >&2; fail "the self-built compiler could not build a program"; }
out="$("$work/d3/prog")"; got=$?
[[ "$got" == 42 && "$out" == "self-hosted" ]] \
  || fail "a program built by the self-built compiler said '$out'/$got, want 'self-hosted'/42"
echo "ok   a program built end to end by the self-built compiler runs correctly"

# ---------------------------------------------------------------
# What one self-compile costs.
#
# This exists because the cost was once 16.9 GB and nothing said so.
# `renderCG` left-folded `strConcat` over the emitted line vector, which
# is one allocation and one full copy of everything emitted so far per
# line, over an allocator that never frees - so peak was the SUM of every
# intermediate rather than the largest, and it grew with the SQUARE of
# the compiler's own size. Measured on the same input before and after
# the two-pass join: 16,973,522,240 -> 72,958,912 bytes of peak
# footprint, 11.54 s -> 0.85 s, with byte-identical output.
#
# A ceiling rather than a benchmark: the number to protect is the shape,
# not the constant. Quadratic growth crosses 400 MB long before it
# crosses a CI runner's limit, and it presents as SIGKILL in an
# unrelated-looking job - which is why this is a gate and not a note.
#
# It measures rather than assumes it can: a platform where neither
# `time` spelling works fails here, because a resource check that
# silently skips is the failure this repository has hit twice.
# ---------------------------------------------------------------
peak_rss_kb() {
  # Darwin's `time -l` reports bytes; GNU's `time -v` reports kilobytes.
  if /usr/bin/time -l true >/dev/null 2>&1; then
    /usr/bin/time -l "$@" 2>&1 >/dev/null \
      | awk '/maximum resident set size/ { print int($1 / 1024) }'
  elif /usr/bin/time -v true >/dev/null 2>&1; then
    /usr/bin/time -v "$@" 2>&1 >/dev/null \
      | awk '/Maximum resident set size/ { print $NF }'
  fi
}

cp "$repo_root/self_host/main.ax" "$work/in.ax"
peak="$(cd "$work" && peak_rss_kb ./stage1)"
if [[ -z "$peak" ]]; then
  fail "could not measure the self-compile's peak memory (no usable /usr/bin/time)"
fi
ceiling=409600   # 400 MiB
if (( peak > ceiling )); then
  fail "one self-compile peaked at $((peak / 1024)) MiB, over the $((ceiling / 1024)) MiB ceiling - suspect an accumulator that copies"
fi
echo "ok   one self-compile peaks at $((peak / 1024)) MiB, under the $((ceiling / 1024)) MiB ceiling"

echo
echo "fixpoint reached: the Axiom compiler reproduces itself, and builds itself"
