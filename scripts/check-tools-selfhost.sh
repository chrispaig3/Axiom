#!/usr/bin/env bash
# The self-hosted CLI tools answer with stage0's bytes.
#
# `self_host/explain.ax` is GENERATED from stage0's own output - one
# cached run per diagnostic code - so the texts cannot drift by
# transcription. This gate closes the other drift direction: a code
# added or reworded in `axiom-errors/src/code.rs` changes stage0's
# output while the generated table still carries yesterday's bytes,
# and the differential below fails until the table is regenerated:
#
#   for c in $(target/release/axiom explain --list \
#              | grep -oE 'AX[0-9]{4}'); do
#     target/release/axiom explain $c > /tmp/exp/$c.out; done
#   ... then re-run the generator recorded in explain.ax's header.
#
# The code list is taken from stage0's `--list` AT RUN TIME, so a new
# code joins the sweep by existing - stage1 missing it is a failure,
# not a smaller sweep. Floor: at least 25 codes, because a sweep that
# reads nothing reports the silence it was looking for.
#
# Negative test, run at introduction: deleting one code's row from the
# generated table fails exactly that code's comparison. Verified.
#
# `symbols`, the REPL and the human renderer join this gate as they
# are ported.
#
# Usage:  scripts/check-tools-selfhost.sh

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "building the compiler first (no binary at $axiom)" >&2
  cargo build --release
fi

export AXIOM_STDLIB="$repo_root/stdlib"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ln -s "$repo_root/stdlib" "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"

echo "== building stage1 =="
if ! "$axiom" build --input self_host/main.ax --output "$work/stage1" >"$work/build.log" 2>&1; then
  echo "FAIL: could not build stage1" >&2
  tail -20 "$work/build.log" >&2
  exit 1
fi

failed=0

# stdout, stderr and exit status must all agree.
compare() {
  local label="$1"; shift
  "$axiom" "$@" >"$work/a.out" 2>"$work/a.err"; local s0=$?
  (cd "$work" && ./stage1 "$@" >b.out 2>b.err); local s1=$?
  if [[ "$s0" != "$s1" ]]; then
    echo "FAIL $label: exit status diverged (stage0=$s0 stage1=$s1)"
    failed=$((failed + 1))
  elif ! cmp -s "$work/a.out" "$work/b.out"; then
    echo "FAIL $label: stdout differs"
    diff "$work/a.out" "$work/b.out" | head -6 | sed 's/^/     /'
    failed=$((failed + 1))
  elif ! cmp -s "$work/a.err" "$work/b.err"; then
    echo "FAIL $label: stderr differs"
    diff "$work/a.err" "$work/b.err" | head -6 | sed 's/^/     /'
    failed=$((failed + 1))
  fi
}

echo "== explain: every code stage0 lists =="
codes=0
for code in $("$axiom" explain --list | grep -oE 'AX[0-9]{4}' | sort -u); do
  codes=$((codes + 1))
  compare "explain $code" explain "$code"
done
echo "     $codes codes"
if [[ $codes -lt 25 ]]; then
  echo "FAIL the code sweep read $codes codes; the floor is 25"
  failed=$((failed + 1))
fi

echo "== explain: spellings, list, bare, unknown =="
compare "explain ax3001 (lowercase)" explain ax3001
compare "explain 3001 (bare digits)" explain 3001
compare "explain AX-3001 (dashed)" explain AX-3001
compare "explain --list" explain --list
compare "explain (no argument)" explain
compare "explain AX9999 (unknown)" explain AX9999
compare "explain ax99 (unknown short)" explain ax99

echo
if [[ $failed -eq 0 ]]; then
  echo "tools-selfhost: all checks passed"
else
  echo "tools-selfhost: $failed check(s) failed"
  exit 1
fi
