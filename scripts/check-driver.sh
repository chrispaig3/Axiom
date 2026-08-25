#!/usr/bin/env bash
# The self-hosted compiler's command-line surface.
#
# No gate in this repository ever invoked a compiler DRIVER. Every one of
# them drives stage1 as `stage1 [FILE [TARGET]]` and runs `llc` and `cc`
# itself, so stage1's own `build` - the thing a user actually types - was
# exercised by nothing. That is the gap this closes, and it is the same
# shape as the gap that hid five miscompiles in `tests/stdlib/` and the
# libc-linking bug in `check-freestanding.sh`: a surface with no gate is
# a surface nobody has checked.
#
# The load-bearing cases are the NEGATIVE ones. A driver that ignores a
# child's exit status reports a failed `llc` as a successful build, and
# every positive test still passes. So this script poisons `PATH` in two
# directions and requires the two outcomes to differ - a failing tool
# must fail the build, and a MISSING `opt` must not.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

passed=0
failed=0
ok()   { echo "ok   $1"; passed=$((passed + 1)); }
bad()  { echo "FAIL $1"; failed=$((failed + 1)); }

gate_build_axc s1 "$work/axiom"

cd "$work"
cat >hello.ax <<'EOF'
(import IO)
(:: main Int)
;@axiom:effect(io)
(fn (main) { (println "driver-ok") 0 })
EOF
printf '(:: main Int)\n(fn (main) 17)\n' >ec.ax
printf '(:: main Int)\n(fn (main) (nope 1))\n' >bad.ax
printf '(:: main Int)\n(fn (main)\n' >unparsable.ax
printf '(import NoSuchModule)\n(:: main Int)\n(fn (main) 1)\n' >badimport.ax

# --- the surface -----------------------------------------------------

"$s1" --help >help.txt 2>&1 && grep -q 'USAGE:' help.txt \
  && ok "--help prints usage" || bad "--help"
"$s1" version >ver.txt 2>&1 && grep -q 'axiom' ver.txt \
  && ok "version prints a version" || bad "version"

"$s1" check hello.ax >/dev/null 2>&1 \
  && ok "check accepts a good program" || bad "check on a good program"

"$s1" build --input hello.ax --output hi >/dev/null 2>&1 \
  && [[ -x hi ]] && [[ "$(./hi)" == "driver-ok" ]] \
  && ok "build produces a working executable" || bad "build"

# Cleanup is part of the contract: a build that leaves a .o behind makes
# the next one ambiguous.
[[ ! -f hi.o && ! -f hi.ll && ! -f hi.opt.ll ]] \
  && ok "build removes its intermediates" || bad "build left intermediates behind"

"$s1" build --input hello.ax --output k --emit-llvm >/dev/null 2>&1
[[ -f k.ll && ! -f k.o ]] \
  && ok "--emit-llvm keeps the IR and still removes the object" || bad "--emit-llvm"

"$s1" emit-llvm hello.ax -o e.ll >/dev/null 2>&1 && grep -q 'define .*@main' e.ll \
  && ok "emit-llvm -o writes IR to a file" || bad "emit-llvm -o"

# The original spelling, which five other gates depend on.
"$s1" hello.ax >legacy.ll 2>/dev/null && grep -q 'define .*@main' legacy.ll \
  && ok "the legacy FILE spelling still emits IR to stdout" || bad "legacy spelling"
# Redirected to a file and then grepped, like the case above it, and
# NOT piped into `grep -q`. `set -o pipefail` is on; `grep -q` exits
# the moment it matches, and the triple is in the first few lines of
# ~75 KB of IR, so the compiler is still writing when the read end
# closes and dies of SIGPIPE - pipeline status 141, reported as a
# failing target selection. Measured at 4 failures in 8 runs on the
# compiler this was written against, so the case has been green by
# luck since it was added; a later change that merely altered the
# timing made it 8 in 8. The producer's status is the thing under
# test, so it must not be a pipeline's.
"$s1" hello.ax linux-x86_64 >legacy_t.ll 2>/dev/null
grep -q 'x86_64-unknown-linux-gnu' legacy_t.ll \
  && ok "the legacy FILE TARGET spelling still selects a target" || bad "legacy target"

# Global flags may precede the subcommand, because stage0's do and
# check-cross-targets.sh relies on it.
"$s1" --target=linux-aarch64 emit-llvm hello.ax -o g.ll >/dev/null 2>&1 \
  && grep -q 'aarch64-unknown-linux-gnu' g.ll \
  && ok "a global flag may precede the subcommand" || bad "flag before subcommand"

# --- exit codes ------------------------------------------------------
#
# Each has a distinct cause and a driver that collapses them sends the
# reader to the wrong place.

"$s1" run ec.ax >/dev/null 2>&1; [[ $? == 17 ]] \
  && ok "run propagates the program's own exit code" || bad "run exit code"

"$s1" build --input bad.ax --output nope >/dev/null 2>&1; [[ $? == 1 ]] && [[ ! -f nope ]] \
  && ok "a program that fails to check exits 1 and produces no binary" \
  || bad "failing check"

# A parse error exits 1, not 2, and no binary is left behind. It exited
# 2 until the parse-error port, which is the number stage0 never used:
# stage0 reports a syntax error as an ordinary diagnostic and exits 1,
# so the two compilers disagreed on the status of every unparseable
# file. Asserting the absent binary as well, because the status alone
# would also be satisfied by a build that failed for another reason.
"$s1" build --input unparsable.ax --output nope2 >/dev/null 2>&1
[[ $? == 1 ]] && [[ ! -f nope2 ]] \
  && ok "a parse error exits 1, like stage0, and produces no binary" \
  || bad "parse error exit code"

"$s1" build --input badimport.ax --output nope3 >/dev/null 2>&1; [[ $? == 1 ]] \
  && ok "an unresolvable import exits 1 (AX5001, stage0's code)" || bad "import exit code"

"$s1" build --input no-such-file.ax --output nope4 >err.txt 2>&1; rc=$?
[[ $rc == 1 ]] && grep -q 'no-such-file.ax' err.txt \
  && ok "an unreadable input exits 1 and names the file" || bad "unreadable input"

# --- the negative cases, which are the point -------------------------

mkdir -p fake fake-cc
printf '#!/bin/sh\nexit 1\n' >fake/llc && chmod +x fake/llc
PATH="$work/fake:$PATH" "$s1" build --input hello.ax --output f1 >f1.log 2>&1; rc=$?
# The message matters as much as the status, and asserting only the
# status does NOT discriminate: measured, a driver that ignores llc's
# exit code still fails this build, because `cc` is handed an object
# that was never written and fails downstream. The outcome is right for
# the wrong reason, and what the user sees is clang complaining about a
# missing `.o` instead of the compiler saying llc failed. So require
# the driver to blame the tool that actually failed.
# The wording is now the MESSAGE of an AX4003 diagnostic rather than a
# bare stderr write, so the code is required alongside it: a toolchain
# failure that named the right tool without a code would be the state
# this replaced.
if [[ $rc == 4 ]] && [[ ! -f f1 ]] && grep -q 'llc failed' f1.log \
   && grep -q 'AX4003' f1.log; then
  ok "a failing llc fails the build with exit 4, no executable, and names llc (AX4003)"
else
  bad "a failing llc (rc=$rc, blamed: $(head -1 f1.log))"
fi

# The same for `cc`, so each tool's status check is pinned by a case
# that only it can satisfy.
printf '#!/bin/sh\nexit 1\n' >fake-cc/cc && chmod +x fake-cc/cc
PATH="$work/fake-cc:$PATH" "$s1" build --input hello.ax --output f3 >f3.log 2>&1; rc=$?
if [[ $rc == 4 ]] && [[ ! -f f3 ]] && grep -q 'cc failed' f3.log \
   && grep -q 'AX4003' f3.log; then
  ok "a failing cc fails the build with exit 4, no executable, and names cc (AX4003)"
else
  bad "a failing cc (rc=$rc, blamed: $(head -1 f3.log))"
fi

# The two cases below are the only ones that REPLACE `PATH` rather than
# prepending to it, and a `PATH` that holds nothing but the tools under
# test withholds one more thing by accident: the C compiler's own.
#
# Apple's `cc` reaches the linker through an absolute path inside its
# toolchain, so darwin never noticed. GNU `cc` runs `collect2`, which
# looks for `ld` on `PATH` - so on both Linux targets these two cases
# failed with
#
#     collect2: fatal error: cannot find 'ld'
#     error[AX4003]: cc failed
#
# and the gate read the C toolchain coming apart as the driver's own
# failure. The driver was right in both: the `opt` case printed its
# warning first, which is the assertion, and then died on the link.
#
# Linking these in withholds nothing this script is testing. `opt` is
# still absent from the first case and all three tools are still absent
# from the empty first entry of the second; what is restored is only
# what `cc` needs to be `cc`.
# Says so when it cannot find one, rather than quietly reproducing the
# defect it exists to prevent: a linker named `ld.lld` on some future
# runner image would take these two cases straight back to `cc failed`
# with nothing on screen to say why.
link_cc_support() {
  local t p
  for t in ld as; do
    if p="$(command -v "$t")"; then
      ln -sf "$p" "$1/$t"
    else
      echo "note: no \`$t\` on PATH; \`cc\` may not be able to link in $1" >&2
    fi
  done
  return 0
}

# A `PATH` with llc and cc but no `opt`: must still build, must warn.
# stage2 compiling its own source needs opt's tail-call pass, so this
# has to be survivable rather than silently skipped or fatal.
mkdir -p only
for t in llc cc; do
  p="$(command -v $t)" && ln -sf "$p" "only/$t"
done
link_cc_support only
PATH="$work/only" "$s1" build --input hello.ax --output f2 >f2.log 2>&1; rc=$?
if [[ $rc == 0 ]] && [[ -x f2 ]] && [[ "$(./f2)" == "driver-ok" ]] \
   && grep -q 'opt' f2.log; then
  ok "a missing opt warns and still builds a working binary"
else
  bad "missing opt (rc=$rc)"
  sed 's/^/    /' f2.log | head -3
fi

# A `PATH` whose FIRST entry holds none of the tools. The driver
# searches `PATH` itself, and the search has to keep going past an entry
# that does not have what it is looking for.
#
# This is the shape that took the whole Linux half of CI down. Under
# `posix_spawn` a missing candidate fails before a process exists and
# answers `-ENOENT`, so the search moved on; under `fork`+`execve` the
# fork always succeeds, the failed `execve` is the CHILD's problem, and
# all the parent gets back is its exit status - 127, which is not
# negative, so the search stopped at the first entry and reported that
# as the tool's own exit code. `axiom build` on both Linux targets said
# `AX4003: cc failed` with no output from cc, because cc had never run.
#
# NOTE FOR ANYONE ABLATING THIS: it is vacuous on darwin and only
# discriminates on Linux, because the backend that had the bug is the
# one darwin cannot use (its `fork` returns two values and `__syscallN`
# yields one register). Reverting the fix and running this on macOS
# passes. That is a property of the defect, not a weak test.
mkdir -p empty late
for t in llc cc opt; do
  p="$(command -v $t)" && ln -sf "$p" "late/$t"
done
link_cc_support late
PATH="$work/empty:$work/late" "$s1" build --input hello.ax --output f4 >f4.log 2>&1; rc=$?
if [[ $rc == 0 ]] && [[ -x f4 ]] && [[ "$(./f4)" == "driver-ok" ]]; then
  ok "the tool search passes a PATH entry that does not have the tool"
else
  bad "PATH search stopped early (rc=$rc)"
  sed 's/^/    /' f4.log | head -3
fi

# ---------------------------------------------------------------
# Argument parsing: a boolean flag must not eat the file after it.
#
# The scan that finds the first positional used to skip TWO arguments
# for any flag without an `=`, on the assumption that every flag takes
# a value. Six do; the rest are booleans. So
#
#     axiom --emit-llvm prog.ax
#
# read `prog.ax` as the value of `--emit-llvm`, found no positional,
# and compiled the default `in.ax` - reporting `cannot read input:
# in.ax` about a file the user never typed, while their filename sat
# in argv.
#
# The assertion is about ARGV, not about any golden: whatever the
# compiler says, it must name the file it was given. A wrong answer
# here cannot be blessed away, because the expected string is built
# from the argument the test itself passed.
# `--input` is read by every subcommand that takes a file, not just
# `build`.
#
# `flagArity` is one table for the whole command line, so `--input` is
# paired with the argument after it for EVERY subcommand - that is what
# makes `--opt banana` fail before any work happens. But only `build`
# ever read the flag back: `check`, `emit-llvm` and `run` sought a bare
# positional, and the operand scan had already skipped the `--input FILE`
# pair, so the filename vanished between the validator and the
# subcommand and each reported "needs an input file" at exit 1 about a
# file the user had named. `fmt` and `symbols` reached it through a
# different walk - one that cannot use the general positional scan,
# because its flag-skipping would swallow the file in `fmt --check FILE`
# - and lost it the same way.
#
# The assertion is a DIFFERENTIAL against the spelling that always
# worked: `--input FILE` must give the same status and the same bytes as
# a bare FILE, for every subcommand that takes one. There is no golden
# here and nothing a re-bless could reach, because the expected output
# is whatever the other spelling produced in the same run.
for cmd in check emit-llvm symbols; do
  "$s1" "$cmd" hello.ax >i-bare.out 2>i-bare.err; arc=$?
  "$s1" "$cmd" --input hello.ax >i-flag.out 2>i-flag.err; brc=$?
  if [[ "$arc" == "$brc" ]] && cmp -s i-bare.out i-flag.out; then
    ok "\`$cmd --input FILE\` agrees with \`$cmd FILE\`"
  else
    bad "\`$cmd --input FILE\` (rc=$brc) differs from bare (rc=$arc): $(head -1 i-flag.err)"
  fi
done

# `fmt` takes its file through the flag-skipping walk, so it gets its own
# case rather than riding the loop: `--check` must still be a boolean and
# the file must still be found.
"$s1" fmt --check hello.ax >f-bare.out 2>&1; arc=$?
"$s1" fmt --check --input hello.ax >f-flag.out 2>&1; brc=$?
[[ "$arc" == "$brc" ]] && cmp -s f-bare.out f-flag.out \
  && ok "\`fmt --check --input FILE\` agrees with \`fmt --check FILE\`" \
  || bad "fmt --input (rc=$brc vs $arc)"

# `run` forwards everything after the file to the program, so the flag
# spelling must not change what the program receives.
"$s1" run --input hello.ax >r-flag.out 2>&1; brc=$?
"$s1" run hello.ax >r-bare.out 2>&1; arc=$?
[[ "$arc" == "$brc" ]] && cmp -s r-bare.out r-flag.out \
  && ok "\`run --input FILE\` agrees with \`run FILE\`" \
  || bad "run --input (rc=$brc vs $arc)"

for flag in --emit-llvm --check --builtins --list; do
  "$s1" "$flag" nosuch-$$.ax >p.out 2>p.err; rc=$?
  if grep -q "nosuch-$$\.ax" p.err; then
    ok "\`$flag FILE\` names FILE, not a default"
  elif grep -q 'in\.ax' p.err; then
    bad "\`$flag FILE\` swallowed the filename and reported in.ax (rc=$rc)"
  else
    bad "\`$flag FILE\` (rc=$rc) said: $(head -1 p.err)"
  fi
done

# The same flags, with a file that EXISTS, must actually compile it.
"$s1" --emit-llvm hello.ax >p2.out 2>p2.err; rc=$?
if [[ $rc == 0 ]] && grep -q '^target triple' p2.out; then
  ok "\`--emit-llvm FILE\` compiles FILE"
else
  bad "\`--emit-llvm FILE\` (rc=$rc): $(head -1 p2.err)"
fi

# No arguments at all: usage, not a complaint about a file nobody named.
"$s1" >n.out 2>n.err; rc=$?
if [[ $rc != 0 ]] && grep -q 'USAGE' n.err && ! grep -q 'in\.ax' n.err; then
  ok "a bare invocation prints usage and fails"
else
  bad "a bare invocation (rc=$rc) said: $(head -1 n.err)"
fi

# ---------------------------------------------------------------
# The entry point is the program's business, not the toolchain's.
#
# A file with no `main` used to reach codegen, which emits the argv
# wrapper's `call @__axiom_user_main` unconditionally, and the omission
# surfaced from `opt` as `use of undefined value '@__axiom_user_main'`
# against a `.ll` the driver had already deleted - exit 4, "a native
# tool failed", for a program that was simply missing its entry point.
# AX4001 was in the code table and in `axiom explain` the whole time
# with nothing constructing it.
#
# Asserting the CODE and the absence of the toolchain's noise, because
# the status alone does not discriminate: exit 1 is also what a failing
# check gives, and a driver that merely stopped earlier for some other
# reason would satisfy a status-only test.
printf '(:: helper (-> Int Int))\n(fn (helper x) x)\n' >nomain.ax
"$s1" build --input nomain.ax --output nm >nm.out 2>nm.err; rc=$?
if [[ $rc == 1 ]] && [[ ! -f nm ]] \
   && grep -q 'AX4001' nm.err \
   && grep -q 'no `main` function found' nm.err \
   && ! grep -q '__axiom_user_main' nm.err \
   && ! grep -q 'opt' nm.err; then
  ok "a program with no \`main\` is AX4001 and exit 1, not an llc error"
else
  bad "no-main (rc=$rc): $(head -1 nm.err)"
fi

# The help has to be actionable, since this is the commonest thing a
# newcomer gets wrong.
grep -q 'add `(:: main Int)`' nm.err \
  && ok "AX4001 says how to fix it" || bad "AX4001 help text"

# ...and it must NOT over-fire. These three surfaces analyse a module
# without producing an executable, so a library with no entry point is
# perfectly well-formed to them. The legacy no-subcommand spelling is
# the load-bearing one: check-diagnostics.sh sweeps every file in
# self_host/, stdlib/, stdlib/Sys/, tests/stdlib/ and tests/selfhost/
# through it and requires exit 0, and most of those modules have no
# `main` at all.
"$s1" check nomain.ax >/dev/null 2>&1 \
  && ok "\`check\` accepts a module with no \`main\`" || bad "check over-fires AX4001"
"$s1" emit-llvm nomain.ax >/dev/null 2>&1 \
  && ok "\`emit-llvm\` accepts a module with no \`main\`" || bad "emit-llvm over-fires AX4001"
"$s1" nomain.ax >legacy-nomain.ll 2>/dev/null && grep -q '^target triple' legacy-nomain.ll \
  && ok "the legacy spelling accepts a module with no \`main\`" \
  || bad "the legacy spelling over-fires AX4001 - check-diagnostics.sh sweeps main-less modules through it"

# ---------------------------------------------------------------
# An empty file is READ, not refused.
#
# `sysReadFile` answers "" for a missing file and for an empty one, so
# both reported `cannot read input` - a statement about the filesystem,
# and false for the second. An empty file is a module with no
# declarations: it checks clean, and only `build` rejects it, for the
# reason that is actually true.
: >empty.ax
"$s1" check empty.ax >e.out 2>e.err; rc=$?
if [[ $rc == 0 ]] && grep -q 'OK' e.out; then
  ok "an empty file checks clean"
else
  bad "empty file check (rc=$rc): $(head -1 e.err)"
fi
"$s1" build --input empty.ax --output ef >/dev/null 2>ef.err; rc=$?
if [[ $rc == 1 ]] && grep -q 'AX4001' ef.err; then
  ok "an empty file fails to BUILD, for want of an entry point"
else
  bad "empty file build (rc=$rc): $(head -1 ef.err)"
fi

# ---------------------------------------------------------------
# One spelling for an unreadable entry file, and it says WHY.
#
# There were three wordings - `cannot read input: F` from the compile
# path, `Failed to read file 'F'` from fmt and symbols, and nothing at
# all distinguishing a missing file from a directory - so which message
# a user saw depended on which subcommand they had typed, and none of
# them ever said whether the file was absent, unreadable, or a
# directory. The REASON is what pins this: no previous version printed
# one, so a re-blessed golden cannot satisfy it by accident.
for sub in "check" "fmt" "symbols"; do
  "$s1" $sub no-such-file.ax >/dev/null 2>r.err
  if grep -q "Failed to read file 'no-such-file.ax': No such file or directory" r.err; then
    ok "\`$sub\` names the file and the reason it could not be read"
  else
    bad "\`$sub\` read failure: $(head -1 r.err)"
  fi
done
"$s1" build --input no-such-file.ax --output x >/dev/null 2>r2.err
grep -q "Failed to read file 'no-such-file.ax': No such file or directory" r2.err \
  && ok "\`build\` uses the same wording" || bad "build read failure: $(head -1 r2.err)"

# A directory opens happily on both Darwin and Linux and fails at
# `read`, so it is the case a missing-file-only probe gets wrong.
mkdir -p adir
"$s1" check adir >/dev/null 2>d.err
grep -q "Failed to read file 'adir': Is a directory" d.err \
  && ok "a directory is reported as a directory" || bad "directory: $(head -1 d.err)"

# ---------------------------------------------------------------
# THE DATA LOSS. Two spellings of `fmt` used to rewrite the user's file
# and report success, because argument parsing could not say that an
# argument was not a flag it knew:
#
#   fmt --check=true F   `hasFlag` matched EXACTLY, so `--check=true`
#                        was not `--check`, and the arm fell through to
#                        the write path.
#   fmt F --help         `--help` was recognised only at argv[1].
#
# Both assertions are about the FILE, not about a message: whatever the
# compiler says, F must come back byte-identical. That cannot be blessed
# away, because the expected content is the input the test itself wrote.
printf '(:: main Int)\n(fn (main)   42)\n' >dl.ax
cp dl.ax dl.orig

"$s1" fmt --check=true dl.ax >dl1.out 2>dl1.err; rc=$?
if cmp -s dl.ax dl.orig && [[ $rc == 2 ]]; then
  ok "\`fmt --check=true FILE\` refuses and leaves FILE untouched"
else
  bad "\`fmt --check=true FILE\` (rc=$rc) rewrote the file or accepted it"
fi

cp dl.orig dl.ax
"$s1" fmt dl.ax --help >dl2.out 2>dl2.err; rc=$?
if cmp -s dl.ax dl.orig && [[ $rc == 0 ]] && grep -q 'axiom fmt' dl2.out; then
  ok "\`fmt FILE --help\` prints fmt's help and leaves FILE untouched"
else
  bad "\`fmt FILE --help\` (rc=$rc) rewrote the file or printed no help"
fi

# ---------------------------------------------------------------
# An unrecognised flag is an ERROR, not something stepped over.
#
# Skipping is indistinguishable from accepting, which is why
# `check --bogus f.ax` printed OK and exited 0, and why a mistyped
# `--diagnostic-formt=json` quietly produced human output.
"$s1" check --bogus hello.ax >u1.out 2>u1.err; rc=$?
if [[ $rc == 2 ]] && grep -q 'unrecognised flag' u1.err && grep -q 'bogus' u1.err; then
  ok "an unrecognised flag is refused, naming the flag"
else
  bad "unknown flag (rc=$rc): $(head -1 u1.err)"
fi

# A value flag at the end of argv with nothing after it.
"$s1" check hello.ax --target >u2.out 2>u2.err; rc=$?
[[ $rc == 2 ]] && grep -q 'value is required' u2.err \
  && ok "a value flag with no value is refused" || bad "missing flag value (rc=$rc)"

# ---------------------------------------------------------------
# A mistyped SUBCOMMAND is a subcommand error, not a file error.
#
# `axiom buidl f.ax` was read as the legacy `FILE TARGET` with
# FILE=`buidl`, so the answer was `cannot read input: buidl` and the
# user's real filename was discarded. `buidl`->`build` is a
# TRANSPOSITION, which plain Levenshtein scores as two edits, so this
# case is also what pins the suggestion threshold at 2 rather than 1.
"$s1" buidl hello.ax >tc.out 2>tc.err; rc=$?
if [[ $rc == 2 ]] && grep -q 'unrecognised subcommand' tc.err && grep -q 'build' tc.err; then
  ok "a mistyped subcommand is refused, and suggests the real one"
else
  bad "typo'd subcommand (rc=$rc): $(head -1 tc.err)"
fi

# ...but a real file that merely looks nothing like a command keeps the
# legacy reading, which is what the five harnesses depend on.
"$s1" hello.ax >lg.ll 2>/dev/null && grep -q '^target triple' lg.ll \
  && ok "a real file is still read as a file, not guessed at" || bad "legacy reading lost"

# ---------------------------------------------------------------
# `--gc` names a capability this compiler does not have.
#
# The retired compiler's tracing collector (1,098 lines, deleted with
# the crate) was not ported. The flag was neither implemented nor
# rejected, so `axiom --gc build ...` produced a bump-allocator binary
# and said nothing - while README.md, docs/reference.md and
# scripts/bench-datastructures.sh all still promised a collector. A
# silent downgrade of a memory-management request is the one failure its
# user cannot detect.
"$s1" --gc build --input hello.ax --output gcout >gc.out 2>gc.err; rc=$?
if [[ $rc == 2 ]] && grep -q 'gc' gc.err && [[ ! -f gcout ]]; then
  ok "\`--gc\` is refused by name rather than silently ignored"
else
  bad "--gc (rc=$rc): $(head -1 gc.err)"
fi

# ---------------------------------------------------------------
# Help, from anywhere, on stdout, exit 0.
for c in build check run test emit-llvm fmt explain symbols repl lsp; do
  "$s1" $c --help >h.out 2>h.err; rc=$?
  if [[ $rc == 0 ]] && grep -q "axiom $c" h.out; then
    ok "\`$c --help\` prints $c's help"
  else
    bad "\`$c --help\` (rc=$rc)"
  fi
done

# `axiom help <COMMAND>` answers for that command. The operand used to
# be read and discarded, printing the general usage - while the COMMANDS
# block promised this exact spelling. A usage text documenting behaviour
# the binary lacks is the same defect as an unconstructed diagnostic code.
for c in build fmt symbols; do
  "$s1" help $c >hc.out 2>&1
  grep -q "axiom $c" hc.out \
    && ok "\`help $c\` answers for $c" || bad "\`help $c\` printed the general usage"
done
"$s1" help nosuchthing >hn.out 2>&1; rc=$?
[[ $rc == 0 ]] && grep -q 'USAGE' hn.out \
  && ok "\`help\` with an unknown topic falls back to the general usage" \
  || bad "\`help nosuchthing\` (rc=$rc)"

# The usage text and the flag table must not drift apart: every flag the
# compiler accepts has to appear in `axiom --help`. Without this the two
# have already diverged once - `repl` was dispatched but missing from
# COMMANDS, and `--check`, `--builtins`, `--list` and `--no-banner` were
# accepted but documented nowhere.
"$s1" --help >full-help.txt 2>&1
missing=""
for f in --input --output -o --target --opt --emit-llvm --check --builtins \
         --list --no-banner --filter --diagnostic-format --help --version; do
  grep -q -- "$f" full-help.txt || missing="$missing $f"
done
for c in build check run test emit-llvm fmt explain symbols repl lsp version help; do
  grep -q -- "  $c" full-help.txt || missing="$missing cmd:$c"
done
[[ -z "$missing" ]] && ok "every accepted flag and command appears in --help" \
  || bad "undocumented in --help:$missing"

# `-o` is the short form of `--output` under `build` too. Only
# `emit-llvm` read it, so `axiom build -o prog f.ax` consumed `prog` as
# a flag value and wrote the default `output` - while the usage text
# listed `-o <PATH>` with no qualification.
rm -f oprog output
"$s1" build -o oprog hello.ax >ob.out 2>ob.err; rc=$?
if [[ $rc == 0 ]] && [[ -x oprog ]]; then
  ok "\`build -o PATH\` writes the executable to PATH"
else
  bad "build -o (rc=$rc, wrote $(ls output 2>/dev/null || echo nothing))"
fi

# `--opt` refuses a value it cannot honour instead of silently using 1,
# in both spellings.
for bad_opt in banana 9 300 ""; do
  "$s1" build --input hello.ax --output oo --opt "$bad_opt" >oo.out 2>oo.err; rc=$?
  [[ $rc == 2 ]] \
    && ok "\`--opt $bad_opt\` is refused rather than silently building at -O1" \
    || bad "\`--opt $bad_opt\` (rc=$rc) was accepted"
done
"$s1" build --input hello.ax --output oo --opt=banana >/dev/null 2>&1; [[ $? == 2 ]] \
  && ok "\`--opt=banana\` is refused too" || bad "--opt= form not validated"

# ...and it is refused BEFORE the compiler does the work, which is the
# whole point of validating the command line in one pass. `--opt` used
# to be parsed where it is USED - in `build`, after `compileFile` has
# already run - so a command line that was wrong in two ways reported
# the type error first and the bad flag only on the next run, after the
# user had fixed the other thing.
printf '(:: main Int)\n(fn (main) (nope 1))\n' >badopt.ax
"$s1" build --input badopt.ax --output x --opt banana >bo.out 2>bo.err; rc=$?
if [[ $rc == 2 ]] && grep -q 'opt' bo.err && ! grep -q 'AX3001' bo.err; then
  ok "a bad flag is refused before the file is compiled"
else
  bad "flag/compile ordering (rc=$rc): $(head -1 bo.err)"
fi
rm -f oo
"$s1" build --input hello.ax --output oo --opt 2 >/dev/null 2>&1 && [[ -x oo ]] \
  && ok "a valid --opt still builds" || bad "--opt 2 regressed"

# `-V` is the short form of `--version`, and `--` really ends option
# parsing. Both were listed in the usage text before they worked: `-V`
# printed the whole usage to stderr and exited 1, and `--` was accepted
# by the validator and then ignored by the operand scan, so
# `axiom check -- -weird.ax` still answered "check needs an input file".
# A flag the help documents and the binary ignores is the same defect as
# a diagnostic code nothing constructs.
"$s1" -V >v.out 2>v.err; rc=$?
[[ $rc == 0 ]] && grep -q 'axiom' v.out \
  && ok "\`-V\` prints the version" || bad "\`-V\` (rc=$rc)"

printf '(:: main Int)\n(fn (main) 1)\n' >./-weird.ax
for sub in check symbols; do
  "$s1" $sub -- -weird.ax >w.out 2>w.err; rc=$?
  [[ $rc == 0 ]] \
    && ok "\`$sub -- -weird.ax\` reaches a file whose name begins with a dash" \
    || bad "\`$sub --\` (rc=$rc): $(head -1 w.err)"
done
# A LEADING-DASH code, which is the case only `--` can reach.
# `explainNormalize` has always stripped leading dashes so that
# `AX-3001` and `-3001` resolve, but nothing could deliver such a code
# to it: the operand scan skipped any argument beginning with `-`. The
# normaliser's dash-stripping was unreachable until now, and a plain
# `explain -- 3001` would not have shown it, because that spelling
# already worked by accident.
"$s1" explain -- -3001 >x.out 2>&1
grep -q 'AX3001' x.out \
  && ok "\`explain -- -CODE\` reaches a code written with a leading dash" \
  || bad "explain -- -3001: $(head -1 x.out)"

# ---------------------------------------------------------------
# `run` forwards what follows the file to the PROGRAM.
#
# It used to pass only the program's own name, so a program that reads
# argv could not be given any arguments at all. Asserted numerically
# through the program's own exit status, so no golden can bless it.
cat >argc.ax <<'EOF'
(import Sys)
(:: main Int)
(fn (main) (sysArgc))
EOF
"$s1" run argc.ax >/dev/null 2>&1; [[ $? == 1 ]] \
  && ok "run with no arguments gives the program argc 1" || bad "run argc baseline"
"$s1" run argc.ax alpha beta >/dev/null 2>&1; [[ $? == 3 ]] \
  && ok "run forwards its trailing arguments to the program" || bad "run does not forward arguments"
"$s1" run argc.ax -- --verbose x >/dev/null 2>&1; [[ $? == 3 ]] \
  && ok "run passes dash-prefixed arguments through after \`--\`" || bad "run \`--\` passthrough"

# A forwarded argument that happens to spell one of the COMPILER's own
# flags is still the program's.
#
# `run`'s input file came from `inputOperand`, which asks `flagValue`
# for `--input` across the whole of argv with no idea where the
# compiler's own arguments stop - while `runArgv` forwards from the
# first positional onward. The two disagreed, so
# `axiom run prog.ax --input other.ax` compiled and ran `other.ax`,
# silently, at exit 0, and `--` did not stop it because that scan never
# looked for one. A program forwarding its own arguments cannot be
# asked to avoid this compiler's flag spellings. Found 2026-08-16.
#
# Asserted through exit status again: `seven.ax` and `fortytwo.ax`
# answer different numbers, so the number IS which file got compiled.
cat >seven.ax <<'EOF'
(:: main Int)
(fn (main) 7)
EOF
cat >fortytwo.ax <<'EOF'
(:: main Int)
(fn (main) 42)
EOF
"$s1" run seven.ax --input fortytwo.ax >/dev/null 2>&1; [[ $? == 7 ]] \
  && ok "run compiles its own operand, not a forwarded \`--input\`" \
  || bad "run compiled the file named by a forwarded \`--input\`"
"$s1" run seven.ax -- --input fortytwo.ax >/dev/null 2>&1; [[ $? == 7 ]] \
  && ok "run ignores a forwarded \`--input\` after \`--\` too" \
  || bad "run \`--\` did not stop the \`--input\` scan"
# The flag spelling still names the file when no operand does - there is
# nothing after it that could have been a program argument.
"$s1" run --input fortytwo.ax >/dev/null 2>&1; [[ $? == 42 ]] \
  && ok "\`run --input FILE\` still names the file" || bad "run --input regressed"
# And the forwarded flag reaches the program rather than being eaten.
"$s1" run argc.ax --input x >/dev/null 2>&1; [[ $? == 3 ]] \
  && ok "a forwarded \`--input\` counts as the program's own argument" \
  || bad "forwarded \`--input\` did not reach the program"

# ---------------------------------------------------------------
# A successful command says so, and names what it produced.
"$s1" build --input hello.ax --output bs >bs.out 2>&1
grep -q 'Build successful: bs' bs.out \
  && ok "a successful build names the executable it wrote" || bad "build success line"

rm -f eo.ll
"$s1" emit-llvm hello.ax --output eo.ll >eo.out 2>eo.err; rc=$?
if [[ $rc == 0 ]] && [[ -s eo.ll ]] && grep -q 'LLVM IR written to eo.ll' eo.out; then
  ok "\`emit-llvm --output\` writes the file and says where"
else
  bad "emit-llvm --output (rc=$rc, file $( [[ -s eo.ll ]] && echo written || echo MISSING))"
fi

# ---------------------------------------------------------------
# An IMPORTED module that does not parse.
#
# This used to print `error: cannot parse module: Broken` on fd 2 and
# exit 3 - no code, no span, no snippet, and byte-identical under
# `--diagnostic-format=json` - while checking that same file DIRECTLY
# gave a complete AX2002 with file, line, column, caret and help at
# exit 1. The information was held by the caller and thrown away.
#
# The broken module is written HERE rather than checked in, because
# `check-fmt.sh` and `check-tree-sitter.sh` sweep every `*.ax` in the
# repository and require it to parse - a file that deliberately does
# not parse has to be `.axbad`, and an `.axbad` is not a name the
# module resolver will ever find.
#
# The load-bearing assertion is the LAST one: that the diagnostic an
# importer gets is byte-for-byte the diagnostic the module itself
# gets. Asserting only "exit 1" or "says AX2002" would be satisfied by
# any refusal, and the defect was never that it failed to refuse.
printf '(pub :: helper (-> Int Int))\n(pub fn (helper x) (* x\n' > Broken.ax
printf '(import Broken)\n(:: main Int)\n(fn (main) (helper 4))\n' > useBroken.ax

"$s1" check useBroken.ax >/dev/null 2>ib.err; rc=$?
[[ $rc == 1 ]] \
  && ok "an unparseable import exits 1, like every other diagnostic" \
  || bad "unparseable import exit status (got $rc, want 1)"

"$s1" --diagnostic-format=ai check useBroken.ax >/dev/null 2>ib.axdl
grep -q '^E AX2002 Broken.ax:' ib.axdl \
  && ok "an unparseable import carries its code and the module's own span" \
  || bad "unparseable import AXDL ($(head -c 90 ib.axdl))"

"$s1" --diagnostic-format=ai check Broken.ax >/dev/null 2>direct.axdl
cmp -s ib.axdl direct.axdl \
  && ok "the importer's diagnostic is the module's diagnostic, byte for byte" \
  || bad "importer and direct check disagree$(diff direct.axdl ib.axdl | head -2 | tr '\n' ' ')"

"$s1" --diagnostic-format=json check useBroken.ax >/dev/null 2>ib.json
grep -q '"code":"AX2002"' ib.json \
  && ok "and it honours --diagnostic-format" \
  || bad "unparseable import ignores --diagnostic-format"

# --- a byte order mark --------------------------------------------------
#
# A file a BOM-emitting editor saved begins with EF BB BF, and until
# 2026-08-21 that was AX1001 `unexpected character` at 1:1, pointing
# at a character nothing displays (the QA sweep). The mark is skipped
# at the lexer's entry and ignored by both column counters, so the
# same program with and without it must check, build, run, and report
# a line-1 diagnostic at the same column. This lives here and not in
# a corpus directory on purpose: check-self-host.sh reads `; expect N`
# off a case's first bytes, check-tree-sitter.sh parses every `.ax`
# with a grammar that knows no BOM, and the span verifier counts the
# mark as a character - each of which would be pinning the fixture's
# encoding rather than the compiler's behaviour.
printf '\xEF\xBB\xBF' >bom.ax; cat hello.ax >>bom.ax
"$s1" check bom.ax >/dev/null 2>&1 \
  && ok "a leading byte order mark is skipped" || bad "check refuses a BOM file"
"$s1" build --input bom.ax --output bomhi >/dev/null 2>&1 \
  && [[ "$(./bomhi)" == "driver-ok" ]] \
  && ok "and the program behind it builds and runs" || bad "build of a BOM file"
printf '(fn (main) (nope 1))\n(:: main Int)\n' >bad1.ax
printf '\xEF\xBB\xBF' >bombad1.ax; cat bad1.ax >>bombad1.ax
"$s1" --diagnostic-format=ai check bad1.ax >/dev/null 2>bad1.axdl
"$s1" --diagnostic-format=ai check bombad1.ax >/dev/null 2>bombad1.axdl
grep -q '^E AX3001 bad1.ax:1:13-17 ' bad1.axdl \
  && [[ "$(sed 's/bombad1/bad1/' bombad1.axdl)" == "$(cat bad1.axdl)" ]] \
  && ok "a line-1 diagnostic reports the same column with the mark as without" \
  || bad "BOM shifts columns: $(head -1 bombad1.axdl | cut -c1-60)"
# The human renderer's caret counts the mark as zero columns too: the
# two carets must sit at the same offset from the gutter.
"$s1" check bad1.ax >/dev/null 2>bad1.human
"$s1" check bombad1.ax >/dev/null 2>bombad1.human
[[ "$(grep -c '\^' bad1.human)" -ge 1 ]] \
  && [[ "$(grep '\^' bad1.human | sed 's/\x1b\[[0-9;]*m//g')" == "$(grep '\^' bombad1.human | sed 's/\x1b\[[0-9;]*m//g')" ]] \
  && ok "and the human caret lands under the same character" \
  || bad "BOM shifts the human caret"
# `fmt` keeps the mark: it scans with its own scanner, which refused
# the file until 2026-08-21, and now lifts the mark off, formats, and
# puts it back - so a formatted BOM file still begins with the mark
# and `--check` on it is a fixed point.
printf '\xEF\xBB\xBF(import IO)\n(:: main Int)\n;@axiom:effect(io)\n(fn (main)   {   (println "driver-ok")   0 })\n' >bomfmt.ax
"$s1" fmt bomfmt.ax >/dev/null 2>&1 \
  && [[ "$(head -c 3 bomfmt.ax | od -An -tx1 | tr -d ' \n')" == "efbbbf" ]] \
  && "$s1" fmt --check bomfmt.ax >/dev/null 2>&1 \
  && "$s1" build --input bomfmt.ax --output bomfmtbin >/dev/null 2>&1 \
  && [[ "$(./bomfmtbin)" == "driver-ok" ]] \
  && ok "fmt formats a BOM file, keeps the mark, and is a fixed point on it" \
  || bad "fmt on a BOM file: $("$s1" fmt --check bomfmt.ax 2>&1 | head -1)"
# Not a leading mark, not skipped: the same bytes anywhere else are
# still an unexpected character.
printf '(:: main Int)\n(fn (main) \xEF\xBB\xBF 0)\n' >midbom.ax
"$s1" --diagnostic-format=ai check midbom.ax >/dev/null 2>midbom.axdl
# `LC_ALL=C`: the message quotes the offending byte, and a UTF-8
# locale's grep declines to search a line it cannot decode.
LC_ALL=C grep -q '^E AX1001 midbom.ax:2:12' midbom.axdl \
  && ok "a mark that is not leading is still AX1001" \
  || bad "mid-file BOM: $(head -c 60 midbom.axdl)"

# ---------------------------------------------------------------
# THE VERSION IS WRITTEN DOWN FIFTEEN TIMES AND NOTHING COMPARED THEM.
#
# `version prints a version` above greps for the word `axiom` and would
# pass on `axiom 9.9.9`. The number itself lives in
# `self_host/main.ax`, `self_host/repl.ax` and `self_host/lsp.ax` as
# three independent string literals, in `rust/Cargo.toml` four more
# times, and in eight `tests/lsp/*.golden` files that pin what the
# language server reports over the wire. They agree today. Nothing was
# keeping them that way, and the first one to drift would be the LSP's
# `serverInfo`, because it is the only one a human never reads.
#
# There is no single-sourcing available here: an Axiom string literal
# and a TOML key cannot be the same object, so agreement IS the
# property, and a gate is the only thing that can hold it.
#
# THE DRIVER'S NUMBER IS TAKEN FROM WHAT THE BINARY PRINTS rather than
# from its source, for the same reason `check-platform-constants.sh`
# reads emitted IR: the source is one more copy, and the copy that
# matters is the one a user sees.
# ---------------------------------------------------------------
ver_from_binary="$("$s1" version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
if [[ -z "$ver_from_binary" ]]; then
  bad "version: the binary prints no semver at all, so nothing can be compared to it"
else
  ok "version: the binary prints $ver_from_binary"
  ver_bad=0
  ver_seen=0
  ver_check() {  # name, file, extracted value
    ver_seen=$((ver_seen + 1))
    if [[ -z "$3" ]]; then
      bad "version: found no version in $2 - the pattern this gate greps with has stopped matching, which is how a count gate dies without saying so"
      ver_bad=$((ver_bad + 1))
    elif [[ "$3" != "$ver_from_binary" ]]; then
      bad "version: $1 says $3, the binary prints $ver_from_binary ($2)"
      ver_bad=$((ver_bad + 1))
    fi
  }
  ver_check "the REPL banner" "self_host/repl.ax" \
    "$(grep -oE 'axiom \(self-hosted\) [0-9]+\.[0-9]+\.[0-9]+' "$repo_root/self_host/repl.ax" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  ver_check "the LSP serverInfo" "self_host/lsp.ax" \
    "$(grep -oE '"version" \(jsonStr "[0-9]+\.[0-9]+\.[0-9]+"' "$repo_root/self_host/lsp.ax" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  ver_check "the crate version" "rust/Cargo.toml" \
    "$(awk '/^\[(workspace\.)?package\]/{p=1;next} /^\[/{p=0} p&&/^version *=/{print;exit}' "$repo_root/rust/Cargo.toml" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

  # The eight LSP goldens are what the server actually answered when
  # they were blessed, so they are evidence rather than another copy -
  # and they are the reason a drifted `serverInfo` would be caught
  # twice. Counted, so a golden that stops carrying a version is a
  # failure and not a silently smaller sweep.
  lsp_goldens=0
  for gfile in "$repo_root"/tests/lsp/*.golden; do
    [[ -f "$gfile" ]] || continue
    gv="$(grep -oE '"version":"[0-9]+\.[0-9]+\.[0-9]+"' "$gfile" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    [[ -z "$gv" ]] && continue
    lsp_goldens=$((lsp_goldens + 1))
    if [[ "$gv" != "$ver_from_binary" ]]; then
      bad "version: $(basename "$gfile") pins $gv, the binary prints $ver_from_binary"
      ver_bad=$((ver_bad + 1))
    fi
  done
  if [[ "$lsp_goldens" -lt 8 ]]; then
    bad "version: only $lsp_goldens LSP goldens carry a version; 8 did when this gate landed - either the server stopped reporting one or the sweep stopped finding it"
    ver_bad=$((ver_bad + 1))
  fi
  [[ "$ver_bad" == 0 ]] \
    && ok "version: $ver_seen source(s) and $lsp_goldens LSP golden(s) all agree on $ver_from_binary"
fi

# ---------------------------------------------------------------
# AN INSTALLED LAYOUT, FOUND ON PATH.
#
# Every other case in this file invokes the compiler by a path -
# `"$s1"` is absolute - and so did `scripts/install.sh`'s own
# post-install check and `release.yml`'s archive check. That is the ONE
# invocation form in which locating the standard library cannot fail,
# which is why the form a user actually adopts was broken and no gate
# said so.
#
# What a user does is what `install.sh` prints: put `<prefix>/bin` on
# PATH and type `axiom`. The shell then passes the BARE NAME as argv[0],
# `(pathDir (sysArg 0))` is empty, and `<exe>/../stdlib` degenerated
# into a working-directory-relative `../stdlib`. On a completely
# correct installation the first program importing anything answered
# `AX5001 cannot resolve import IO`.
#
# Both directions are asserted, because only the pair is evidence: the
# positive is an installed layout resolving its own stdlib through a
# bare-name invocation, and the NEGATIVE is the same invocation with
# the stdlib removed, which must still fail. Without the negative this
# case would pass on a compiler that found some other stdlib - the
# repository's own, four directories up - and report the property it
# was written to check while not checking it.
#
# `AXIOM_STDLIB` is unset throughout. It is the documented override and
# it makes every case here pass vacuously.
# ---------------------------------------------------------------
inst="$work/inst"
mkdir -p "$inst/bin"
cp "$s1" "$inst/bin/axiom"
cp -R "$repo_root/stdlib" "$inst/stdlib"

mkdir -p "$work/away"
cat >"$work/away/useio.ax" <<'EOF'
(import IO (writeStr))
(:: main Int)
;@axiom:effect(io)
(fn (main) { (writeStr 1 "installed-ok\n") 42 })
EOF

# The probe directory must not itself supply a stdlib, or the
# compiler's last-resort working-directory entry answers instead.
if [[ -e "$work/away/stdlib" || -e "$work/stdlib" ]]; then
  bad "installed layout: the probe directory has a stdlib of its own, so this case cannot mean anything"
else
  (
    cd "$work/away"
    unset AXIOM_STDLIB AXIOM_PATH
    PATH="$inst/bin:$PATH" axiom build --input useio.ax --output useio
  ) >"$work/inst.log" 2>&1
  if [[ $? -eq 0 && -x "$work/away/useio" ]] \
    && [[ "$("$work/away/useio")" == "installed-ok" ]]; then
    ok "installed layout: bin/ + stdlib/ resolves through a bare-name PATH invocation"
  else
    bad "installed layout: \`axiom\` found on PATH could not build a program that imports IO"
    sed 's/^/     /' "$work/inst.log" | head -8
  fi

  # The negative. Same compiler, same program, same invocation, with
  # the archive's stdlib taken away: this MUST fail, or the positive
  # above was resolving something other than the installation.
  rm -rf "$inst/stdlib" "$work/away/useio"
  (
    cd "$work/away"
    unset AXIOM_STDLIB AXIOM_PATH
    PATH="$inst/bin:$PATH" axiom build --input useio.ax --output useio
  ) >"$work/inst-neg.log" 2>&1
  if [[ $? -ne 0 ]] && grep -q 'AX5001' "$work/inst-neg.log"; then
    ok "installed layout: removing stdlib/ makes the same invocation fail (AX5001)"
  else
    bad "installed layout: the compiler built a stdlib-importing program with NO stdlib installed - the positive case above proves nothing"
    sed 's/^/     /' "$work/inst-neg.log" | head -8
  fi
fi

echo
echo "$passed passed, $failed failed"
[[ "$failed" == 0 ]]
