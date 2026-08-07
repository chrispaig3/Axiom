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

axiom="${AXIOM:-$repo_root/target/release/axiom}"
[[ -x "$axiom" ]] || cargo build --release
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

# A gate that has never been seen to fail is a gate nobody has checked.
#
# Everything above asserts SILENCE - no libc in any case - and silence is
# exactly what a broken grep, an empty corpus, or a mistyped alternation
# also produces. So the gate finishes by compiling a program that
# deliberately does the forbidden thing and requiring both mechanisms to
# catch it. The probe uses `posix_spawn` because that is the name the
# process-control entries were added for, and because it is the one an
# author would actually reach for.
#
# It cannot live in `tests/stdlib/`: six other gates glob that directory
# and would all fail on it. It is written here instead, following the
# inline-fixture precedent in `check-self-host.sh`.
probe="$work/libc-probe.ax"
cat > "$probe" <<'PROBE'
(foreign posix_spawn :: (-> Int Int Int Int Int Int) = "posix_spawn")
(pub :: main Int)
(pub fn (main) (posix_spawn 0 0 0 0 0))
PROBE

probe_ir="$work/libc-probe.ll"
if ! "$axiom" emit-llvm "$probe" -o "$probe_ir" > /dev/null 2>&1; then
  echo "FAIL negative probe: the libc probe did not compile, so it proves nothing"
  status=1
elif ! grep -qE "call[^\"]*@($libc_names)\(" "$probe_ir"; then
  echo "FAIL negative probe: a program calling posix_spawn passed the IR check"
  echo "     the forbidden-name list does not cover what it claims to"
  status=1
else
  echo "ok   negative probe: a libc spawn is refused by the IR check"
fi

exit "$status"
