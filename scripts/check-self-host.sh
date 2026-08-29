#!/usr/bin/env bash
# Compile every case in tests/selfhost with the *self-hosted* compiler,
# assemble it, run it, and check its exit status.
#
# This gate exercises the compiler end to end: it is what notices when
# the compiler emits LLVM that `llc` rejects, or emits code that
# assembles and computes the wrong answer.
#
# Each case declares its expected exit status on the first line as
# `; expect N`, and the exit status is what this gate reads. Cases must
# therefore return something distinguishable, and 0 is avoided as an
# expected value since it is also what a silent failure looks like. A
# handful of cases do `(import IO)` and print, but stdout is
# `check-stdlib-selfhost.sh`'s subject, not this one's.
#
# Usage:
#   scripts/check-self-host.sh          # every case
#   scripts/check-self-host.sh 050      # every case whose name starts with 050

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

filter="${1:-}"

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

# stage1: the compiler built from the current self_host/ by $axiom.
gate_build_axc stage1

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

  # stage1 reads its input from the first argument and writes LLVM to
  # stdout.
  cp "$case_file" "$work/in.ax"
  if ! (cd "$work" && ./stage1 in.ax >out.ll 2>stage1.err); then
    echo "FAIL $name (stage1 rejected it)"
    sed 's/^/    /' "$work/stage1.err" | head -3
    failed=$((failed + 1))
    continue
  fi

# `llc` carries an explicit relocation model, which the driver documents
# as required of every `llc` invocation in the project including these.
#
# It deliberately does NOT carry -O0, even though the emitted bump
# allocator is miscompiled by `llc` at -O1 and above (two consecutive
# `memAlloc 64` calls come back a whole 1 MiB chunk apart). The two
# hazards pull opposite ways: at -O0 the allocator is correct but there
# is no tail-call elimination, and stage2 compiling its own source
# overflows its stack - measured, it segfaults. `axiom build` escapes
# both by running `opt` over the IR before `llc`, which these scripts
# cannot assume is installed (the driver treats a missing `opt` as a
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
# An unresolvable import is a real diagnostic now - AX5001, spanless,
# exit 1, stage0's code (2026-08-08; it was a bare "cannot read
# module" line and exit 3, whose only consumers were this gate and
# check-driver.sh). The pin is structural: the code, the module's
# name, and the help's search-path list must all appear - the exact
# paths differ legitimately between two differently-located binaries,
# which is why this is not a corpus golden.
if [[ -z "$filter" ]]; then
  printf '(import NoSuchModule)\n(:: main Int)\n(fn (main) 7)\n' >"$work/in.ax"
  (cd "$work" && ./stage1 in.ax >/dev/null 2>neg.err)
  neg_status=$?
  if [[ "$neg_status" == 1 ]] && grep -q "AX5001" "$work/neg.err" \
     && grep -q "NoSuchModule" "$work/neg.err" \
     && grep -q "looked for" "$work/neg.err"; then
    echo "ok   negative: unresolvable import is AX5001, naming the module and the search"
    passed=$((passed + 1))
  else
    echo "FAIL negative: unresolvable import (exit $neg_status, want 1 with AX5001 + module + search paths)"
    sed 's/^/    /' "$work/neg.err" | head -3
    failed=$((failed + 1))
  fi
fi

# The standard library is findable from a directory that has not been
# salted with symlinks.
#
# stage1 used to search the entry file's directory and then the literal
# strings `self_host/` and `stdlib/` RELATIVE TO ITS WORKING DIRECTORY,
# so a user compiling a hello-world that imports `IO` from anywhere else
# got `cannot read module: IO` and exit 3. Every gate in this repository
# hid that by running from the repo root or by symlinking `stdlib` into
# its work directory - including this one, which is why the check below
# deliberately uses a FRESH directory containing nothing but the source.
#
# Ablating the search path back to the hardcoded pair fails this and
# nothing else, which is how it is known to discriminate.
if [[ -z "$filter" ]]; then
  away="$work/away"
  rm -rf "$away" && mkdir -p "$away"
  printf '(import IO)\n(:: main Int)\n;@axiom:effect(io)\n(fn (main) { (println "ok") 0 })\n' \
    >"$away/hello.ax"
  if (cd "$away" && AXIOM_STDLIB="$repo_root/stdlib" "$work/stage1" hello.ax \
        >hello.ll 2>hello.err) && grep -q 'define .*@main' "$away/hello.ll"; then
    echo "ok   the standard library resolves from an unprepared directory"
    passed=$((passed + 1))
  else
    echo "FAIL stage1 could not find the standard library outside the repo root"
    sed 's/^/    /' "$away/hello.err" 2>/dev/null | head -3
    failed=$((failed + 1))
  fi
fi

# Every target stage1 claims must actually assemble: emit the
# syscall-heavy case for each of the seven and run llc under that
# target's own triple. A wrong register convention or syscall number
# is invisible on the host - the mmap number 9 assembles fine on
# darwin - so the check is per-triple, not host-only. windows-x86_64
# makes no syscall at all: its `sysWriteFd` goes through kernel32, and
# a wrong `dllimport` declare is what llc would refuse here.
if [[ -z "$filter" ]]; then
  cp "$repo_root/tests/selfhost/230-syscall.ax" "$work/in.ax"
  all_targets="darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64 freebsd-x86_64 freebsd-aarch64 windows-x86_64"
  for tgt in $all_targets; do
    case "$tgt" in
      darwin-aarch64)  triple=arm64-apple-macosx14.0.0 ;;
      darwin-x86_64)   triple=x86_64-apple-macosx14.0.0 ;;
      linux-aarch64)   triple=aarch64-unknown-linux-gnu ;;
      linux-x86_64)    triple=x86_64-unknown-linux-gnu ;;
      freebsd-x86_64)  triple=x86_64-unknown-freebsd14.0 ;;
      freebsd-aarch64) triple=aarch64-unknown-freebsd14.0 ;;
      windows-x86_64)  triple=x86_64-pc-windows-msvc ;;
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

  # Assembling under a triple is necessary and NOT sufficient, and the
  # gap is not hypothetical: darwin-aarch64's IR assembles cleanly under
  # `aarch64-unknown-linux-gnu`, because `svc #0x80` is a valid AArch64
  # instruction whatever the OS and `{x16}` allocates fine. So if stage1
  # ever stopped honouring the target argument, this loop would emit the
  # same Darwin IR seven times and still report several of the seven green -
  # while every Linux binary carried Darwin syscall numbers.
  #
  # Requiring the seven to be pairwise distinct is what closes that. It
  # is satisfiable today (the seven differ), so it is an assertion about
  # the compiler rather than an aspiration - and for one pair it is a
  # DERIVED fact rather than an obvious one: freebsd-x86_64 reuses
  # darwin-x86_64's syscall template byte for byte (both kernels
  # answer through the carry flag), and the two modules differ only
  # in the triple and the syscall numbers.
  #
  # WHAT THIS CHECK CANNOT SEE, measured 2026-08-29: with
  # freebsd-aarch64's syscall template replaced by linux-aarch64's -
  # `svc #0` with no carry epilogue, so every failed syscall on
  # FreeBSD would answer a positive errno that `sysFailed` reads as
  # success - all six modules still emitted, still assembled, and
  # this check still reported "six different modules", because the
  # triple and the numbers keep that pair apart on their own. So
  # distinctness proves the target argument is honoured and nothing
  # about the template's CONTENT; `check-platform-constants.sh`'s
  # carry-epilogue assertion is what holds the content, and that
  # ablation is recorded there as the probe that made it exist.
  dupes=0
  for a in $all_targets; do
    for b in $all_targets; do
      [[ "$a" < "$b" ]] || continue
      if cmp -s "$work/out-$a.ll" "$work/out-$b.ll"; then
        echo "FAIL emit [$a] and [$b] are byte-identical: the target argument is being ignored"
        dupes=1
      fi
    done
  done
  if [[ "$dupes" == 0 ]]; then
    echo "ok   the seven targets emit seven different modules"
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
fi

echo
echo "$passed passed, $failed failed"
[[ "$failed" == 0 ]]
