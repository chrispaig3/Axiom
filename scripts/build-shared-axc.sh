#!/usr/bin/env bash
# Build the compiler-under-test ONCE, and stamp it so the gates will
# trust it.
#
# sixty gates call `gate_build_axc`, and each one rebuilt the same
# 60,881 lines. The saving is measured on the only A/B that is not a
# developer machine under unknown load - the `test` job's three CI legs
# on 2026-08-24, at `2283e93` before and `8cf595f` after:
#
#     linux-x86_64    17m38s -> 10m48s
#     linux-aarch64   18m54s -> 11m51s
#     darwin-aarch64  10m01s ->  7m46s
#
# about sixteen minutes per run, ~35%. The single build step that
# replaced them took 20s.
#
# This writes two files: the artifact, and `<artifact>.stamp` holding
# `gate_source_stamp` for the tree as it stands. `gate_build_axc` reuses
# the artifact only while those agree, so this script does not have to
# be re-run when the tree changes - a stale artifact is rebuilt rather
# than believed, an unstamped one is refused, and the gate that proves
# both is `scripts/check-gate-lib.sh`.
#
# Usage:  ./scripts/build-shared-axc.sh <output-path>
# Then:   AXIOM_AXC=<output-path> ./scripts/check-whatever.sh
#
# WHY THIS SCRIPT ASSERTS ANYTHING AT ALL. It is not a gate, and the
# table in CONTRIBUTING.md says so. But it is the one place that makes
# the claim sixty gates then rest on - "this artifact is what you
# would have built" - and until 2026-08-24 the only check here restated
# its own stamp:
#
#     if [[ "$(cat "$out.stamp")" != "$(gate_source_stamp)" ]]; then
#
# `gate_source_stamp` is a pure function of the tree and the builder,
# called twice in one process over an unchanged tree. It can fire only
# if the checkout mutates mid-build. That is a check that cannot fail,
# which is this repository's most common defect, sitting in the script
# whose whole output is a claim of equality.
#
# So the equality is now MEASURED, by building the compiler a second
# time and comparing. Not the two binaries: on macOS the system linker
# stamps a build UUID into the Mach-O, so two builds of identical
# source differ by ~11 KB of bytes no compiler chose - the same reason
# `check-reproducible.sh` compares IR rather than executables. What is
# compared is what the two compilers EMIT for the largest Axiom program
# there is, `self_host/main.ax`: ~145,000 lines of IR from each, byte
# for byte. Two compilers that agree on that are the same compiler for
# every purpose a gate has.
#
# Cost: one extra build - 20s in CI, against the sixteen minutes the
# cache saves.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

out="${1:-}"
if [[ -z "$out" ]]; then
  echo "usage: $0 <output-path>" >&2
  exit 2
fi
mkdir -p "$(dirname "$out")"

build_one() {  # build_one <output> <log>
  if ! "$axiom" build --input self_host/main.ax --output "$1" >"$2" 2>&1; then
    echo "FAIL: could not build the shared compiler from self_host/" >&2
    sed 's/^/    /' "$2" | head -20 >&2
    exit 1
  fi
}

echo "== building the shared compiler under test from self_host/ =="
build_one "$out" "$work/build.log"

# WRITTEN AS THE CONSUMER WILL COMPUTE IT, and that is the whole fix.
#
# `gate_source_stamp` is sha(the tree's `.ax` bytes + sha("$axiom")) -
# it identifies the SOURCES and the COMPILER TOGETHER. But `$axiom` is
# whatever `gate_init` resolved, and the two sides resolve it
# differently: here nothing is set, so it is the bootstrap compiler
# that did the BUILDING; in a gate, `run-gates.sh` has exported
# `AXIOM_AXC`, so `gate_init` answers the ARTIFACT. Two different
# values, two different stamps, and `gate_build_axc` therefore never
# matched and every gate rebuilt a compiler that was already built for
# it - the sixteen minutes per run this file's own header says the
# sharing saves.
#
# Regression, not an old bug: until 2026-08-31 `gate_init` was
# `${AXIOM:-.axiom-bin/axiom}` and IGNORED `AXIOM_AXC`, so both sides
# said "bootstrap" and agreed. Teaching it to honour `AXIOM_AXC` - a
# real fix, for twelve gates that were silently measuring the installed
# binary - changed what this hash means on one side only.
#
# So the stamp is computed with `$axiom` pointing at the ARTIFACT, which
# is what every reader will use. It also reads better than what it
# replaced: the stamp now says "these sources, and THIS compiler", so a
# swapped or truncated artifact fails the comparison too, where before
# it recorded a builder no consumer ever asks about.
( axiom="$out"; gate_source_stamp > "$out.stamp" )

# THE EQUALITY, MEASURED. A second, independent build from the same
# tree with the same builder, and then both compilers are asked to emit
# the IR for `self_host/main.ax`. The artifact this script hands to
# sixty gates is the compiler each of them would have built exactly
# when those two files are identical.
#
# This can go red for a real reason, and the reason is worth naming:
# any nondeterminism in the compiler's own output - a hash-map
# iteration order, an embedded path, a clock - makes the shared
# artifact a DIFFERENT compiler from the one a gate would have built,
# and the stamp cannot see it because the stamp hashes inputs.
# `check-reproducible.sh` pins the same property one level down, over
# `tests/stdlib` and through the seed-descended builder; this pins it
# for the compiler itself, which is the program the cache is about.
#
# THE ABLATION, recorded rather than re-run because it costs two builds
# - the convention `check-symbol-names.sh` states for the same reason.
# In a copy of the tree, with the emitted attribute group changed
# between the two builds (`"no-builtins"` -> `"no-builtins" "ablated"`
# in `codegen.ax`), measured 2026-08-24:
#
#     FAIL: the two builds do not emit the same IR
#         --- 144818 lines vs 144818 lines, first difference at line 144818
#
# and the script exits 1.
#
# TWO WEAKER ABLATIONS DID NOT FIRE, and what they show is worth more
# than the one that did. Appending a comment line to `self_host/main.ax`
# between the builds: still green. Replacing the second build outright
# with the seed-descended `.axiom-bin/axiom`: still green. Both are
# correct answers. This check compares what the two compilers DO, not
# what they were built from, and two compilers that emit the same IR
# for the same input are interchangeable for every purpose a gate has -
# which is the claim being made. A source difference that changes no
# emitted byte is not a difference the sixty gates can observe, and
# a check that failed on one would be reporting a distinction that does
# not exist. The stamp is what covers the inputs; this covers the
# behaviour.
echo "== building it a second time, to measure the equality this claims =="
build_one "$work/second" "$work/build2.log"

"$out"        emit-llvm self_host/main.ax -o "$work/a.ll" >/dev/null
"$work/second" emit-llvm self_host/main.ax -o "$work/b.ll" >/dev/null

a_lines=$(wc -l < "$work/a.ll" | tr -d ' ')

# A comparison of two empty files is a comparison that always passes,
# so the volume is asserted before the equality. 144,818 lines on
# 2026-08-24; the floor is a tenth of that, low enough not to be a
# maintenance burden and high enough that a truncated or failed
# emission cannot slip past as agreement.
if (( a_lines < 14000 )); then
  echo "FAIL: the emitted IR is only $a_lines lines - it was 144818 on 2026-08-24." >&2
  echo "      Comparing two near-empty files would agree about nothing." >&2
  exit 1
fi

if ! cmp -s "$work/a.ll" "$work/b.ll"; then
  b_lines=$(wc -l < "$work/b.ll" | tr -d ' ')
  echo "FAIL: the two builds do not emit the same IR" >&2
  echo "    --- $a_lines lines vs $b_lines lines, first difference at line \
$(cmp "$work/a.ll" "$work/b.ll" 2>&1 | sed 's/.*line //')" >&2
  echo "      The shared artifact is therefore NOT the compiler a gate would" >&2
  echo "      have built, and sixty gates would be testing something else." >&2
  exit 1
fi

echo "ok   $out"
echo "ok   stamp $(cut -c1-16 "$out.stamp")… - gates will reuse this until a source file moves"
echo "ok   a second build emits identical IR for self_host/main.ax ($a_lines lines)"

