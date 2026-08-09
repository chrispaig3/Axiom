#!/usr/bin/env bash
# Regenerate the checked-in bootstrap seeds from the current tree.
#
# Run this when `scripts/bootstrap-from-seed.sh` fails because the
# committed seed can no longer compile self_host/ - that is the seed
# going stale, and it is the only routine reason to move it. Advancing
# it otherwise is optional and costs 8.4 MB of generated text in the
# diff, so do it on purpose.
#
# The seeds are the compiler's own LLVM IR, one per target, produced by
# the compiler currently in the tree. Every target is generated from a
# single host, which is exactly what scripts/check-cross-targets.sh
# already proves is sound - the target decides the syscall ABI and the
# triple, not the machine doing the compiling. Measured: the four files
# differ from one another in 193 lines of 61,473.
#
# Requires a working compiler to start from. It defaults to the one
# every other script here defaults to - `.axiom-bin/axiom`, where
# `bootstrap-from-seed.sh --install` puts it - and AXIOM names another:
#
#   AXIOM=/path/to/compiler scripts/reseed.sh
#
# It does NOT bootstrap one itself, unlike the gates. The routine
# reason to run this is that the committed seed can no longer compile
# self_host/ - so a bootstrap from that seed is exactly the thing that
# has just failed, and silently attempting it here would replace a
# clear "the seed is stale" with a confusing one. Name a compiler that
# works: the previous commit's `.axiom-bin/axiom` is the usual answer.
#
# The seeds are REPRODUCIBLE - scripts/check-reproducible.sh is the gate
# that says so - which means re-running this against an unchanged tree
# leaves the files untouched and `git status` clean. If it does not, the
# compiler has a nondeterminism bug and that is the thing to fix.

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() { echo "FAIL: $*" >&2; exit 1; }

axiom="${AXIOM:-$repo_root/.axiom-bin/axiom}"
[[ -x "$axiom" ]] || fail "no compiler at $axiom - set AXIOM to one"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ln -s "$repo_root/stdlib"    "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"

# The seed is emitted by a compiler built from THIS tree, never by
# `$axiom` directly - `$axiom` is only trusted to be new enough to
# compile self_host/, not to be what the seed should record. So the
# first thing that happens here is building the compiler; the seeds
# come out of THAT. (Written while the Rust compiler still existed and
# could be passed in; the reasoning is unchanged now that any `$axiom`
# is itself self-hosted.)
if ! "$axiom" build --input self_host/main.ax --output "$work/gen" >"$work/build.log" 2>&1; then
  # `$axiom` may already be a self-hosted compiler, which has no
  # `build --input` spelled that way only if it is very old; try the
  # plain form before giving up.
  cp "$repo_root/self_host/main.ax" "$work/in.ax"
  (cd "$work" && "$axiom" in.ax >"$work/gen.ll" 2>/dev/null) \
    || { tail -20 "$work/build.log" >&2; fail "could not build a compiler with $axiom"; }
  llc -filetype=obj -relocation-model=pic "$work/gen.ll" -o "$work/gen.o" 2>/dev/null \
    || fail "llc rejected the IR from $axiom"
  cc "$work/gen.o" -o "$work/gen" -e _main 2>/dev/null || fail "could not link the generator"
fi
echo "generator built"

mkdir -p bootstrap
targets="darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64"
cp "$repo_root/self_host/main.ax" "$work/in.ax"
for t in $targets; do
  (cd "$work" && ./gen in.ax "$t" >"$work/out.ll" 2>"$work/out.err") \
    || { head -3 "$work/out.err" >&2; fail "could not emit the seed for $t"; }
  # A seed that is empty, or that is the wrong target, is worse than no
  # seed: it fails far away from here. Check both before writing.
  grep -q "^target triple" "$work/out.ll" || fail "the $t seed has no target triple"
  lines="$(wc -l <"$work/out.ll")"
  (( lines > 10000 )) || fail "the $t seed is only $lines lines - the emit was truncated"
  mv "$work/out.ll" "bootstrap/axiom-$t.ll"
  printf '  %-16s %8d bytes  %7d lines\n' "$t" "$(wc -c <"bootstrap/axiom-$t.ll")" "$lines"
done

( cd bootstrap && { command -v sha256sum >/dev/null && sha256sum axiom-*.ll || shasum -a 256 axiom-*.ll; } ) \
  > bootstrap/SHA256SUMS
echo "wrote bootstrap/SHA256SUMS"

cat > bootstrap/STAMP <<STAMP
Generated from commit: $(git rev-parse HEAD 2>/dev/null || echo "unknown")
Generated on:          $(date -u +%Y-%m-%dT%H:%M:%SZ)
Regenerate with:       scripts/reseed.sh
Verified by:           scripts/bootstrap-from-seed.sh
STAMP
cat bootstrap/STAMP

echo
echo "seeds regenerated; run scripts/bootstrap-from-seed.sh before committing them"
