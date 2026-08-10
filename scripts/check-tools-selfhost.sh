#!/usr/bin/env bash
# `explain` and `symbols`, pinned without a second compiler.
#
# This gate used to be a differential against the Rust compiler: run
# both binaries on the same input, require identical bytes. That was
# the right shape while the Rust compiler was the trusted reference and
# the Axiom one was being brought up to it. It stops being available
# the moment the reference is deleted, and - this is the part worth
# being careful about - a differential does not fail when its reference
# disappears. Point `$axiom` at a self-hosted binary and every
# comparison becomes a compiler against itself: 214 files swept, zero
# differences, exit 0, and nothing tested. That is the failure mode
# this repository names most often, and it is why the gate was rewritten
# rather than left to degrade.
#
# What replaces it, per surface:
#
#   explain   a checked-in golden of every code's text, materialized
#             from the Rust compiler at the last commit that had one
#             (tests/tools/explain.golden), PLUS a cross-check that
#             every code the diagnostics corpus actually emits has an
#             entry. The second half is derived from a different
#             artifact - tests/diagnostics/*.axdl - so re-blessing the
#             explain golden cannot satisfy it.
#
#   symbols   three checks, of which only the first is a golden:
#               1. AXSYM for tests/fmt/syntax-zoo.ax, byte for byte
#               2. `symbols` exits 0 for exactly the files `check`
#                  exits 0 for - two subcommands of one binary
#                  cross-checking each other, with nothing to bless
#               3. EVERY position claim AXSYM makes, verified against
#                  the source bytes: at the line and columns a symbol
#                  names, the file must literally spell that symbol
#
# Check 3 is strictly stronger than the differential it replaces.
# Agreeing with another implementation says two things agree; this says
# the answer is CORRECT, it cannot be satisfied by regenerating
# anything, and it does not churn when a span moves - the position is
# recomputed from the source on every run. 14,123 claims over the
# corpus, plus 503 symbols that carry no position by design (the
# builtin `Option` and its constructors, and the operations of an
# `effect`) and are counted rather than skipped.
#
# THE DRILL, run rather than assumed. A compiler was built with every
# AXSYM start column shifted by one, and BOTH goldens were regenerated
# from it:
#
#   the zoo golden        re-blessed clean - matched the wrong compiler
#   the status manifest   re-blessed clean - matched the wrong compiler
#   verify-axsym.py       14,100 of 14,100 claims wrong, plus 23 lines
#                         it could not even parse (one-character names,
#                         whose spans went zero-width and printed
#                         without the dash), exit 1
#
# That is the whole argument for check 3 existing, measured: the two
# goldens are exactly as strong as whoever last regenerated them, and
# the verifier is not.
#
# The provenance of both goldens, recorded at the last moment there
# were two compilers to compare: at commit 1041f11 the Rust compiler
# and the self-hosted one produced IDENTICAL AXSYM for all 216 files -
# all 14,626 lines - and identical exit statuses, once paths are
# normalised and the sweep runs from a neutral directory.
#
# Usage:  scripts/check-tools-selfhost.sh

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/.axiom-bin/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "no compiler at $axiom - building one from the committed seed" >&2
  "$repo_root/scripts/bootstrap-from-seed.sh" --install "$repo_root/.axiom-bin" >&2 \
    || { echo "FAIL: could not bootstrap a compiler" >&2; exit 1; }
fi

export AXIOM_STDLIB="$repo_root/stdlib"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failed=0

# AXSYM names the file each symbol came from, and for an imported
# stdlib module that path depends on where the BINARY lives - both
# compilers resolve their stdlib relative to themselves, so the same
# symbol is `.../target/release/../../stdlib/Mem.ax` from one install
# and `.../.axiom-bin/../stdlib/Mem.ax` from another. Neither is wrong
# and neither belongs in a golden. Normalising to the repo-relative
# spelling is what makes the golden a fact about AXSYM rather than
# about the checkout.
# Anchored on the `..` segment, which is what marks a
# binary-relative path. An earlier version matched any path ending in
# `stdlib/` and quietly rewrote `tests/stdlib/010-hello.ax` to
# `stdlib/010-hello.ax` - a file that does not exist, which the
# position verifier then reported as 191 unreadable files. The
# normaliser has to name the thing it is normalising.
norm() { sed -E -e "s|[^ ]*\.\./stdlib/|stdlib/|g" -e "s|[^ ]*\.\./self_host/|self_host/|g" -e "s|$repo_root/||g"; }

# Every invocation runs from `$neutral`, a directory containing
# nothing. The compiler keeps a legacy CWD-relative entry in its module
# search, so running the sweep from the repository root would let a
# fixture resolve `(import lexer)` out of self_host/ - which is a
# property of where the sweep ran, not of the fixture, and it moves 4
# of the 216 statuses. A neutral directory measures the file.
neutral="$work/neutral"
mkdir -p "$neutral"

# The compiler under test is the one built FROM SOURCE by `$axiom`, not
# `$axiom` itself: this gate exists to test self_host/, and `$axiom` may
# be an older seed-descended binary that predates the change being
# tested.
#
# Deliberately NO stdlib/self_host symlinks in the work directory. The
# compiler keeps a legacy CWD-relative module search that the compile
# harnesses depend on, and a salted work directory would let the symbols
# sweep resolve imports it should not - which flatters the refusal half
# of the exit-status manifest.
echo "== building the compiler under test =="
if ! "$axiom" build --input self_host/main.ax --output "$work/axc" >"$work/build.log" 2>&1; then
  echo "FAIL: could not build the compiler under test" >&2
  tail -20 "$work/build.log" >&2
  exit 1
fi

# ---------------------------------------------------------------
# explain
# ---------------------------------------------------------------
# THE COLOUR IN THE LIST SECTION IS RECONSTRUCTED, NOT CAPTURED, and the
# golden's header says so. stage0 printed `explain --list` through the
# `colored` crate, which does its own tty detection and has no
# `set_override` anywhere in that binary - so into a pipe, which is how
# this golden was materialised, stage0 emitted no escapes at all. Its
# diagnostics went through ariadne, which had the opposite behaviour and
# painted a pipe as readily as a terminal.
#
# stage1 is always-on everywhere, which EXCEEDS stage0 here rather than
# matching it. The palette is `colored`'s - bold bright cyan heading,
# bright yellow codes - so the intent is reproduced even though the
# bytes were never observed. Recorded because this file's whole job is
# provenance, and a captured byte and a reconstructed one are not the
# same claim.
echo "== explain: every code and spelling, against the golden =="
golden="tests/tools/explain.golden"
[[ -f "$golden" ]] || { echo "FAIL: $golden is missing"; exit 1; }

{
  # Regenerated in the same order and with the same section headers the
  # golden was written with; a mismatch in the ORDER is a real
  # difference and is meant to fail.
  head -4 "$golden"
  echo "### explain --list"
  "$work/axc" explain --list 2>&1
  for c in $("$work/axc" explain --list 2>/dev/null | grep -oE 'AX[0-9]{4}' | sort -u); do
    echo "### explain $c"
    "$work/axc" explain "$c" 2>&1
  done
  for v in ax3001 3001 AX-3001 AX9999 ax99; do
    echo "### explain $v (exit $("$work/axc" explain "$v" >/dev/null 2>&1; echo $?))"
    "$work/axc" explain "$v" 2>&1
  done
  echo "### explain (no argument) (exit $("$work/axc" explain >/dev/null 2>&1; echo $?))"
  "$work/axc" explain 2>&1
} > "$work/explain.out"

if ! cmp -s "$golden" "$work/explain.out"; then
  echo "FAIL explain: output differs from $golden"
  diff "$golden" "$work/explain.out" | head -12 | sed 's/^/     /'
  failed=$((failed + 1))
else
  echo "ok   explain matches the golden ($(grep -c '^### ' "$golden") sections)"
fi

# The half a re-bless of that golden cannot satisfy: the codes come from
# a DIFFERENT artifact. Every code the diagnostics corpus actually emits
# must have an explanation, so a new diagnostic that nobody documented
# fails here rather than shipping undocumented.
echo "== explain: every code the diagnostics corpus emits has an entry =="
listed="$("$work/axc" explain --list 2>/dev/null | grep -oE 'AX[0-9]{4}' | sort -u)"
emitted="$(grep -ohE 'AX[0-9]{4}' tests/diagnostics/*.axdl | sort -u)"
emitted_n="$(printf '%s\n' "$emitted" | grep -c .)"
if (( emitted_n < 20 )); then
  echo "FAIL: only $emitted_n codes found in tests/diagnostics/*.axdl; the floor is 20 (the corpus moved or the glob broke)"
  failed=$((failed + 1))
fi
missing="$(comm -23 <(printf '%s\n' "$emitted") <(printf '%s\n' "$listed") | tr '\n' ' ')"
if [[ -n "${missing// /}" ]]; then
  echo "FAIL explain: codes the corpus emits with no explanation: $missing"
  failed=$((failed + 1))
else
  echo "ok   all $emitted_n codes emitted by the corpus are explained"
fi

# ---------------------------------------------------------------
# symbols
# ---------------------------------------------------------------
# `--target` is PINNED for both golden comparisons below, and has to be.
#
# The zoo imports `Sys`, `Sys` imports `Sys.Platform`, and that module is
# selected by TARGET - `Platform.darwin.ax` here, `Platform.linux-aarch64.ax`
# on one CI runner, `Platform.linux-x86_64.ax` on another. Its symbols land
# in the table with the resolved file's name AND its line numbers, so 22 of
# the zoo's 89 rows are a statement about the host rather than about the
# fixture. Blessed on darwin, the golden could only ever match on darwin:
#
#     < F sysRead stdlib/Sys/Platform.darwin.ax:21:9-16 "Int" @d99009b49c22cd84
#     > F sysRead stdlib/Sys/Platform.linux-aarch64.ax:8:9-16 "Int" @d99009b49c22cd84
#
# which is what both Linux targets reported the first time this gate ever
# ran on them. Note the hash is EQUAL across the two - the symbol is the
# same symbol; only its address in the tree moved.
#
# Pinning a target rather than normalising the path away is the choice that
# keeps the other half honest: the cited file still exists on every host, so
# the position verifier can still open it and check the claim against real
# bytes. A placeholder would have to be exempted from that check, which is
# the half a re-bless cannot satisfy and the half worth keeping.
#
# darwin-aarch64 is simply the target the goldens were blessed with; any
# fixed one would do. What matters is that it is fixed, which also means a
# contributor on Linux can now run this gate at all - until this line they
# could not.
zoo_target="darwin-aarch64"

echo "== symbols: the syntax zoo, against the golden =="
zoo_golden="tests/tools/symbols-zoo.golden"
[[ -f "$zoo_golden" ]] || { echo "FAIL: $zoo_golden is missing"; exit 1; }
(cd "$neutral" && "$work/axc" --target="$zoo_target" --diagnostic-format=ai symbols \
   "$repo_root/tests/fmt/syntax-zoo.ax" 2>/dev/null) | norm >"$work/zoo.out"
if ! cmp -s "$zoo_golden" "$work/zoo.out"; then
  echo "FAIL symbols: the zoo's AXSYM differs from $zoo_golden"
  diff "$zoo_golden" "$work/zoo.out" | head -10 | sed 's/^/     /'
  failed=$((failed + 1))
else
  echo "ok   the zoo's AXSYM matches the golden ($(wc -l <"$zoo_golden" | tr -d ' ') symbols)"
fi

# ---------------------------------------------------------------
# The human table, and the half a re-bless of ITS golden cannot satisfy.
#
# `symbols` printed AXSYM under every format until the table landed;
# stage0's bare `symbols` printed the table and only `ai` gave AXSYM.
# The golden below is the re-blessable half. The derivation after it
# reads `$work/zoo.out` - the AXSYM golden's own bytes, a different
# artifact - and reconstructs every row from them, so a table that
# invented, dropped, reordered or misspelled a symbol fails even with a
# freshly written golden beside it.
# ---------------------------------------------------------------
echo "== symbols: the human table, against the golden and against AXSYM =="
tbl_golden="tests/tools/symbols-zoo-human.golden"
(cd "$neutral" && "$work/axc" --target="$zoo_target" symbols \
   "$repo_root/tests/fmt/syntax-zoo.ax" 2>/dev/null) | norm >"$work/zoo.tbl"
if [[ "${AXIOM_BLESS:-0}" == 1 ]]; then
  cp "$work/zoo.tbl" "$repo_root/$tbl_golden"
  echo "blessed $tbl_golden"
fi
if [[ ! -f "$tbl_golden" ]]; then
  echo "FAIL symbols: $tbl_golden is missing; run with AXIOM_BLESS=1"
  failed=$((failed + 1))
elif ! cmp -s "$tbl_golden" "$work/zoo.tbl"; then
  echo "FAIL symbols: the human table differs from $tbl_golden"
  diff "$tbl_golden" "$work/zoo.tbl" | head -6 | sed 's/^/     /'
  failed=$((failed + 1))
else
  echo "ok   the human table matches the golden ($(wc -l <"$tbl_golden" | tr -d ' ') rows)"
fi

# Row for row against the AXSYM the same run produced.
tbl_bad="$(python3 - "$work/zoo.out" "$work/zoo.tbl" <<'PY'
import re, sys
# One entry per arm of `symKindWord` in self_host/symbols.ax, and no
# more: `X` (foreign binding) was retired with the FFI, and leaving it
# here would have this rule spell a kind the compiler prints raw.
KIND = {'F': 'Fn', 'D': 'Data', 'C': 'Ctor',
        'S': 'Struct', 'A': 'Alias', 'T': 'Trait'}
axsym = [l for l in open(sys.argv[1], encoding='utf-8').read().split('\n') if l]
table = [l for l in open(sys.argv[2], encoding='utf-8').read().split('\n') if l]
bad = []
if len(axsym) != len(table):
    bad.append('%d AXSYM lines, %d table rows' % (len(axsym), len(table)))
for i, (a, t) in enumerate(zip(axsym, table)):
    k, name, loc, rest = a.split(' ', 3)
    ty = rest[1:rest.rindex('"')] if rest.startswith('"') else ''
    want_loc = 'builtin' if loc == '-' else loc
    # The rule, not the golden: 8, 20 and 40 columns, left justified,
    # single spaces between, location in brackets at the end.
    want = '%-8s %-20s %-40s [%s]' % (KIND.get(k, k), name, ty, want_loc)
    if t != want:
        bad.append('row %d\n      is   %r\n      want %r' % (i + 1, t, want))
    if len(bad) > 3:
        break
print('\n    '.join(bad))
PY
)"
if [[ -n "$tbl_bad" ]]; then
  echo "FAIL symbols: the table does not reconstruct from AXSYM"
  echo "    $tbl_bad"
  failed=$((failed + 1))
else
  echo "ok   every table row reconstructs from its AXSYM line ($(wc -l <"$work/zoo.out" | tr -d ' ') rows)"
fi

echo '== symbols: exit status agrees with check, file by file =='
# This was a checked-in manifest of the per-file exit status, and the
# manifest was wrong for the corpus - it enumerated every `.ax` in the
# repository, so ADDING A TEST FIXTURE anywhere made it fail and need
# re-blessing. A golden that churns for reasons unrelated to what it
# pins is a golden nobody reads.
#
# The property behind it does not churn. `symbols` folds every failure
# into exit 1, where `check` distinguishes parse (2) from semantic (1),
# so for every file:
#
#     symbols exits 0  <=>  check exits 0
#
# That is two independent paths through the same binary - a file that
# type-checks but whose symbols cannot be listed, or vice versa, is a
# real defect and nothing has to be regenerated for this to notice.
# Measured over 224 files at the time it was written: zero mismatches.
: > "$work/all.axsym"
swept=0; accepted=0; refused=0
while read -r f; do
  swept=$((swept + 1))
  (cd "$neutral" && "$work/axc" check "$repo_root/$f" >/dev/null 2>&1); c=$?
  (cd "$neutral" && "$work/axc" --diagnostic-format=ai symbols "$repo_root/$f" \
     2>/dev/null) | norm > "$work/one.axsym"
  (cd "$neutral" && "$work/axc" --diagnostic-format=ai symbols "$repo_root/$f" \
     >/dev/null 2>&1); sy=$?
  cat "$work/one.axsym" >> "$work/all.axsym"
  if [[ "$c" == 0 ]]; then
    accepted=$((accepted + 1))
    if [[ "$sy" != 0 ]]; then
      echo "FAIL $f: check accepted it (0) but symbols refused it ($sy)"
      failed=$((failed + 1))
    fi
  else
    refused=$((refused + 1))
    if [[ "$sy" == 0 ]]; then
      echo "FAIL $f: check refused it ($c) but symbols answered (0)"
      failed=$((failed + 1))
    elif [[ "$sy" != 1 ]]; then
      echo "FAIL $f: symbols exited $sy; it folds every failure into 1"
      failed=$((failed + 1))
    fi
  fi
done < <(find stdlib self_host tests -name '*.ax' | sort)

if (( swept < 150 )); then
  echo "FAIL: the sweep read only $swept files; the floor is 150 - a tree is missing from the find"
  failed=$((failed + 1))
# Both outcomes have to occur, or the agreement is trivial: a `symbols`
# that always succeeded would satisfy a corpus that always type-checks.
elif (( accepted == 0 || refused == 0 )); then
  echo "FAIL: every file got the same verdict ($accepted accepted, $refused refused) - the check cannot distinguish anything"
  failed=$((failed + 1))
else
  echo "ok   $swept files, symbols agrees with check everywhere ($accepted accepted, $refused refused)"
fi

echo "== symbols: every position claim, against the source =="
if ! (cd "$repo_root" && python3 tests/tools/verify-axsym.py "$work/all.axsym"); then
  echo "FAIL symbols: AXSYM claims a symbol where the source does not have one"
  failed=$((failed + 1))
fi

# ---------------------------------------------------------------
# The documented programs compile.
#
# `check-tree-sitter.sh` runs the same verifier for delimiter BALANCE,
# in the grammar job that deliberately has no compiler. Balance cannot
# see an example that parses and means nothing, and three did - `(fn
# main ...)` with more than one body expression is a syntax error, and
# `printf` is not a function in this language. This is where the
# compiler exists, so this is where they are compiled.
# ---------------------------------------------------------------
echo "== docs: every documented whole program compiles =="
if ! python3 "$repo_root/tests/docs/verify-doc-code.py" --compile "$work/axc" \
     "$repo_root/README.md" "$repo_root/docs/reference.md" \
     "$repo_root/CONTRIBUTING.md" \
     "$repo_root/docs/macros.md" "$repo_root/docs/self-hosting.md"; then
  failed=$((failed + 1))
fi

echo "== symbols: flags, and a file that is not there =="
zoocase="$repo_root/tests/stdlib/010-hello.ax"
(cd "$neutral" && "$work/axc" --diagnostic-format=ai symbols --builtins "$zoocase" \
   >"$work/b1.out" 2>/dev/null); b1=$?
(cd "$neutral" && "$work/axc" --diagnostic-format=ai symbols "$zoocase" --builtins \
   >"$work/b2.out" 2>/dev/null); b2=$?
if [[ "$b1" != 0 || "$b2" != 0 ]] || ! cmp -s "$work/b1.out" "$work/b2.out"; then
  echo "FAIL symbols: --builtins is order-sensitive (exits $b1/$b2)"
  failed=$((failed + 1))
elif ! grep -q '^C Some ' "$work/b1.out"; then
  echo "FAIL symbols: --builtins printed no builtin constructor - the flag did nothing"
  failed=$((failed + 1))
else
  echo "ok   --builtins works in either position and lists the builtins"
fi

"$work/axc" symbols "$work/does-not-exist.ax" >"$work/m.out" 2>/dev/null; m=$?
if [[ "$m" == 0 || -s "$work/m.out" ]]; then
  echo "FAIL symbols: a missing file exited $m with $(wc -c <"$work/m.out" | tr -d ' ') bytes on stdout"
  failed=$((failed + 1))
else
  echo "ok   a missing file is refused with empty stdout"
fi

echo
if [[ $failed -eq 0 ]]; then
  echo "tools-selfhost: all checks passed"
else
  echo "tools-selfhost: $failed check(s) failed"
  exit 1
fi
