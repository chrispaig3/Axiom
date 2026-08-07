#!/usr/bin/env bash
# Run the standard-library test corpus through BOTH compilers and
# compare what the programs actually do: exit status and stdout.
#
# This gate exists because nothing else ran `tests/stdlib/` through
# stage1. `check-self-host.sh` runs `tests/selfhost/` end to end;
# `run-stdlib-tests.sh` runs `tests/stdlib/` through *stage0* only;
# and `check-diagnostics.sh` does compile `tests/stdlib/` with stage1
# but only reads its diagnostics, and explicitly exempts a non-zero
# exit there. So a stage1 miscompile of a stdlib test was invisible to
# every gate in the repository, and five of them were: two programs
# whose output was wrong, one whose IR `llc` rejected, and two more
# found only by running this comparison for the first time.
#
# `llc` carries an explicit relocation model, which axiom-cli documents
# as required of every `llc` invocation in the project including this
# one. It deliberately does NOT carry -O0: it did for one commit, as a
# workaround for the bump allocator coming apart at -O1 and above, and
# that turned out to be an undeclared inline-asm clobber in the arm64
# syscall sequence rather than anything about optimisation level. With
# the clobbers declared the gate runs at `llc`'s default, which is the
# configuration a user gets.
#
# The comparison is against stage0's answer rather than a checked-in
# expected value on purpose: stage0 is the trusted implementation, and
# `run-stdlib-tests.sh` already pins stage0's own answers, so
# "stage1 agrees with stage0" plus "stage0 is pinned" is the same
# three-way property `check-diagnostics.sh` gets from its goldens.
#
# Usage:
#   scripts/check-stdlib-selfhost.sh          # every case
#   scripts/check-stdlib-selfhost.sh 080      # one case, by name prefix

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
[[ -x "$axiom" ]] || cargo build --release

export AXIOM_STDLIB="$repo_root/stdlib"
filter="${1:-}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

ln -s "$repo_root/stdlib" "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"
ln -s "$repo_root/tests" "$work/tests"

# Helper modules for `tests/selfhost/` cases that import a sibling.
# Copied flat because a module's name is its filename stem; the cases
# themselves are digit-prefixed, which is how the two are told apart.
cp "$repo_root"/tests/selfhost/[A-Z]*.ax "$work/" 2>/dev/null || true

if ! "$axiom" build --input self_host/main.ax --output "$work/stage1" >"$work/build.log" 2>&1; then
  echo "FAIL: could not build stage1" >&2
  tail -20 "$work/build.log" >&2
  exit 1
fi

# Language surface stage1 has not implemented. Not miscompiles - each
# refuses loudly - and each is recorded in docs/self-hosting.md.
# Listed by name so that a file leaving a list is a deliberate edit.
#
# Both lists are empty. They held two kinds, conflated under one
# "unparsed" label until the exit codes were actually read:
#   exit 2, a real PARSE failure - qualified `Mod::name` references
#           and struct variants were both here, and both parse now.
#   exit 3, parsed but REFUSED - the effect system, which stage1
#           checked (AX3011/AX3016/AX3017 byte-identical) but did not
#           lower. It lowers now: evidence slots, outward dispatch and
#           the unhandled trap, so all three cases run and agree.
UNPARSED=""
UNLOWERED=""

# Programs stage1 compiles and gets WRONG. Every entry is a real bug
# with a diagnosis; the list is here so the gate can be green while
# they are open, and so that a fix cannot land unnoticed - a name on
# this list that starts agreeing FAILS the gate and must be removed.
#
#   (empty)
#
# Fixed and removed from this list: 120-pattern-representation (nested
# nullary constructor patterns parsed as binders), 270-nullary-unboxed
# (the builtin `Option` was absent from the codegen type registry),
# 280-function-application (a non-name application head lowered to the
# constant 0, deleting the call) and 140-function-values (an
# over-applied spine flattened into one direct call). The gate refused
# to stay green when each started agreeing, which is what the list is
# for - all four left it that way. 160-arena left it too, but for a
# different reason: it was never a stage1 bug at all, only this
# script's own `llc` invocation missing -O0.
KNOWN_WRONG=""

in_list() { case " $2 " in *" $1 "*) return 0;; *) return 1;; esac; }

# Cases stage0 cannot build, and it is not a defect in either compiler:
# each imports the self-hosted compiler's OWN modules (`lexer`,
# `parser`, `typecheck`, `codegen`, `diag`), which stage1 resolves
# through its `self_host/` fallback path and stage0 does not resolve at
# all. They are stage1-only by construction, and `check-self-host.sh`
# covers them against their `; expect N`.
# Programs whose recursion depth needs LLVM's tail-call elimination to
# fit on a stack, and which therefore cannot be compared through a RAW
# `llc` pipeline at all.
#
# `320-effect-gc-roots` churns 200,000 allocations through `churn`,
# whose self call sits in a `let` body - which neither compiler treats
# as tail position, deliberately, because stage0 does not. Without
# `opt` that is a real 200,000-frame chain, and whether it fits is a
# question about FRAME SIZE rather than about either compiler's
# semantics: stage0 gives every function a hidden closure parameter and
# spills its bindings to allocas, stage1 does neither, so stage0
# overflows an 8 MiB stack here and stage1 does not (measured: stage0's
# raw IR exits 139 at both -O0 and -O2, and 0 once `opt -O1` has run;
# stage1's exits 0 at every level). `axiom build` runs `opt` and both
# are fine, which is the configuration users get and the one
# `run-stdlib-tests.sh` covers.
#
# Listed rather than silently tolerated, and listed by name so that a
# file leaving the list is a deliberate edit.
NEEDS_OPT="320-effect-gc-roots"

STAGE0_CANNOT="270-lex 280-parse 290-emit 300-pipeline 630-decl-spans \
640-axdl-render 650-quote 660-span-shapes 680-expr-spans 720-type-render \
840-large-lex"

passed=0; failed=0; skipped=0; xfail=0; compared=0

# Both trees, and both optimisation levels.
#
# `tests/selfhost/` used to be checked only against its own `; expect N`
# line - stage1's answer against a number, with stage0 never asked. That
# is a two-way comparison wearing a golden's clothes, and this file's
# own header explains why that is not enough. Running both compilers
# over it makes the property three-way for that tree too:
# expect == stage0 == stage1.
#
# The two `llc` levels are not redundant, because the hazards they
# expose pull in opposite directions and each hid a real bug: at -O1 and
# above an undeclared inline-asm clobber broke the bump allocator, and
# at -O0 there is no tail-call elimination, so a deeply recursive
# program overflows. Checking one level only is checking half the
# configurations a user gets.
for case_file in tests/stdlib/*.ax tests/selfhost/[0-9]*.ax; do
  name="$(basename "$case_file" .ax)"
  [[ -n "$filter" && "$name" != "$filter"* ]] && continue

  if in_list "$name" "$UNPARSED"; then
    echo "skip $name (stage1 does not parse it)"
    skipped=$((skipped + 1))
    continue
  fi
  if in_list "$name" "$UNLOWERED"; then
    echo "skip $name (stage1 parses and checks it, but does not lower effects)"
    skipped=$((skipped + 1))
    continue
  fi
  if in_list "$name" "$NEEDS_OPT"; then
    echo "skip $name (deep non-tail recursion; needs opt's tailcallelim to fit a stack)"
    skipped=$((skipped + 1))
    continue
  fi
  if in_list "$name" "$STAGE0_CANNOT"; then
    echo "skip $name (imports the self-hosted compiler; stage0 cannot resolve it)"
    skipped=$((skipped + 1))
    continue
  fi

  # Both compilers are asked for IR, and the SAME toolchain turns each
  # into a binary. Taking stage0's side from `axiom build` instead
  # compared unlike with unlike: the driver runs `opt` before `llc`, so
  # stage0's binary arrived optimised while stage1's came raw out of
  # `llc -O0`, and a program that survives only because LLVM eliminated
  # its tail calls then "disagreed" about nothing the compilers did.
  # Holding the toolchain constant is what makes this a comparison of
  # the two compilers rather than of two build pipelines.
  if ! "$axiom" build --input "$case_file" --emit-llvm --output "$work/o0" >/dev/null 2>&1; then
    echo "FAIL $name (stage0 could not build it)"
    failed=$((failed + 1))
    continue
  fi

  # stage1 is given the case's real path, not a copy: it derives the
  # module search directory from its argument, and a case importing a
  # module that sits beside it - `150-qualified-modules.ax` imports
  # `Q.Inner`, which is `tests/stdlib/Q/Inner.ax` - cannot resolve it
  # from a copy in the work directory. Copying to `in.ax` was why that
  # case looked unparseable.
  if ! (cd "$work" && ./stage1 "$case_file" >s1.ll 2>/dev/null); then
    echo "FAIL $name (stage1 could not emit it)"
    failed=$((failed + 1))
    continue
  fi

  agree=1
  why=""
  for opt in -O0 -O2; do
    built=1
    for side in o0 s1; do
      llc "$opt" -filetype=obj -relocation-model=pic "$work/$side.ll" -o "$work/$side.o" 2>/dev/null \
        && cc "$work/$side.o" -o "$work/$side.bin" -e _main 2>/dev/null || built=0
    done
    if [[ "$built" == 0 ]]; then
      agree=0; why="$why $opt(llc/cc rejected one side)"
      continue
    fi
    (cd "$work" && ./o0.bin >e0.txt 2>&1); e0=$?
    (cd "$work" && ./s1.bin >e1.txt 2>&1); e1=$?
    if [[ "$e0" != "$e1" ]] || ! cmp -s "$work/e0.txt" "$work/e1.txt"; then
      agree=0; why="$why $opt(stage0 exit $e0, stage1 exit $e1)"
    fi
  done
  compared=$((compared + 1))

  if in_list "$name" "$KNOWN_WRONG"; then
    if [[ "$agree" == 1 ]]; then
      # A known-wrong case that now agrees is good news the list has
      # to be told about, or the list rots into a lie.
      echo "FAIL $name (listed as known-wrong but now AGREES - remove it from KNOWN_WRONG)"
      failed=$((failed + 1))
    else
      echo "xfail $name (known stage1 bug)"
      xfail=$((xfail + 1))
    fi
    continue
  fi

  if [[ "$agree" == 1 ]]; then
    echo "ok   $name"
    passed=$((passed + 1))
  else
    echo "FAIL $name (stage1 disagrees with stage0):$why"
    diff "$work/e0.txt" "$work/e1.txt" 2>/dev/null | head -6 | sed 's/^/    /'
    failed=$((failed + 1))
  fi
done

echo
echo "$passed agree, $xfail known-wrong, $skipped skipped, $failed failed"
echo "$compared cases compared through both compilers at -O0 and -O2"

# A gate that quietly stops comparing reports the same silence as one
# that compares everything and finds nothing wrong. A glob that stops
# matching, a tree that moves, a skip list that grows - all of them look
# like success. The floor is well under the current count and refuses
# outright, the same guard `check-diagnostics.sh` carries for its sweep.
if [[ -z "$filter" && "$compared" -lt 90 ]]; then
  echo "FAIL compared only $compared cases (expected ~106): a tree or a glob is missing"
  failed=$((failed + 1))
fi

[[ "$failed" -eq 0 ]]
