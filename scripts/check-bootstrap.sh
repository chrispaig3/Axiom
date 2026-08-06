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

echo
echo "fixpoint reached: the Axiom compiler reproduces itself"
