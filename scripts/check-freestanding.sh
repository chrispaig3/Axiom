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

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/.axiom-bin/axiom}"
if [[ ! -x "$axiom" ]]; then
  # No `cargo` here, and none anywhere in this repository's gates: the
  # Rust compiler this used to build has been deleted. A checkout gets
  # a compiler from the committed seed - `bootstrap/axiom-<target>.ll`
  # through `llc` and `cc` - which is the whole point of that directory
  # existing. Set AXIOM to use one you already have.
  echo "no compiler at $axiom - building one from the committed seed" >&2
  "$repo_root/scripts/bootstrap-from-seed.sh" --install "$repo_root/.axiom-bin" >&2 \
    || { echo "FAIL: could not bootstrap a compiler from bootstrap/" >&2; exit 1; }
fi
export AXIOM_STDLIB="$repo_root/stdlib"

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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

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
