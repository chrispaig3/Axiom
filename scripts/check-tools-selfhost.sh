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
# Deliberately NO stdlib/self_host symlinks here, unlike the gates
# that COMPILE through stage1: stage1 keeps a legacy CWD-relative
# search entry five harnesses depend on, and a work directory that
# feeds it would let stage1 resolve imports stage0 cannot - the
# symbols sweep's refusal parity on tests/selfhost's compiler-module
# imports depends on both sides failing identically. stage0 builds
# stage1 from the repository root and needs nothing from here.

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

# ---------------------------------------------------------------
# symbols: every .ax in the repository, live and two-sided.
#
# stage0 runs fresh rather than from a cache: a cached golden went
# stale FOUR times while the port was written, each time because an
# edit moved spans in a file some other file imports. Both binaries
# get ABSOLUTE paths, and stage1 runs from the gate's work directory,
# which deliberately contains no stdlib or self_host entry - so its
# legacy CWD-relative search (which the five compile harnesses still
# depend on) finds nothing stage0's search would not, and resolution
# failures agree.
#
# `symbols` folds EVERY failure into exit 1 - parse errors included,
# where `check` answers 2 - so the deliberately-broken fixtures under
# tests/ are refusal-parity cases, not skips: both sides must refuse,
# and stdout must be empty on both.
#
# Negative test, RUN at introduction, not assumed: ablating the
# emitter's nid-variant map (every variant forced to DFn:) fails the
# sweep on every file with a sig, data, struct, alias or trait.
# ---------------------------------------------------------------
echo "== symbols: corpus differential =="
swept=0
for f in $(find "$repo_root/stdlib" "$repo_root/self_host" "$repo_root/tests" -name '*.ax' | sort); do
  swept=$((swept + 1))
  "$axiom" --diagnostic-format=ai symbols "$f" >"$work/s0.out" 2>/dev/null; s0=$?
  (cd "$work" && ./stage1 symbols "$f" >s1.out 2>/dev/null); s1=$?
  if [[ "$s0" != "$s1" ]]; then
    echo "FAIL symbols $f: exit status diverged (stage0=$s0 stage1=$s1)"
    failed=$((failed + 1))
  elif ! cmp -s "$work/s0.out" "$work/s1.out"; then
    echo "FAIL symbols $f: stdout differs"
    diff "$work/s0.out" "$work/s1.out" | head -4 | sed 's/^/     /'
    failed=$((failed + 1))
  fi
done
echo "     $swept files swept"
if [[ $swept -lt 150 ]]; then
  echo "FAIL symbols sweep read $swept files; the floor is 150"
  failed=$((failed + 1))
fi

echo "== symbols: --builtins, flag order, missing file =="
zoocase="$repo_root/tests/stdlib/010-hello.ax"
# The global format flag goes to BOTH binaries: stage0 needs it to
# emit AXSYM rather than its human table, and stage1's argv walk
# skips an unrecognised global flag.
compare "symbols --builtins FILE" --diagnostic-format=ai symbols --builtins "$zoocase"
compare "symbols FILE --builtins" --diagnostic-format=ai symbols "$zoocase" --builtins
# Missing file: status and stdout only. The stderr prose carries
# Rust's io::Error rendering ("(os error 2)"), which is not part of
# any contract a port should chase.
"$axiom" symbols "$work/does-not-exist.ax" >"$work/m0.out" 2>/dev/null; m0=$?
(cd "$work" && ./stage1 symbols "$work/does-not-exist.ax" >m1.out 2>/dev/null); m1=$?
if [[ "$m0" != "$m1" || -s "$work/m0.out" || -s "$work/m1.out" ]]; then
  echo "FAIL symbols missing-file: statuses ($m0/$m1) or stdout nonempty"
  failed=$((failed + 1))
fi

echo
if [[ $failed -eq 0 ]]; then
  echo "tools-selfhost: all checks passed"
else
  echo "tools-selfhost: $failed check(s) failed"
  exit 1
fi
