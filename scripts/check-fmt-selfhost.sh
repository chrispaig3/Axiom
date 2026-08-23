#!/usr/bin/env bash
# The formatter, pinned without a second compiler.
#
# This gate used to be a differential. It built stage1 with the Rust
# compiler and then required, on the syntax zoo, on every `.ax` in the
# tree, and on the `tests/fmt/parity/*.axp` refusal bank, that the two
# `fmt` implementations produce identical bytes and identical exit
# status. That was the right shape while the Rust compiler was the
# reference being reproduced. It stops being available the moment the
# reference is deleted, and - this is the part worth being careful about
# - a differential does not FAIL when its reference disappears. Point
# `$axiom` at a self-hosted binary and every comparison becomes a
# compiler against itself: 224 files swept, zero differences, exit 0,
# and nothing tested. That is the failure this repository names most
# often, and it is why the gate was rewritten rather than repointed.
#
# What replaces it, in two halves that fail for different reasons.
#
# The goldens - what the normal form IS. A rewrite cannot be checked by
# re-parsing, because `(define x 1)` and `(fn (x) 1)` mean the same
# thing; only a reviewed artefact can say which one comes out.
#
#   zoo       `tests/fmt/syntax-zoo.ax` formats to the checked-in
#             `tests/fmt/syntax-zoo.expected.ax`, byte for byte - the
#             same golden `check-fmt.sh` pins, unchanged by this
#             conversion. Plus: the golden is a fixed point of itself.
#
#   parity    `tests/fmt/parity.golden`, new here: per `.axp` case the
#             exit status AND, when it formats, the formatted bytes.
#             The bank is 37 hand-written cases, 20 rewrites and 17
#             refusals, so the file cannot be satisfied by a formatter
#             that always succeeds or always refuses - the gate checks
#             that both statuses are present.
#
#   corpus    `tests/fmt/corpus-fmt.golden`, new here: for every `.ax`
#             in the tree, sha256(source) -> sha256(formatted). Keyed by
#             the SOURCE hash, not the path, and that is deliberate.
#             `fmt` rewrites 221 of the 224 corpus files, so their
#             formatted bytes change whenever anyone edits anything, and
#             a golden that churns on every edit gets re-blessed unread.
#             Hashing the input means an edited file RETIRES its entry
#             instead of reddening the gate, and the floor on surviving
#             entries is what stops the table from being retired into
#             vacuity.
#
# The derived half - what a re-bless cannot satisfy, because none of it
# is stored anywhere. Recomputed from the inputs on every run:
#
#   idempotent    format, then format the result: byte-identical, and
#                 `fmt --check` on the result exits 0. 244 pairs at
#                 introduction. A printer that loses a form on the
#                 second pass fails here whatever any golden says.
#
#   preserving    `tests/fmt/verify-fmt.py` reads the ORIGINAL and the
#                 FORMATTED bytes of every file and compares comments,
#                 string literals and character literals with a scanner
#                 of its own: 9,282 comments, 2,832 strings and 22
#                 character literals over those 244 pairs. This
#                 is the class of bug that shipped: `fmt` deleted every
#                 block comment, every AXTAG, every `(import ...)` and
#                 every `pub` marker with CI green.
#
#   compiling     the whole tree is copied, formatted, and the compiler
#                 is REBUILT from the formatted copy - which type-checks
#                 every formatted stdlib and self_host file by using it
#                 - and that compiler must reproduce the zoo golden. A
#                 formatter that changes what a program means fails here
#                 even when the change re-parses, which is how the
#                 nullary-pattern bug survived the first fmt tests.
#
# Regenerating the two new goldens is deliberate and manual; the recipe
# is in each one's header. Their provenance is recorded there too: both
# were materialized at commit 1041f11 from the Rust compiler and
# verified, at that commit, to be byte-identical to what the self-hosted
# compiler produces - 224 corpus mappings and all 37 parity cases - on
# the last day there were two compilers to compare.
#
# Ablation drills, run at introduction rather than assumed. The wrong
# printer is a compiler built from a scratch copy of self_host/ in which
# `flushTrailing` advances the comment queue without emitting anything -
# every `(foo)  ; note` loses its note - and `fmtFormat`'s own
# count-and-content verification is removed so the loss is written
# rather than refused. Nothing in the working tree is edited; the gate
# is handed the wrong binary through $AXIOM.
#
#   * that printer, all goldens as committed -> exit 1, 7 checks: the
#     zoo golden and its fixed point, 29 of 224 corpus mappings, the
#     parity bank's status AND a parity case that stopped being
#     idempotent, preservation on 29 files, and `--check` calling a
#     formatted file dirty
#
#   * the same printer with EVERY golden this gate reads re-blessed from
#     it - the zoo, the corpus table, the parity bank - -> still exit 1,
#     3 checks. The goldens go green, which is the point: what survives
#     is the parity case that is not a fixed point, preservation on 28
#     files, and the rebuild, which now fails in the opposite direction
#     because the compiler built from the formatted TREE is the correct
#     one and no longer matches a golden blessed from the wrong binary.
#
# Note which check did NOT fire in the first drill: the rebuild. Dropping
# a comment is data loss, not a change of meaning, so formatted sources
# still compile into a working compiler. That division is deliberate -
# preservation catches what the tree cannot notice, the rebuild catches
# what the text cannot.
#
# Usage:  scripts/check-fmt-selfhost.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

failed=0

# The formatter under test is the one built FROM SOURCE by `$axiom`, not
# `$axiom` itself: this gate exists to test `self_host/format.ax`, and
# `$axiom` may be an older seed-descended binary that predates the change
# being tested.
gate_build_axc axc

# ---------------------------------------------------------------
# 1. The zoo, against the golden it has always had.
# ---------------------------------------------------------------
echo "== zoo: the normal form, against the checked-in golden =="
golden="$repo_root/tests/fmt/syntax-zoo.expected.ax"
if [[ ! -s "$golden" ]]; then
  # A golden with no content agrees with everything, which is the
  # failure that looks like success.
  echo "FAIL: $golden is missing or empty"
  failed=$((failed + 1))
else
  cp "$repo_root/tests/fmt/syntax-zoo.ax" "$work/zoo.ax"
  if ! "$axc" fmt "$work/zoo.ax" >/dev/null 2>&1; then
    echo "FAIL zoo: the formatter refused it"
    failed=$((failed + 1))
  elif ! cmp -s "$work/zoo.ax" "$golden"; then
    echo "FAIL zoo: the normal form is no longer $golden"
    diff "$golden" "$work/zoo.ax" | head -12 | sed 's/^/     /'
    failed=$((failed + 1))
  else
    echo "ok   the zoo formats to the golden ($(wc -l <"$golden" | tr -d ' ') lines)"
  fi
  # The golden must also be a fixed point of the printer. Nothing in the
  # comparison above says so: a printer that formats the zoo correctly
  # and its own output differently would pass it.
  cp "$golden" "$work/zoo-again.ax"
  if ! "$axc" fmt "$work/zoo-again.ax" >/dev/null 2>&1 \
     || ! cmp -s "$work/zoo-again.ax" "$golden"; then
    echo "FAIL zoo: the golden is not a fixed point of the formatter"
    failed=$((failed + 1))
  fi
fi

# ---------------------------------------------------------------
# 2. The corpus: two snapshots of the tree, one of them formatted, used
#    by everything below.
#
# Formatting happens in a COPY rather than in place because the tree is
# the input to the comparison - the original bytes are half of every
# preservation claim, and a gate that formats the working tree destroys
# the thing it was measuring. Two copies rather than one because the
# other half has to be a snapshot too: `$orig` and `$copy` are the same
# bytes taken at the same instant, so nothing in this sweep can be
# confused by an edit landing while it runs. `$copy` is also what gets
# rebuilt in 6.
# ---------------------------------------------------------------
echo "== corpus: formatting a copy of the tree =="
orig="$work/orig"
copy="$work/copy"
mkdir -p "$orig"
tar -cf - stdlib self_host tests | (cd "$orig" && tar -xf -)
cp -R "$orig" "$copy"

: > "$work/observed"
: > "$work/pairs.txt"
swept=0; refused=0; nonidem=0; dirty_after=0; wrote_on_refusal=0
# Enumerated from the SNAPSHOT, and hashed from it, never from the
# working tree. A file edited or added while the sweep runs would
# otherwise be recorded as the new source mapping to the old file's
# formatted bytes - a mismatch against the table that says nothing about
# the formatter. Measured the hard way: a preservation run reported 3
# lost comments and 3 lost strings in `self_host/main.ax` that were only
# ever an edit landing between the copy and the compare.
for af in $(find "$orig" -name '*.ax' | sort); do
  f="${af#"$orig"/}"
  swept=$((swept + 1))
  src_h="$(shasum -a 256 "$af" | cut -d' ' -f1)"
  if ! "$axc" fmt "$copy/$f" >/dev/null 2>&1; then
    refused=$((refused + 1))
    printf '%s REFUSED %s\n' "$src_h" "$f" >> "$work/observed"
    # A refusal is allowed to happen; writing anything while refusing is
    # not. `fmt` refuses precisely when it is about to change meaning.
    cmp -s "$copy/$f" "$af" || {
      echo "FAIL $f: the formatter refused it and wrote to it anyway"
      wrote_on_refusal=$((wrote_on_refusal + 1)); }
    continue
  fi
  printf '%s %s %s\n' "$src_h" "$(shasum -a 256 "$copy/$f" | cut -d' ' -f1)" "$f" \
    >> "$work/observed"
  echo "$af $copy/$f" >> "$work/pairs.txt"

  # Idempotence, and the `--check` surface agreeing with the `fmt`
  # surface about its own output.
  cp "$copy/$f" "$work/again.ax"
  if ! "$axc" fmt "$work/again.ax" >/dev/null 2>&1 \
     || ! cmp -s "$work/again.ax" "$copy/$f"; then
    echo "FAIL $f: formatting is not idempotent"
    diff "$copy/$f" "$work/again.ax" | head -6 | sed 's/^/     /'
    nonidem=$((nonidem + 1))
  fi
  if ! "$axc" fmt --check "$copy/$f" >/dev/null 2>&1; then
    echo "FAIL $f: --check calls the formatter's own output unformatted"
    dirty_after=$((dirty_after + 1))
  fi
done
echo "     $swept files swept, $refused refused"
if [[ $swept -lt 420 ]]; then
  echo "FAIL: the sweep read $swept files; the floor is 420 (451 today) - a tree is missing from the find"
  failed=$((failed + 1))
fi
failed=$((failed + nonidem + dirty_after + wrote_on_refusal))
if [[ $nonidem -eq 0 && $dirty_after -eq 0 ]]; then
  echo "ok   $((swept - refused)) files format to a fixed point that --check calls clean"
fi

# ---------------------------------------------------------------
# 3. The corpus golden: sha256(source) -> sha256(formatted).
#
# Joined on the source hash, so a file edited since the table was
# materialized simply has no entry to disagree with. Everything the
# table still covers has to match exactly.
# ---------------------------------------------------------------
echo "== corpus: formatted output against tests/fmt/corpus-fmt.golden =="
table="$repo_root/tests/fmt/corpus-fmt.golden"
if [[ ! -s "$table" ]]; then
  echo "FAIL: $table is missing or empty"
  failed=$((failed + 1))
else
  # LC_ALL=C throughout: `join` refuses to answer for input its own
  # collation says is unsorted, and a locale that sorts differently from
  # the sort that produced the file is a silent way to join nothing.
  grep -v '^#' "$table" | grep . | LC_ALL=C sort > "$work/table.sorted"
  LC_ALL=C sort "$work/observed" > "$work/observed.sorted"
  entries="$(wc -l <"$work/table.sorted" | tr -d ' ')"
  distinct="$(awk '{print $2}' "$work/table.sorted" | LC_ALL=C sort -u | wc -l | tr -d ' ')"
  LC_ALL=C join -j 1 -o 0,1.2,2.2,1.3 "$work/table.sorted" "$work/observed.sorted" \
    > "$work/joined"
  hits="$(wc -l <"$work/joined" | tr -d ' ')"
  awk '$2 != $3 {print "     " $4 ": golden says " $2 ", the formatter produced " $3}' \
    "$work/joined" > "$work/table.bad"
  bad="$(wc -l <"$work/table.bad" | tr -d ' ')"
  if [[ $bad -gt 0 ]]; then
    echo "FAIL corpus: $bad file(s) format to something other than the golden"
    head -10 "$work/table.bad"
    failed=$((failed + 1))
  fi
  if [[ $entries -lt 420 ]]; then
    echo "FAIL: the table has $entries entries; the floor is 420 (451 today)"
    failed=$((failed + 1))
  fi
  # A table of one repeated value would be satisfied by a formatter that
  # emits the same bytes for every input.
  if [[ $distinct -lt 150 ]]; then
    echo "FAIL: the table's $entries entries carry only $distinct distinct outputs"
    failed=$((failed + 1))
  fi
  # Retirement is expected; retirement of everything is the vacuum this
  # gate is built to refuse. Regenerate per the golden's header when the
  # hit count nears the floor.
  if [[ $hits -lt 380 ]]; then
    echo "FAIL: only $hits of $entries table entries still match a file in the tree;"
    echo "      the floor is 380 (451 of 451 hit today) - the table has decayed and must be regenerated"
    failed=$((failed + 1))
  elif [[ $bad -eq 0 ]]; then
    echo "ok   $hits of $entries pinned source->formatted mappings reproduced"
  fi

  # THE OTHER DIRECTION, and it is the one that went unnoticed. The hit
  # count above measures how much of the TABLE is still live; it says
  # nothing about how much of the TREE the table covers. On 2026-08-22
  # those two numbers had come apart completely: 308 of 354 entries
  # still matched - comfortably above the floor, reported as healthy -
  # while 143 of the 451 `.ax` files in the tree had no entry at all,
  # among them 17 of the 22 compiler sources. A formatter bug in
  # `codegen.ax`'s shape would have had nothing to disagree with.
  unpinned=$(( $(wc -l <"$work/observed.sorted" | tr -d ' ') - hits ))
  if [[ $unpinned -gt 60 ]]; then
    echo "FAIL: $unpinned .ax files in the tree have no entry in the table"
    echo "      (the ceiling is 60) - regenerate per the golden's header"
    failed=$((failed + 1))
  else
    echo "ok   $unpinned .ax file(s) in the tree are not pinned by the table"
  fi
fi

# ---------------------------------------------------------------
# 4. The parity bank: refusals and rewrites, status and bytes.
# ---------------------------------------------------------------
echo "== parity bank: tests/fmt/parity.golden =="
parity_golden="$repo_root/tests/fmt/parity.golden"
mkdir -p "$work/parity-out"
: > "$work/parity.out"
cases=0; ok_cases=0; refused_cases=0
for f in "$repo_root"/tests/fmt/parity/*.axp; do
  [[ -f "$f" ]] || continue
  cases=$((cases + 1))
  name="$(basename "$f")"
  cp "$f" "$work/case.ax"
  # Ask the COMPILER about the case before asking the formatter. This bank
  # compares the formatter against its own previous output, so nothing in
  # it ever noticed that two of its cases - `170-empty-tuple` `(fn (f) ())`
  # and `172-empty-brace-body` `(fn (f) {})` - killed the compiler outright,
  # and that `100-empty-form-dropped` was a file the compiler REFUSES which
  # the formatter rewrote into one it accepts, reporting OK. A signal is the
  # one answer no golden can record, so it is asserted here rather than
  # compared.
  cp "$f" "$work/parity-in.ax"
  ( cd "$work" && "$axc" --diagnostic-format=ai check parity-in.ax ) >/dev/null 2>&1
  in_st=$?
  if [[ $in_st -ge 128 ]]; then
    echo "FAIL parity/$name: reading the case killed the compiler (exit $in_st)"
    failed=$((failed + 1))
  fi
  "$axc" fmt "$work/case.ax" >/dev/null 2>&1; s=$?
  echo "### $name (exit $s)" >> "$work/parity.out"
  if [[ $s -eq 0 ]]; then
    ok_cases=$((ok_cases + 1))
    cat "$work/case.ax" >> "$work/parity.out"
    cp "$work/case.ax" "$work/parity-out/$name"
    echo "$f $work/parity-out/$name" >> "$work/pairs.txt"
    # Same two properties the corpus gets: a fixed point that `--check`
    # agrees is clean.
    cp "$work/case.ax" "$work/case-again.ax"
    if ! "$axc" fmt "$work/case-again.ax" >/dev/null 2>&1 \
       || ! cmp -s "$work/case-again.ax" "$work/case.ax"; then
      echo "FAIL parity/$name: formatting is not idempotent"
      failed=$((failed + 1))
    fi
  else
    refused_cases=$((refused_cases + 1))
    cmp -s "$work/case.ax" "$f" || {
      echo "FAIL parity/$name: refused, and wrote to the file anyway"
      failed=$((failed + 1)); }
  fi
done
echo "     $cases cases, $ok_cases formatted, $refused_cases refused"
if [[ $cases -lt 20 ]]; then
  echo "FAIL: the parity bank has $cases cases; the floor is 20"
  failed=$((failed + 1))
fi
# Both outcomes have to be represented, or the bank cannot tell a
# formatter that always succeeds from one that always refuses.
if [[ $ok_cases -eq 0 || $refused_cases -eq 0 ]]; then
  echo "FAIL: the bank produced only one outcome ($ok_cases formatted, $refused_cases refused)"
  failed=$((failed + 1))
fi
if [[ ! -s "$parity_golden" ]]; then
  echo "FAIL: $parity_golden is missing or empty"
  failed=$((failed + 1))
elif ! diff <(sed -n '/^### /,$p' "$parity_golden") "$work/parity.out" >"$work/parity.diff" 2>&1; then
  echo "FAIL parity: the bank's status or bytes differ from the golden"
  head -14 "$work/parity.diff" | sed 's/^/     /'
  failed=$((failed + 1))
else
  echo "ok   all $cases cases match the golden, status and bytes"
fi

# ---------------------------------------------------------------
# 5. Preservation: what the formatted bytes still contain.
#
# The half no re-bless can reach. verify-fmt.py never reads a golden -
# it reads the source and its formatted output and compares them with a
# scanner written independently of the compiler's.
# ---------------------------------------------------------------
echo "== preservation: comments, strings and chars, against the source =="
if ! python3 "$repo_root/tests/fmt/verify-fmt.py" "$work/pairs.txt"; then
  echo "FAIL preservation: formatting changed something it may not change"
  failed=$((failed + 1))
fi

# ---------------------------------------------------------------
# 5b. The formatted output is source THIS compiler can read.
#
# The formatter is a second implementation of the grammar, with its own
# scanner (`format.ax` says so at the top: it needs the spans of things
# the token stream discards). `fmtFormat`'s three-part verification -
# rescan, comments preserved, fixed point - runs entirely inside that
# second implementation. Nothing anywhere handed a formatted file back
# to the LEXER, and the two disagreed for as long as the self-hosted
# compiler has been the only one:
#
#   $ cat tests/fmt/parity/110-nested-block-comment.axp
#   #| outer #| inner |# still |#
#   (fn (f) 1)
#   $ axiom fmt case.ax   -> exit 0, "already formatted"
#   $ axiom check case.ax -> E AX1001 "unexpected character `#`"
#
# `#| ... |#` is documented in README.md and docs/reference.md, was
# implemented by stage0, and is scanned by `format.ax` - and was refused
# by `lexer.ax`, so `fmt` was blessing files the compiler could not
# read. Section 6 below could not see it: it compiles the formatted
# TREE, and no file in the tree has a block comment.
#
# Only AX1xxx and AX2xxx count. A formatted parity case may legitimately
# not type-check - the bank is full of programs about undefined names -
# but every one of them has to LEX and PARSE, whatever the formatter
# accepted on the way in. That asymmetry is deliberate: `fmt` migrates
# legacy spellings (`$` becomes `!`, `define` becomes `fn`), so it takes
# input the compiler refuses on purpose. What it may never do is EMIT
# any.
# ---------------------------------------------------------------
echo "== the formatted output lexes and parses =="
unreadable=0; read_swept=0
while read -r src out; do
  [[ -f "$out" ]] || continue
  read_swept=$((read_swept + 1))
  # From the formatted copy of the tree, so an `(import Mem)` in a
  # formatted corpus file resolves the same way section 6 resolves it.
  axdl="$( (cd "$copy" && AXIOM_STDLIB="$copy/stdlib" \
            "$axc" --diagnostic-format=ai check "$out") 2>&1 )"
  read_st=$?
  # A process killed by a signal prints nothing, so it satisfies a check
  # written as "the output must not contain a diagnostic". That is not a
  # hypothetical: `tests/fmt/parity/170-empty-tuple.axp` is `(fn (f) ())`,
  # the formatter wrote it back out, `check` died of SIGSEGV reading it,
  # the grep below found no AX2xxx line, and this section reported ok - in
  # CI, for as long as that case has existed. The status has to be read
  # BEFORE the output is believed.
  if [[ $read_st -ge 128 ]]; then
    echo "FAIL $(basename "$src"): reading its formatted output killed the compiler (exit $read_st)"
    unreadable=$((unreadable + 1))
  elif grep -qE '^[EW] AX[12][0-9]{3} ' <<<"$axdl"; then
    echo "FAIL $(basename "$src"): its formatted output does not lex or parse"
    grep -E '^[EW] AX[12][0-9]{3} ' <<<"$axdl" | head -2 | sed 's/^/     /'
    unreadable=$((unreadable + 1))
  fi
done < "$work/pairs.txt"
failed=$((failed + unreadable))
# The floor is the usual one: this check reports silence, and a
# `pairs.txt` that stopped being written would report the same silence
# from zero files.
if [[ $read_swept -lt 440 ]]; then
  echo "FAIL: only $read_swept formatted outputs were re-read; the floor is 440 (468 today)"
  failed=$((failed + 1))
elif [[ $unreadable -eq 0 ]]; then
  echo "ok   $read_swept formatted outputs carry no lexical or syntactic error"
fi

# ---------------------------------------------------------------
# 6. Behaviour: the formatted tree still compiles, and the compiler it
#    produces still formats the zoo to the golden.
#
# Everything above is textual. This is the check that the formatted
# source still MEANS what it meant: 20k lines of Axiom, type-checked by
# being compiled, and the resulting binary held to the same golden.
# The formatter's own round-trip check cannot see a change of meaning
# that re-parses - `((Red) 1)` collapsing to the catch-all pattern
# `(Red 1)` compiled and ran and answered wrongly.
# ---------------------------------------------------------------
echo "== behaviour: rebuilding the compiler from the formatted tree =="
if ! (cd "$copy" && AXIOM_STDLIB="$copy/stdlib" "$axc" build \
        --input self_host/main.ax --output "$work/axc2") >"$work/build2.log" 2>&1; then
  echo "FAIL: the formatted tree no longer builds the compiler"
  tail -20 "$work/build2.log" | sed 's/^/     /'
  failed=$((failed + 1))
else
  cp "$repo_root/tests/fmt/syntax-zoo.ax" "$work/zoo2.ax"
  if ! "$work/axc2" fmt "$work/zoo2.ax" >/dev/null 2>&1 \
     || ! cmp -s "$work/zoo2.ax" "$golden"; then
    echo "FAIL: the compiler built from the formatted tree does not reproduce the zoo golden"
    diff "$golden" "$work/zoo2.ax" | head -10 | sed 's/^/     /'
    failed=$((failed + 1))
  else
    echo "ok   the formatted tree builds, and its compiler reproduces the golden"
  fi
  # The zoo is the one corpus file that exists only to be parsed, so it
  # is also the one whose formatted form is worth type-checking on its
  # own: it carries `type`, `trait` and `impl`, all of which were once
  # formatted into source that did not parse.
  if ! (cd "$copy" && AXIOM_STDLIB="$copy/stdlib" "$axc" --diagnostic-format=ai \
          check tests/fmt/syntax-zoo.ax) >"$work/zoocheck.log" 2>&1; then
    echo "FAIL: the formatted syntax zoo no longer type-checks"
    head -10 "$work/zoocheck.log" | sed 's/^/     /'
    failed=$((failed + 1))
  fi
fi

# ---------------------------------------------------------------
# 7. The cases a file cannot carry.
# ---------------------------------------------------------------
echo "== driver: empty, missing, and --check =="
: > "$work/empty.ax"
"$axc" fmt "$work/empty.ax" >/dev/null 2>&1; e=$?
if [[ "$e" != 0 || -s "$work/empty.ax" ]]; then
  echo "FAIL: an empty file must format to an empty file with exit 0 (exit $e, $(wc -c <"$work/empty.ax" | tr -d ' ') bytes)"
  failed=$((failed + 1))
fi

"$axc" fmt "$work/does-not-exist.ax" >/dev/null 2>&1; m=$?
if [[ "$m" == 0 || -e "$work/does-not-exist.ax" ]]; then
  echo "FAIL: a missing file must be refused, not created (exit $m)"
  failed=$((failed + 1))
fi

printf '(fn  (f)   1)\n' > "$work/dirty.ax"
cp "$work/dirty.ax" "$work/dirty-orig"
"$axc" fmt --check "$work/dirty.ax" >/dev/null 2>&1; c1=$?
"$axc" fmt "$work/dirty.ax" --check >/dev/null 2>&1; c2=$?
if [[ "$c1" != 1 || "$c2" != 1 ]]; then
  echo "FAIL: --check on an unformatted file must exit 1 in either argument order (got $c1, $c2)"
  failed=$((failed + 1))
fi
if ! cmp -s "$work/dirty.ax" "$work/dirty-orig"; then
  echo "FAIL: --check wrote to the file"
  failed=$((failed + 1))
fi
# And the other verdict, so `--check` is not just an alias for exit 1.
cp "$golden" "$work/clean.ax"
"$axc" fmt --check "$work/clean.ax" >/dev/null 2>&1; c3=$?
if [[ "$c3" != 0 ]]; then
  echo "FAIL: --check on an already-formatted file must exit 0 (got $c3)"
  failed=$((failed + 1))
fi

echo
if [[ $failed -eq 0 ]]; then
  echo "fmt-selfhost: all checks passed"
else
  echo "fmt-selfhost: $failed check(s) failed"
  exit 1
fi
