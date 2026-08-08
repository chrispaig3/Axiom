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

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
[[ -x "$axiom" ]] || cargo build --release
export AXIOM_STDLIB="$repo_root/stdlib"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

passed=0
failed=0
ok()   { echo "ok   $1"; passed=$((passed + 1)); }
bad()  { echo "FAIL $1"; failed=$((failed + 1)); }

s1="$work/axiom"
if ! "$axiom" build --input self_host/main.ax --output "$s1" >"$work/build.log" 2>&1; then
  sed 's/^/    /' "$work/build.log" | head -5 >&2
  echo "FAIL could not build the self-hosted compiler" >&2
  exit 1
fi

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
"$s1" hello.ax linux-x86_64 2>/dev/null | grep -q 'x86_64-unknown-linux-gnu' \
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

"$s1" build --input unparsable.ax --output nope2 >/dev/null 2>&1; [[ $? == 2 ]] \
  && ok "a parse error exits 2" || bad "parse error exit code"

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
if [[ $rc == 4 ]] && [[ ! -f f1 ]] && grep -q 'llc failed' f1.log; then
  ok "a failing llc fails the build with exit 4, no executable, and names llc"
else
  bad "a failing llc (rc=$rc, blamed: $(head -1 f1.log))"
fi

# The same for `cc`, so each tool's status check is pinned by a case
# that only it can satisfy.
printf '#!/bin/sh\nexit 1\n' >fake-cc/cc && chmod +x fake-cc/cc
PATH="$work/fake-cc:$PATH" "$s1" build --input hello.ax --output f3 >f3.log 2>&1; rc=$?
if [[ $rc == 4 ]] && [[ ! -f f3 ]] && grep -q 'cc failed' f3.log; then
  ok "a failing cc fails the build with exit 4, no executable, and names cc"
else
  bad "a failing cc (rc=$rc, blamed: $(head -1 f3.log))"
fi

# A `PATH` with llc and cc but no `opt`: must still build, must warn.
# stage2 compiling its own source needs opt's tail-call pass, so this
# has to be survivable rather than silently skipped or fatal.
mkdir -p only
for t in llc cc; do
  p="$(command -v $t)" && ln -sf "$p" "only/$t"
done
PATH="$work/only" "$s1" build --input hello.ax --output f2 >f2.log 2>&1; rc=$?
if [[ $rc == 0 ]] && [[ -x f2 ]] && [[ "$(./f2)" == "driver-ok" ]] \
   && grep -q 'opt' f2.log; then
  ok "a missing opt warns and still builds a working binary"
else
  bad "missing opt (rc=$rc)"
  sed 's/^/    /' f2.log | head -3
fi

echo
echo "$passed passed, $failed failed"
[[ "$failed" == 0 ]]
