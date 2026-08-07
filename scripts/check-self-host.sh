#!/usr/bin/env bash
# Compile every case in tests/selfhost with the *self-hosted* compiler,
# assemble it, run it, and check its exit status.
#
# This is the only gate that exercises stage1 end to end. `cargo test`
# and the stdlib suite both check the Rust compiler; nothing else notices
# when the Axiom one emits LLVM that `llc` rejects, or emits code that
# assembles and computes the wrong answer.
#
# Each case declares its expected exit status on the first line as
# `; expect N`. Exit status is the whole answer - stage1 has no way to
# print yet - so cases must return something distinguishable, and 0 is
# avoided as an expected value since it is also what a silent failure
# looks like.
#
# Usage:
#   scripts/check-self-host.sh          # every case
#   scripts/check-self-host.sh 050      # one case, by name prefix

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "building the compiler first (no binary at $axiom)" >&2
  cargo build --release
fi

export AXIOM_STDLIB="$repo_root/stdlib"

filter="${1:-}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# stage1 resolves `(import Foo)` by reading `self_host/Foo.ax` or
# `stdlib/Foo.ax` relative to its working directory, so those have to be
# reachable from where it runs. Without them every import silently
# resolves to nothing and the emitted module is missing every function it
# calls - which looks like a codegen bug and is not one.
ln -s "$repo_root/stdlib" "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"

# Helper modules for cases that import a SIBLING - a shape no case
# could express while every case was one file, and the one an effect
# declared in another module needs.
#
# They live in `tests/selfhost/` beside the cases, not in a
# subdirectory, because check-diagnostics.sh's silence sweep reads
# every file of this tree FROM ITS REAL PATH: a case whose import
# resolves only inside this script's work directory fails that sweep,
# and it is right to - it did not get far enough to check anything.
# The two kinds are told apart by name below.
cp "$repo_root"/tests/selfhost/[A-Z]*.ax "$work/" 2>/dev/null || true

# stage1: the Axiom compiler, compiled by the Rust one.
if ! "$axiom" build --input self_host/main.ax --output "$work/stage1" >"$work/build.log" 2>&1; then
  echo "FAIL: could not build stage1" >&2
  tail -20 "$work/build.log" >&2
  exit 1
fi

passed=0
failed=0

for case_file in tests/selfhost/*.ax; do
  name="$(basename "$case_file" .ax)"
  if [[ -n "$filter" && "$name" != "$filter"* ]]; then
    continue
  fi

  # A CASE is digit-prefixed (`820-effect-handlers.ax`); anything else
  # in this directory is a helper module a case imports, copied into
  # the work directory above and not run on its own.
  if [[ ! "$name" =~ ^[0-9] ]]; then
    continue
  fi

  # A case missing its expectation is a FAILURE, not a skip. It used to
  # print `SKIP` and go on, which is the same silent-hole shape the
  # sweep in check-diagnostics.sh exists to refuse: a case that stops
  # being run reports nothing, and nothing is what success looks like.
  want="$(sed -n '1s/^; expect \([0-9]*\).*/\1/p' "$case_file")"
  if [[ -z "$want" ]]; then
    echo "FAIL $name (no '; expect N' on the first line, so nothing was checked)"
    failed=$((failed + 1))
    continue
  fi

  # stage1 reads its input from the first argument (default in.ax) and
  # writes LLVM to stdout.
  cp "$case_file" "$work/in.ax"
  if ! (cd "$work" && ./stage1 >out.ll 2>stage1.err); then
    echo "FAIL $name (stage1 rejected it)"
    sed 's/^/    /' "$work/stage1.err" | head -3
    failed=$((failed + 1))
    continue
  fi

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
  if ! llc -filetype=obj -relocation-model=pic "$work/out.ll" -o "$work/out.o" 2>"$work/llc.err"; then
    echo "FAIL $name (llc rejected the emitted IR)"
    grep -m2 "error" "$work/llc.err" | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi

  if ! cc "$work/out.o" -o "$work/prog" -e _main 2>"$work/cc.err"; then
    echo "FAIL $name (link failed)"
    head -3 "$work/cc.err" | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi

  # From `$work`, so a case that opens `in.ax` finds the one it was
  # compiled from rather than nothing.
  (cd "$work" && ./prog)
  got=$?
  if [[ "$got" == "$want" ]]; then
    echo "ok   $name"
    passed=$((passed + 1))
  else
    echo "FAIL $name (exit $got, want $want)"
    failed=$((failed + 1))
  fi
done

# Negative: an import that cannot be resolved is a diagnostic naming the
# module, not a silent skip. Skipping is the failure mode that presented
# `stdlib/Fmt.ax` failing to parse as `use of undefined value '@fmtInt'`
# out of llc - a codegen-shaped report for an import-shaped failure.
# Exit 3 is the driver's import-resolution code (1 = unreadable input,
# 2 = parse error in the input itself).
if [[ -z "$filter" ]]; then
  printf '(import NoSuchModule)\n(:: main Int)\n(fn (main) 7)\n' >"$work/in.ax"
  (cd "$work" && ./stage1 >/dev/null 2>neg.err)
  neg_status=$?
  if [[ "$neg_status" == 3 ]] && grep -q "NoSuchModule" "$work/neg.err"; then
    echo "ok   negative: unresolvable import is refused, naming the module"
    passed=$((passed + 1))
  else
    echo "FAIL negative: unresolvable import (exit $neg_status, want 3 and the module named)"
    sed 's/^/    /' "$work/neg.err" | head -3
    failed=$((failed + 1))
  fi
fi

# Every target stage1 claims must actually assemble: emit the
# syscall-heavy case for each of the four and run llc under that
# target's own triple. A wrong register convention or syscall number
# is invisible on the host - the mmap number 9 assembles fine on
# darwin - so the check is per-triple, not host-only.
if [[ -z "$filter" ]]; then
  cp "$repo_root/tests/selfhost/230-syscall.ax" "$work/in.ax"
  for tgt in darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64; do
    case "$tgt" in
      darwin-aarch64) triple=arm64-apple-macosx14.0.0 ;;
      darwin-x86_64)  triple=x86_64-apple-macosx14.0.0 ;;
      linux-aarch64)  triple=aarch64-unknown-linux-gnu ;;
      linux-x86_64)   triple=x86_64-unknown-linux-gnu ;;
    esac
    if (cd "$work" && ./stage1 in.ax "$tgt" >"out-$tgt.ll" 2>tgt.err) \
       && llc -mtriple="$triple" -relocation-model=pic "$work/out-$tgt.ll" -o /dev/null 2>"$work/llc-$tgt.err"; then
      echo "ok   emit [$tgt] assembles"
      passed=$((passed + 1))
    else
      echo "FAIL emit [$tgt]"
      sed 's/^/    /' "$work/llc-$tgt.err" 2>/dev/null | head -3
      failed=$((failed + 1))
    fi
  done
fi

echo
echo "$passed passed, $failed failed"
[[ "$failed" == 0 ]]
