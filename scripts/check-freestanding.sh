#!/usr/bin/env bash
# Assert that Axiom's generated code needs no C library.
#
# This is the property that distinguishes an Axiom-native standard
# library from a set of thin wrappers around libc, and it is invisible in
# program output: a `printf`-backed `println` prints exactly the same
# bytes. So it gets its own check, at two levels:
#
#   1. the generated LLVM IR contains no call to a libc function, and
#   2. the linked executable imports no libc symbol.
#
# (2) is the stronger claim but is checked leniently on macOS, where the
# system linker always records a dependency on `libSystem` for the C
# runtime startup stub even when nothing in the program calls into it;
# there, the check is that no *libc function* is imported, not that no
# library is linked.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

# Names that only ever belong to C. Axiom's own standard library defines
# `exit`, `write`, and `read`, which compile to calls on Axiom functions
# of those names, so listing them here would flag the replacement code
# itself.
#
# The process-control family joined the list when `Sys` learned to spawn
# children. That capability is the one place where reaching for libc is
# genuinely tempting - `posix_spawn` is a function, not a syscall, on
# every system that documents it - and until these names were listed the
# gate could not tell the raw-syscall implementation from the forbidden
# one: a `(foreign posix_spawn ...)` binding emitted `call i64
# @posix_spawn(...)`, linked against libc, and passed both the IR grep
# and the `nm` check. Verified before adding them.
#
# `foreign` has since been removed from the language, so nothing can
# emit such a call any more. The list stays: it is what would notice a
# BACKEND that started lowering something to a libc name, which is a
# different door from the source-level one, and the last probe below is
# what keeps the source-level one shut.
libc_names='printf|puts|malloc|calloc|realloc|free|strlen|strcmp|fopen|fwrite|fread'
libc_names="$libc_names"'|fork|vfork|execv|execve|execvp|execl|execlp|posix_spawn|posix_spawnp'
libc_names="$libc_names"'|wait|waitpid|wait3|wait4|system|popen|pclose|getenv|setenv|pipe|dup2'
# The mem/str family. The stage1 paragraph below records the measured
# bug as "linked against `_strlen` and `_memset`" - and `memset` was
# never on this list, so of the two symbols that motivated the stage1
# pass only ONE could ever have been caught. Found 2026-08-16: an
# executable importing `_memset` or `_bzero` got a green `ok`.
#
# These are the names the loop-idiom recogniser reaches for, which is
# the exact door the stage1 pass exists to watch: it rewrites a byte
# loop into `strlen`, a zeroing loop into `memset`, and a copy loop
# into `memcpy`. None of them is defined by Axiom's stdlib, so unlike
# `exit`/`write`/`read` there is no replacement code to flag.
libc_names="$libc_names"'|memset|memcpy|memmove|memcmp|memchr|bzero|bcopy'
libc_names="$libc_names"'|strcpy|strncpy|strcat|strncat|strncmp|strchr|strrchr|strstr|strdup'

status=0

for case_file in tests/stdlib/*.ax; do
  name="$(basename "$case_file" .ax)"

  ir="$work/$name.ll"
  "$axiom" emit-llvm "$case_file" -o "$ir" > /dev/null

  if grep -nE "call[^\"]*@($libc_names)\(" "$ir" > "$work/$name.hits"; then
    echo "FAIL $name: generated IR calls libc"
    sed 's/^/    /' "$work/$name.hits"
    status=1
    continue
  fi

  # The INTRINSIC spelling of the same thing, which the pattern above
  # structurally cannot match: `@llvm.memset.p0.i64` does not begin
  # with `memset` after the `@`, so adding the name to `libc_names`
  # would not have found it either. An `llvm.mem*` intrinsic is not a
  # libc call in the IR, but the backend lowers anything it cannot
  # expand inline into one - so a program can arrive at `memcpy` with
  # no libc name appearing in the IR at any point.
  if grep -nE "@llvm\.(memset|memcpy|memmove)\." "$ir" > "$work/$name.intr"; then
    echo "FAIL $name: generated IR uses an llvm.mem* intrinsic, which lowers to libc"
    sed 's/^/    /' "$work/$name.intr"
    status=1
    continue
  fi

  exe="$work/$name.bin"
  "$axiom" build --input "$case_file" --output "$exe" > /dev/null

  case "$(uname -s)" in
    Darwin) imports="$(nm -u "$exe" 2>/dev/null | sed 's/^_//' || true)" ;;
    *)      imports="$(nm -D --undefined-only "$exe" 2>/dev/null | awk '{print $NF}' || true)" ;;
  esac

  if printf '%s\n' "$imports" | grep -qE "^($libc_names)$"; then
    echo "FAIL $name: executable imports libc symbols"
    printf '%s\n' "$imports" | grep -E "^($libc_names)$" | sed 's/^/    /'
    status=1
    continue
  fi

  echo "ok   $name (no libc in IR or imports)"
done

# The same corpus, compiled by the SELF-HOSTED compiler.
#
# Nothing ever ran this gate against stage1's output, and a real bug was
# living in that gap: `opt` rewrites a byte loop into a call to `strlen`
# when it can, and it can on stage1's register/phi IR while it cannot on
# stage0's alloca form. Measured before the fix - a stage1-built
# `010-hello.ax` grew 17 `strlen` references under `opt -O1` and linked
# against `_strlen` and `_memset`. Every case failed; the gate was green
# because it only ever asked stage0.
#
# The freestanding contract belongs to the language, not to one backend,
# so both compilers have to answer for it. This also exercises stage1's
# own driver end to end, which is the only place in the gates that does.
if [[ "${AXIOM_SKIP_STAGE1:-0}" != 1 ]]; then
  s1="$work/stage1"
  if "$axiom" build --input self_host/main.ax --output "$s1" >"$work/s1.log" 2>&1; then
    s1_checked=0
    for case_file in tests/stdlib/*.ax; do
      name="$(basename "$case_file" .ax)"
      exe="$work/s1-$name"
      if ! "$s1" build --input "$repo_root/$case_file" --output "$exe" \
           >"$work/s1-$name.log" 2>&1; then
        echo "FAIL $name: the self-hosted compiler could not build it"
        sed 's/^/    /' "$work/s1-$name.log" | head -3
        status=1
        continue
      fi
      case "$(uname -s)" in
        Darwin) imports="$(nm -u "$exe" 2>/dev/null | sed 's/^_//' || true)" ;;
        *)      imports="$(nm -D --undefined-only "$exe" 2>/dev/null | awk '{print $NF}' || true)" ;;
      esac
      if printf '%s\n' "$imports" | grep -qE "^($libc_names)$"; then
        echo "FAIL $name: an executable built by the SELF-HOSTED compiler imports libc"
        printf '%s\n' "$imports" | grep -E "^($libc_names)$" | sed 's/^/    /'
        status=1
        continue
      fi
      s1_checked=$((s1_checked + 1))
    done
    # A loop that silently stopped matching would report the silence it
    # was looking for, so say how many it actually read.
    echo "ok   $s1_checked cases built by the self-hosted compiler import no libc"
    [[ "$s1_checked" -ge 30 ]] || { echo "FAIL only $s1_checked cases reached the stage1 pass"; status=1; }
  else
    echo "FAIL could not build the self-hosted compiler for the stage1 pass"
    sed 's/^/    /' "$work/s1.log" | head -5
    status=1
  fi
fi

# ---------------------------------------------------------------
# Negative probes: the IR check can still fail, and the language has
# no way to ask for a libc call in the first place.
#
# A gate that has never been seen to fail is a gate nobody has checked.
# Everything above asserts SILENCE - no libc in any case - and silence
# is exactly what a broken grep, an empty corpus, or a mistyped
# alternation also produces.
#
# This used to be one probe, an Axiom program built on
# `(foreign posix_spawn ...)`, and it worked because `foreign` emitted
# `call i64 @posix_spawn(...)` verbatim. `foreign` has been removed -
# it named a symbol the emitted module never declared, so every
# program that used one passed `check` and then died in `opt` - and
# with it went the only construct that could name an external symbol
# at all. A probe cannot be written in Axiom any more.
#
# That is a strictly better world and a strictly worse test, so the
# two halves it used to prove at once are now proved separately.
# ---------------------------------------------------------------

# 1. The forbidden-name list catches what it claims to, checked against
#    IR lines this script writes itself - one per name in the list, not
#    just the one a probe happened to call. The old probe exercised
#    exactly one alternative of the alternation, so a typo in any of the
#    other thirty was invisible.
missed=""
IFS='|' read -r -a forbidden <<< "$libc_names"
for fname in "${forbidden[@]}"; do
  grep -qE "call[^\"]*@($libc_names)\(" <<< "  %r = call i64 @$fname(i64 0)" \
    || missed="$missed $fname"
done
if (( ${#forbidden[@]} < 25 )); then
  echo "FAIL negative probe: the forbidden-name list parsed to only ${#forbidden[@]} names"
  status=1
elif [[ -n "$missed" ]]; then
  echo "FAIL negative probe: the IR check does not catch a call to$missed"
  status=1
else
  echo "ok   negative probe: the IR check catches a call to each of ${#forbidden[@]} libc names"
fi

# And it DISCRIMINATES. A pattern that matched every line would pass the
# loop above while reporting the whole standard library as libc, so the
# grep is also shown refusing a call the corpus makes on every run -
# `@axiom_alloc` is Axiom's own, and the substring hazard is real:
# `free` sits inside a name like `freelist` and `wait` inside `awaited`,
# so this is what would notice the alternation losing its anchors.
kept=""
for ok_name in axiom_alloc freelist awaited printfmt __syscall1; do
  grep -qE "call[^\"]*@($libc_names)\(" <<< "  %r = call i64 @$ok_name(i64 0)" \
    && kept="$kept $ok_name"
done
if [[ -n "$kept" ]]; then
  echo "FAIL negative probe: the IR check flags non-libc name(s)$kept"
  status=1
else
  echo "ok   negative probe: the IR check leaves Axiom's own call names alone"
fi

# The OTHER direction, which nothing here asserted: that the patterns
# above actually FIRE. A gate is only worth its green when it has been
# shown to go red, and this one had been silently half-blind - the
# stage1 paragraph below names `_memset` as a symbol it caught, while
# `memset` was absent from `libc_names` until 2026-08-16, so that half
# of the claim had never been true. Each line here is a shape the
# corpus cannot produce today; if the recogniser ever emits one, the
# check that notices is the one being probed.
missed=""
for bad_line in \
  '  %r = call i64 @memset(i64 0, i64 0, i64 8)' \
  '  %r = call i64 @memcpy(i64 0, i64 0, i64 8)' \
  '  %r = call i64 @strlen(i64 0)' \
  '  %r = call i64 @malloc(i64 8)' \
  '  %r = call i64 @posix_spawn(i64 0)' ; do
  grep -qE "call[^\"]*@($libc_names)\(" <<< "$bad_line" \
    || missed="$missed ${bad_line##*@}"
done
for intr_line in \
  '  call void @llvm.memset.p0.i64(ptr %d, i8 0, i64 8, i1 false)' \
  '  call void @llvm.memcpy.p0.p0.i64(ptr %d, ptr %s, i64 8, i1 false)' ; do
  grep -qE "@llvm\.(memset|memcpy|memmove)\." <<< "$intr_line" \
    || missed="$missed ${intr_line##*@}"
done
if [[ -n "$missed" ]]; then
  echo "FAIL negative probe: the IR checks do NOT flag$missed"
  status=1
else
  echo "ok   negative probe: the IR checks flag libc calls and llvm.mem* intrinsics"
fi

# 2. The door is shut in the language, not merely unused by the corpus.
#    A sweep over programs that do not call libc says nothing about
#    whether one COULD; this is the check that says it cannot, and it is
#    the reason (1) no longer has an Axiom program behind it.
ffi="$work/ffi-probe.ax"
cat > "$ffi" <<'PROBE'
(foreign posix_spawn :: (-> Int Int Int Int Int Int) = "posix_spawn")
(pub :: main Int)
(pub fn (main) (posix_spawn 0 0 0 0 0))
PROBE
# Assigned inside the `if` condition, not before it: this script runs
# under `set -e`, and a bare `out="$(cmd)"` whose command exits non-zero
# takes the whole script down. Here a non-zero exit is the PASSING
# outcome, so writing it that way killed the gate one line before its
# own result - exit 1, no verdict printed, which reads as a failure
# somewhere else entirely.
if ffi_out="$("$axiom" --diagnostic-format=ai check "$ffi" 2>&1)"; then
  echo "FAIL negative probe: a \`foreign\` binding still compiles - the FFI is back"
  status=1
elif ! grep -q 'AX2004' <<< "$ffi_out"; then
  echo "FAIL negative probe: \`foreign\` is refused, but not as a removed construct"
  printf '%s\n' "$ffi_out" | sed 's/^/    /' | head -3
  status=1
else
  echo "ok   negative probe: \`foreign\` is refused as a removed construct (AX2004)"
fi

exit "$status"
