#!/usr/bin/env bash
# Build the compiler under test once, and stamp it so the gates trust
# it.
#
# Ninety-five gates call `gate_build_axc`. With a shared artifact, none
# of them rebuilds the compiler, which saves a large share of each CI
# test leg.
#
# This writes two files: the artifact, and `<artifact>.stamp` holding
# `gate_source_stamp` for the tree. `gate_build_axc` reuses the artifact
# only while the two agree, so there is no need to re-run this when the
# tree changes. A stale artifact is rebuilt and an unstamped one is
# refused; `scripts/check-gate-lib.sh` proves both.
#
# Usage:  ./scripts/build-shared-axc.sh <output-path>
# Then:   AXIOM_AXC=<output-path> ./scripts/check-whatever.sh
#
# It is not a gate, but every gate that reuses the artifact rests on its
# claim: "this artifact is what you would have built". So it builds the
# compiler twice and compares, byte for byte, the IR both emit for
# `self_host/main.ax`, the largest Axiom program. It compares IR, not
# binaries, because the macOS linker stamps a build UUID into each
# Mach-O. The extra build is cheap next to what the cache saves.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

out="${1:-}"
if [[ -z "$out" ]]; then
  echo "usage: $0 <output-path>" >&2
  exit 2
fi
mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"

# Serialise publishers of this path. Build and verify privately, then
# rename fresh inodes into place; never truncate an executable in use.
lock="$out.lock"
waited=0
until mkdir "$lock" 2>/dev/null; do
  (( waited < 300 )) || { echo "FAIL: timed out waiting for $lock" >&2; exit 1; }
  sleep 1
  waited=$((waited + 1))
done
pending=""
cleanup_shared() {
  [[ -z "$pending" ]] || rm -f "$pending" "$pending.stamp"
  rmdir "$lock"
  rm -rf "$work"
}
trap cleanup_shared EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
initial_stamp="$(gate_source_stamp)"
candidate="$work/candidate"

build_one() {  # build_one <output> <log>
  if ! "$axiom" build --input self_host/main.ax --output "$1" >"$2" 2>&1; then
    echo "FAIL: could not build the shared compiler from self_host/" >&2
    sed 's/^/    /' "$2" | head -20 >&2
    exit 1
  fi
}

echo "== building the shared compiler under test from self_host/ =="
build_one "$candidate" "$work/build.log"

# A second, independent build from the same tree and builder, then both
# compilers emit the IR for `self_host/main.ax`. The shared artifact is
# the compiler each gate would have built exactly when the two files are
# identical.
#
# Any nondeterminism in the compiler's output, such as hash-map order,
# an embedded path or a clock, fails this. The stamp cannot see it,
# because the stamp hashes inputs. `check-reproducible.sh` pins the same
# property over `tests/stdlib` through the seed-descended builder; this
# pins it for the compiler itself.
#
# The ablation is recorded rather than re-run, because it costs two
# builds (as in `check-symbol-names.sh`). In a copy of the tree, change
# the emitted attribute group between the two builds (`"no-builtins"` to
# `"no-builtins" "ablated"` in `codegen.ax`): this then reports "the two
# builds do not emit the same IR" and exits 1.
#
# A source change that alters no emitted byte passes, such as a comment
# added to `self_host/main.ax`, and so does building the second compiler
# with the seed-descended `.axiom-bin/axiom`. That is correct: this
# compares what the compilers do, and the stamp covers their inputs.
echo "== building it a second time, to measure the equality this claims =="
build_one "$work/second" "$work/build2.log"

"$candidate"  emit-llvm self_host/main.ax -o "$work/a.ll" >/dev/null
"$work/second" emit-llvm self_host/main.ax -o "$work/b.ll" >/dev/null

a_lines=$(wc -l < "$work/a.ll" | tr -d ' ')

# Two empty files always compare equal, so assert the volume first. The
# floor is about a tenth of the usual IR: low enough to need no upkeep,
# high enough that a truncated or failed emission cannot pass as
# agreement.
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
  echo "      have built, and ninety-five gates would be testing something else." >&2
  exit 1
fi

# Publish only after both builds and the comparison succeed, and only if
# the build inputs did not change meanwhile.
if [[ "$(gate_source_stamp)" != "$initial_stamp" ]]; then
  echo "FAIL: build inputs changed while building the shared compiler; nothing published" >&2
  exit 1
fi
pending="$(mktemp "$out.pending.XXXXXX")"
# -p: mktemp files are 0600, and a plain cp onto an existing path keeps
# the destination mode, which would publish a non-executable compiler.
cp -p "$candidate" "$pending"
# Stamp with `$axiom` pointing at the artifact, as every consumer
# computes it. `gate_source_stamp` hashes `$axiom` along with the
# sources. Here `$axiom` is the bootstrap builder, but in a gate
# `run-gates.sh` exports `AXIOM_AXC`, so `gate_init` resolves the
# artifact. A stamp taken with the builder would never match, and every
# gate would rebuild. Stamping the artifact also makes a swapped or
# truncated artifact fail the comparison.
( axiom="$candidate"; gate_source_stamp > "$pending.stamp" )
mv -f "$pending" "$out"
mv -f "$pending.stamp" "$out.stamp"
pending=""

echo "ok   $out"
echo "ok   stamp $(cut -c1-16 "$out.stamp")… - gates will reuse this until a source file moves"
echo "ok   a second build emits identical IR for self_host/main.ax ($a_lines lines)"
