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
libc_names='printf|puts|malloc|calloc|realloc|free|strlen|strcmp|fopen|fwrite|fread'

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

exit "$status"
