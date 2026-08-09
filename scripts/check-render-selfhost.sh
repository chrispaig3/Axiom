#!/usr/bin/env bash
# The native human diagnostic renderer, pinned without a second compiler.
#
# WHAT THIS USED TO PIN AND NO LONGER CAN. The layout itself was never a
# byte-differential against stage0, and that decision has a paper trail
# (docs/self-hosting.md): stage0's human renderer was the third-party
# `ariadne` crate, whose per-character stream is an internal of a
# compiler being retired rather than a design of Axiom's. But two checks
# per case still reached for stage0 anyway - the exit status had to
# equal stage0's, and stdout had to be byte-equal to stage0's - and
# neither could be left in place once the Rust tree goes, because a
# differential does not FAIL when its reference disappears. Repoint
# `$axiom` at a self-hosted binary and `s1 != s0` becomes `s1 != s1`,
# `cmp a.out h.out` compares a file with itself, and the sweep reports
# 52 cases, zero divergences, exit 0, nothing tested.
#
# WHAT IT PINS NOW. Six checks per case, of which exactly two are
# golden comparisons:
#
#   1. GOLDEN. tests/diagnostics/NAME.human equals the renderer's
#      stderr, byte for byte.
#
#   2. EXIT STATUS AND STDOUT, DERIVED FROM THE AXDL GOLDEN. A `^E `
#      line in NAME.axdl means the case must FAIL: status 1, empty
#      stdout. No `^E ` line means it must SUCCEED: status 0, stdout
#      exactly `OK`. This is a fact about the golden, not about the
#      renderer. NAME.axdl records the severity of every diagnostic the
#      case produces, and "an error was reported" and "the compile
#      failed" are one statement said twice; the two halves are
#      produced by different parts of the compiler - the status by the
#      driver, the severity by a file checked in beside the one under
#      test - so they agree only when both are right. That is what the
#      stage0 comparison bought, bought without stage0.
#      Not decoration: a warnings-only file exited 1 here and 0 under
#      stage0 for a month with the gate green (probed and fixed
#      2026-08-07). 330-axtag-mismatch is that case, and it is the
#      corpus's only status-0 case - if it ever stops being one the
#      derivation degenerates into a constant, which the
#      both-classes-present check below refuses outright.
#
#   3. THE AXDL GOLDEN READ AS A DOCUMENT, BLOCK BY BLOCK, AGAINST THE
#      HUMAN ONE. The human surface is split on blank lines; the k-th
#      block must be the rendering of the k-th AXDL line, and every
#      assertion below is scoped to THAT BLOCK and anchored at both
#      ends. Block count = one per AXDL diagnostic, plus one trailer
#      block iff there is an error. Then, per block: the first line
#      must EQUAL `<severity>[<CODE>]: <message>`; a line must EQUAL
#      `--> FILE:L:C` (leading gutter spaces aside), with the
#      end-of-file remap described at the assertion; the primary line
#      must appear in the gutter; the caret row must EQUAL C spaces
#      then exactly `run` carets after the bar, and the related row
#      RC spaces then exactly `rrun` dashes then the related note; and
#      each help must EQUAL `= help: <text>` after undoing AXDL's `\\`
#      and `\"` escaping. Widths and columns are computed from the
#      span - for a span that crosses lines, from the FIXTURE's line
#      length, because the renderer underlines to end of line and the
#      AXDL does not say how long that line is. The block must draw
#      exactly ONE caret row and exactly as many dash rows as the AXDL
#      gives it related spans (one, or none), so a row the diagnostic
#      never asked for is a failure rather than a free extra. Finally
#      the golden's last line must EQUAL the trailer counting exactly
#      the E lines.
#
#      Why block-scoped and anchored rather than `grep -qF`: see THE
#      HOLLOW VERSION below. An unanchored substring search over the
#      whole file pins a MULTISET of strings. It cannot see order, it
#      cannot see which message belongs to which code, and it cannot
#      see anything ADDED - not a wider caret run, not a debug tag
#      welded onto every heading.
#
#   4. EVERY SOURCE LINE THE SNIPPET QUOTES, AGAINST THE FIXTURE'S OWN
#      BYTES. Each `N | TEXT` row must have TEXT equal to line N of the
#      file that the enclosing `--> FILE:L:C` names, resolved per
#      snippet - a multi-file case quotes an imported module, and
#      360-imported-module-body renders two snippets from two different
#      files, so a check that assumed one fixture per case would have
#      compared BadBody.ax's line 2 against the case file's. 101 rows
#      over the corpus.
#
#   5. THE ESCAPE STREAM, AGAINST THE PALETTE self_host/style.ax
#      DECLARES. The human surface is coloured and neither of the
#      artifacts checks 3 and 4 read has any colour in it, so those two
#      compare a STRIPPED copy of the golden and say nothing about the
#      escapes - and check 1, which does see them, is the re-blessable
#      half. Check 5 is the third artifact: every SGR parameter string
#      in the golden must be one the compiler's own palette table
#      declares, every line's sequences must read open/reset in pairs so
#      no colour bleeds past a newline, and no escape may appear after a
#      snippet's gutter bar or anywhere on the trailer - the source text
#      a snippet quotes is the fixture's bytes, and the trailer is
#      printed in the machine formats too. AXIOM_BLESS writes
#      NAME.human; it cannot write self_host/style.ax.
#
#   6. THE JSON RENDERING, in the same two halves. 6a is a `cmp`
#      against NAME.json, minus the trailer, which is not JSON and is
#      pinned by the human golden anyway - dropped here the way
#      check-diagnostics.sh drops it from AXDL. 6b is
#      tests/diagnostics/verify-json.py, which derives every field of
#      every object from NAME.axdl and the fixture: one object per AXDL
#      line in the same order, severity from the sigil, the span's
#      line/col equal to the AXDL's, `char_start`/`char_end`
#      RECOMPUTED from the fixture as character offsets, and label,
#      related, notes, help and expansion from the `#`, `^`, `!`, `?`
#      and `&` fields. The comparison is on the whole decoded object,
#      so an invented key fails as loudly as a dropped one.
#      Before this the JSON renderer had no golden and no gate at all.
#
# WHY THAT IS ADEQUATE WITHOUT A SECOND COMPILER. Checks 3, 4 and 5
# cannot be satisfied by regenerating anything this script writes.
# `AXIOM_BLESS=1` rewrites NAME.human and nothing else; check 3 reads
# NAME.axdl, a different checked-in artifact, check 4 reads the fixture,
# which is the INPUT and cannot be blessed at all, and check 5 reads the
# compiler's source. A renderer that quoted the
# wrong line, quoted the right line from the wrong file, put a caret one
# column off, sized it to the wrong width, printed a message it did not
# diagnose, printed its diagnostics in the wrong order, or exited 0 on a
# file it had just reported an error for, fails here with a freshly
# blessed golden sitting in the tree. Drilled rather than assumed - the
# comparators are negative-tested at the foot of this script, on
# corrupted copies, every run - and a bless whose result fails checks
# 2/3/4 is REFUSED on the spot rather than left to go green later
# (check-diagnostics.sh has refused on the same grounds since it grew
# its span verifier).
#
# THE HOLLOW VERSION, AND WHAT IT COST. Measured 2026-08-08. Check 3
# used to be 692 unanchored `grep -qF` hits over the whole golden. Three
# one-token renderer defects, each re-blessed into all 52 goldens, each
# left this gate at EXIT=0, "52 passed, 0 failed", zero FAIL lines:
#
#   A  render.ax:171 `(repByte run ch)` -> `(repByte (+ run 1) ch)`.
#      Every caret run and every dash run one character too wide;
#      040's 4-character span 4:6-10 rendered `^^^^^`. Invisible
#      because `grep -qF -- "| ${pad}${carets}"` is a SUBSTRING search
#      and `"|      ^^^^"` is a prefix of `"|      ^^^^^"`. A span that
#      is too LONG - the ordinary direction of an end-offset bug - could
#      never fail. Now: the caret row is an equality on everything after
#      the bar, and the drill at the foot widens a real caret run by one
#      character every run to prove the comparator still sees it.
#
#   B  render.ax:272 `(vecGet ds i)` -> `(vecGet ds (- (- (vecLen ds) 1)
#      i))`, reversing the human renderer's emission order only (AXDL is
#      rendered elsewhere and stayed correct). 130-order-all-three went
#      from AX3006/AX3015/AX3013 to AX3013/AX3015/AX3006. Invisible
#      because nothing paired the k-th AXDL line with the k-th rendered
#      block - two of the corpus's cases (040-order-dup-before-missing,
#      130-order-all-three) exist for no other purpose than to pin
#      emission order and the derived half could not see it. Now: block
#      k is the rendering of AXDL line k, and the drill reverses two
#      blocks of a real golden every run.
#
#   C  render.ax:211 `(strConcat msg "\n")` -> `(strConcat msg " [debug:
#      span=?]\n")`, welding a debug tag onto every heading. Invisible
#      because `grep -qF -- "$msg"` means "appears somewhere as a
#      substring", so anything appended, prepended or interleaved was
#      free. Now: the heading is an equality against
#      `<severity>[<CODE>]: <message>` built from the AXDL line, which
#      pins severity, code, text and the absence of anything else in one
#      statement.
#
# RE-RUN AGAINST THOSE SAME THREE BUILDS with this version in place, in
# a mirror tree (self_host a patchable copy, tests/diagnostics a
# writable copy, stdlib and .axiom-bin symlinked) so neither self_host/
# nor tests/ in the real tree was touched. `AXIOM_BLESS=1` still writes
# all 52 goldens - it has to, it is only writing down what the compiler
# said - and is then REFUSED; running the gate again over those freshly
# blessed goldens exits 1 -
#
#   A  bless REFUSED. Plain run: exit 1, 0 passed / 52 failed, 102 FAIL
#      lines - every one of the 86 caret-row equalities and all 15
#      dash-row equalities, because a run one character too wide is now
#      an inequality rather than a prefix. 010 reads `FAIL
#      010-duplicate-fn (block 1: no caret row at col 6 width 4 for span
#      010-duplicate-fn.ax:3:6-10)`.
#   B  bless REFUSED. Plain run: exit 1, 29 passed / 24 failed, 191 FAIL
#      lines. The 24 are the 23 cases that emit more than one
#      diagnostic - the only ones an order bug can show up in - plus
#      drill(g). 44 headings, 44 caret rows, 29 gutter lines, 12 helps
#      and 6 dash-row counts disagree; 040 reads `block 1 heading is
#      `error[AX3015]: `ghost` has a signature but no definition``; the
#      AXDL calls for `error[AX3006]: duplicate definition `main```,
#      and block 2 the mirror image.
#   C  bless REFUSED. Plain run: exit 1, 0 passed / 52 failed, 87 FAIL
#      lines - all 86 heading equalities. 010 reads `block 1 heading is
#      `error[AX3006]: duplicate definition `main` [debug: span=?]``;
#      the AXDL calls for `error[AX3006]: duplicate definition `main```.
#
# In each the 53rd/24th failure is drill(g) reporting that its own
# baseline golden no longer satisfies its AXDL - the reorder drill is
# the one corruption that is an involution, so it says which of the two
# is broken instead of blaming the comparator. Check 4 saw none of the
# three, which is the point of keeping both halves: it reads the
# fixture, and all three defects are downstream of the input.
#
# The pristine tree, same script: 52 passed, 0 failed, 936 AXDL facts,
# 101 source rows, 51 fail/1 ok by derivation, exit 0. Counting them
# against the 692 they replaced is not the comparison that matters: 566
# of those 692 were unanchored substring greps, and none of the ones
# here are.
#
# THE SCAFFOLDING THAT LANDED BEFORE THE RENDERER DID. Check 5, the
# colour stripping in checks 3 and 4, the display-column and truncation
# arithmetic, and the `#`/`!`/`&`/`~>` AXDL field arms were all added in
# one run that changed NO existing assertion: block/head/loc/msg/caret/
# dash/gutter came out at 208/86/86/78/172/101/101 before and after. The
# derivations are the identity on this corpus - no fixture has a tab,
# the longest line is 83 columns against a 160-column window, and no
# diagnostic emits a label, a note or an expansion frame yet - so they
# are provably neutral, and each is drilled on synthetic input at the
# foot rather than left to be tested by the step that finally needs it.
# Adversarially checked at introduction, each defect caught by exactly
# the check that owns it and no other: a `disp_col` seeded one column
# off fails 54 cases on the caret row; a `strip_ansi` that strips
# nothing is seen only by drill (h1); a palette that declares everything
# is seen only by drill (h3).
#
# PROVENANCE FOR THE DERIVED STATUS RULE. Measured 2026-08-08, while
# both compilers still existed: over all 52 cases the rule "an E line
# means status 1 with empty stdout, no E line means status 0 with `OK`"
# reproduces stage0's observed status and stdout exactly, and the
# self-hosted compiler's. That is the last moment there were two
# implementations to take that measurement from.
#
# Regenerate a golden deliberately, never casually:
#   AXIOM_BLESS=1 scripts/check-render-selfhost.sh          # all
#   AXIOM_BLESS=1 scripts/check-render-selfhost.sh 010      # one
# A bless still has to pass checks 2, 3 and 4 - the ones that read the
# AXDL golden and the fixture rather than the file being written - or it
# is refused with the new goldens left on disk to look at.
#
# Usage:
#   scripts/check-render-selfhost.sh          # every case
#   scripts/check-render-selfhost.sh 010      # one case, by prefix
#                                             # (a filtered run skips
#                                             #  the corpus floors and
#                                             #  the drills; it is a
#                                             #  probe, not the gate)

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

filter="${1:-}"
bless="${AXIOM_BLESS:-0}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Same work-dir shape as check-diagnostics.sh, for the same reason: the
# cases run from $work so the filename the renderer prints is a bare
# `NAME.ax`, and the helper modules for multi-file cases are copied flat
# because a module name is its filename stem.
ln -s "$repo_root/stdlib" "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"
ln -s "$repo_root/tests" "$work/tests"
cp "$repo_root"/tests/diagnostics/mods/*.ax "$work/" 2>/dev/null || true

# The renderer under test is the one built FROM SOURCE by `$axiom`, not
# `$axiom` itself: this gate exists to test self_host/, and `$axiom` may
# be an older seed-descended binary that predates the change being
# tested.
if ! "$axiom" build --input self_host/main.ax --output "$work/axc" >"$work/build.log" 2>&1; then
  echo "FAIL: could not build the compiler under test" >&2
  tail -20 "$work/build.log" >&2
  exit 1
fi

# ------------------------------------------------------------------
# helpers
# ------------------------------------------------------------------

# A basename out of a diagnostic maps back to a file in the tree. Three
# places, because a case that deliberately does not parse is spelled
# `.axbad` (check-fmt.sh and check-tree-sitter.sh sweep every `*.ax` and
# require all of them to parse) and a helper module lives under mods/.
resolve_fixture() {
  local b="$1" c
  for c in "tests/diagnostics/$b" "tests/diagnostics/${b%.ax}.axbad" \
           "tests/diagnostics/mods/$b"; do
    [[ -f "$c" ]] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# Line N of a file, and its length in CHARACTERS rather than bytes. The
# renderer counts columns in characters - 070-nonascii-same-line pins
# that, its em dash is three bytes and one column - and both `awk`'s
# `length` and `wc -c` here count bytes, while `wc -m` counts whatever
# the ambient locale says. Every byte that is not a UTF-8 continuation
# byte starts exactly one character, which needs no locale at all.
fixture_line() {
  awk -v n="$2" 'NR==n {print; exit}' "$1"
}
char_len() {
  printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | LC_ALL=C wc -c | tr -d ' '
}

# ------------------------------------------------------------------
# display columns, tab expansion, truncation
# ------------------------------------------------------------------
# The renderer quotes a source line with its tabs expanded and, past a
# width, only a window of it. A CHARACTER column (what AXDL reports, what
# colOf counts) and a DISPLAY column (where the caret actually lands)
# stop being the same number the moment a tab appears before the span.
# The rules, restated here so this gate DERIVES the quoted row and the
# caret pad from the fixture rather than reading them off the golden:
#
#   * a tab advances to the next multiple of TAB_WIDTH;
#   * every other character is one column wide, and a UTF-8 continuation
#     byte is not a character at all - the rule char_len already uses,
#     and the reason 070-nonascii-same-line reads column 22 where a byte
#     count says 24;
#   * a line wider than LINE_MAX is quoted as a window: it starts
#     LEFT_CTX columns before the span, runs LINE_MAX columns, is pushed
#     back to end at the line's end if that overshoots, and is marked
#     `...` on whichever side was elided.
#
# ALL THREE ARE THE IDENTITY ON TODAY'S CORPUS - no fixture contains a
# tab and the longest line is 83 columns against a 160-column window - so
# this whole section changes no assertion in the run that introduces it.
# That is the point: the gate for a renderer behaviour lands before the
# behaviour, drilled on synthetic input (see drill (i) at the foot), so
# that the step which adds tab handling is not also the step that writes
# the check on it.
TAB_WIDTH=4
LINE_MAX=160
LEFT_CTX=20

# Byte values, so a UTF-8 continuation byte can be recognised without a
# locale. `LC_ALL=C` makes awk's substr index bytes, which is what lets
# the same loop count characters and copy them intact.
awk_ord='BEGIN { for (n = 1; n < 256; n++) ord[sprintf("%c", n)] = n }
         function iscont(c) { return (ord[c] >= 128 && ord[c] < 192) }'

# A line with its tabs expanded.
expand_tabs() {
  printf '%s' "$1" | LC_ALL=C awk -v tw="$TAB_WIDTH" "$awk_ord"'
    { out = ""; col = 0; n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (c == "\t") { stop = int(col / tw + 1) * tw
                         while (col < stop) { out = out " "; col++ } }
        else { out = out c; if (!iscont(c)) col++ }
      }
      print out }'
}

# Display width of a line, in columns.
disp_width() {
  printf '%s' "$1" | LC_ALL=C awk -v tw="$TAB_WIDTH" "$awk_ord"'
    { col = 0; n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (c == "\t") col = int(col / tw + 1) * tw
        else if (!iscont(c)) col++
      }
      print col }'
}

# The 1-based display column at which the WANT-th character of a line
# begins. A column at or past end of line keeps counting one per
# character, which is where an end-of-file caret sits.
disp_col() {
  printf '%s' "$1" | LC_ALL=C awk -v want="$2" -v tw="$TAB_WIDTH" "$awk_ord"'
    { ch = 0; col = 0; n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (iscont(c)) continue
        ch++
        if (ch == want) { print col + 1; exit }
        if (c == "\t") col = int(col / tw + 1) * tw; else col++
      }
      print col + 1 + (want - ch - 1) }'
}

# Display columns [a, b) of an ALREADY-EXPANDED line (so every character
# is one column wide), with multi-byte characters copied whole.
disp_slice() {
  printf '%s' "$1" | LC_ALL=C awk -v a="$2" -v b="$3" "$awk_ord"'
    { out = ""; col = 0; keep = 0; n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (iscont(c)) { if (keep) out = out c; continue }
        keep = (col >= a && col < b)
        if (keep) out = out c
        col++
      }
      print out }'
}

# The window a line of display width W gets when the span starts at
# 1-based display column S, as `START END` with START 0-based and END
# exclusive. `0 W` means the whole line, which is every case today.
trunc_window() {
  local w="$1" s0=$(( $2 - 1 )) start end
  if (( w <= LINE_MAX )); then printf '0 %s\n' "$w"; return 0; fi
  start=$(( s0 - LEFT_CTX )); (( start < 0 )) && start=0
  end=$(( start + LINE_MAX ))
  if (( end >= w )); then end="$w"; start=$(( w - LINE_MAX )); (( start < 0 )) && start=0; fi
  printf '%s %s\n' "$start" "$end"
}

# ------------------------------------------------------------------
# ANSI
# ------------------------------------------------------------------
# The human surface is colored; the AXDL golden and the fixture it is
# checked against are not. Checks 3 and 4 compare rendered text with text
# derived from those two artifacts, so they read a STRIPPED copy of the
# golden - while check 1's `cmp` stays a raw byte comparison, which is
# what keeps the escape stream itself pinned. Check 5 then asserts the
# escapes are the ones self_host/style.ax declares.
#
# Stripping in the comparator rather than in the renderer is deliberate:
# a gate that asked the compiler for uncolored output would be checking
# the layout of a mode nobody runs.
strip_ansi() {
  LC_ALL=C sed $'s/\x1b\\[[0-9;]*m//g'
}

# Every quoted string on an AXDL line, one `KIND<TAB>TEXT` per output
# line, KIND decided by the STRUCTURAL text that precedes the opening
# quote: the slug and a space introduce the primary message, `^L:C-C2:`
# a related-span note, `?` or `?L:C-C2:` a help, `~>` a suggested
# replacement. The replacement is machine-applied text, not something
# the human surface is required to print, and is dropped; anything that
# matches no rule is reported rather than ignored, because a new AXDL
# field that this parser silently skipped would be a message family
# nobody is checking.
#
# AXDL quotes its strings and escapes `\` and `"` inside them; the human
# surface prints them raw. Comparing the two without undoing that would
# make every message containing a backslash unassertable - which is most
# of the lexer corpus, where the diagnostic IS about an escape sequence.
# Two rules suffice because AXDL emits exactly two: `\\` and `\"`. Both
# are swapped for sentinels before the split, which is also what keeps
# `\\"` (an escaped backslash then a delimiter) from being read as `\`
# followed by an escaped quote, and leaves the remaining `"` all
# structural - so the odd fields of a `"`-split are exactly the strings.
axdl_fields() {
  local line="$1" esc s pre i seen=0
  local help_re='[?]([0-9]+:[0-9]+(-[0-9]+)?:)?$'
  local rel_re='\^[0-9]+:[0-9]+(-[0-9]+)?:$'
  local label_re='#$'
  local note_re='!$'
  local trace_re='&$'
  local -a parts
  esc="${line//\\\\/$'\001'}"
  esc="${esc//\\\"/$'\002'}"
  IFS='"' read -r -a parts <<< "$esc"
  i=1
  while (( i < ${#parts[@]} )); do
    pre="${parts[i-1]}"
    s="${parts[i]}"
    s="${s//$'\002'/\"}"
    s="${s//$'\001'/\\}"
    # The replacement half of a machine-applicable fix. It used to be
    # DROPPED here, on the reasoning that machine-applied text is not
    # something the human surface must print - true until the human
    # surface started printing it. Named rather than discarded so the
    # help-line equality can be extended to cover it.
    if [[ "$pre" == *'~>' ]]; then
      printf 'fix\t%s\n' "$s"
    elif [[ "$pre" =~ $label_re ]]; then
      printf 'label\t%s\n' "$s"
    elif [[ "$pre" =~ $note_re ]]; then
      printf 'note\t%s\n' "$s"
    elif [[ "$pre" =~ $trace_re ]]; then
      printf 'trace\t%s\n' "$s"
    elif [[ "$pre" =~ $help_re ]]; then
      printf 'help\t%s\n' "$s"
    elif [[ "$pre" =~ $rel_re ]]; then
      printf 'rel\t%s\n' "$s"
    elif (( seen == 0 )); then
      printf 'msg\t%s\n' "$s"
      seen=1
    else
      printf 'unknown\t%s\n' "$s"
    fi
    i=$((i + 2))
  done
}

# The block helpers. `GL` is the human golden as an array of lines and
# `BS`/`BE` are the inclusive line ranges of its blank-line-separated
# blocks; both are filled by `read_blocks` and read by everything below
# through bash's dynamic scope.
read_blocks() {
  local f="$1" ln inblk=0
  GL=(); BS=(); BE=()
  NG=0
  while IFS= read -r ln || [[ -n "$ln" ]]; do
    GL[$NG]="$ln"
    NG=$((NG + 1))
  done < "$f"
  NB=0
  local i
  for (( i = 0; i < NG; i++ )); do
    if [[ -n "${GL[$i]}" ]]; then
      if (( inblk == 0 )); then BS[$NB]=$i; inblk=1; fi
      BE[$NB]=$i
    elif (( inblk == 1 )); then
      NB=$((NB + 1)); inblk=0
    fi
  done
  (( inblk == 1 )) && NB=$((NB + 1))
  return 0
}

# Some line of block [s,e], with its leading whitespace removed, equals
# WANT exactly. The leading whitespace is the gutter, whose WIDTH is a
# layout choice with no independent truth (it tracks the widest line
# number in the snippet); everything to the right of it is asserted
# character for character.
block_trim_eq() {
  local s="$1" e="$2" want="$3" i t
  for (( i = s; i <= e; i++ )); do
    t="${GL[$i]}"
    t="${t#"${t%%[![:space:]]*}"}"
    [[ "$t" == "$want" ]] && return 0
  done
  return 1
}

# Some line of block [s,e] is a gutter bar - leading spaces, then `|` -
# whose entire remainder equals WANT. This is the assertion the hollow
# version could not make: `grep -qF "| ${pad}${carets}"` accepted a run
# of carets one longer than the span, because a prefix is a substring.
block_bar_eq() {
  local s="$1" e="$2" want="$3" i ln pre
  for (( i = s; i <= e; i++ )); do
    ln="${GL[$i]}"
    [[ "$ln" == *'|'* ]] || continue
    pre="${ln%%|*}"
    [[ -z "${pre//[[:space:]]/}" ]] || continue
    [[ "${ln#*|}" == "$want" ]] && return 0
  done
  return 1
}

# Some line of block [s,e] matches an ERE.
block_re() {
  local s="$1" e="$2" re="$3" i
  for (( i = s; i <= e; i++ )); do
    [[ "${GL[$i]}" =~ $re ]] && return 0
  done
  return 1
}

# How MANY lines of block [s,e] match an ERE. The equalities above say a
# row with the right geometry exists; these say no second one does. One
# diagnostic underlines one primary span, so a block with two caret rows
# is a renderer emitting something it was never asked for - the same
# class of defect as a caret run one character too wide, and equally
# invisible to a search that stops at the first hit.
block_count_re() {
  local s="$1" e="$2" re="$3" i n=0
  for (( i = s; i <= e; i++ )); do
    [[ "${GL[$i]}" =~ $re ]] && n=$((n + 1))
  done
  printf '%s' "$n"
}

facts=0      # individual assertions made against the AXDL goldens
rows=0       # snippet rows checked against fixture bytes
f_block=0    # ... of which: block pairing and severity counts
f_head=0     #               heading equalities
f_loc=0      #               `-->` location equalities
f_msg=0      #               help and related-note text equalities
f_caret=0    #               caret-row equalities
f_dash=0     #               dash-row equalities
f_gutter=0   #               snippet-gutter presence
f_label=0    #               primary-label equalities  (AXDL `#"..."`)
f_note=0     #               note-line equalities      (AXDL `!"..."`, `&"..."`)
f_esc=0      # ANSI sequences checked against style.ax's declared palette

# ------------------------------------------------------------------
# check 3: the AXDL golden read as a document, against the human one
# ------------------------------------------------------------------
# POSITIONAL. The k-th blank-line-separated block of the human golden is
# the rendering of the k-th AXDL diagnostic, and every assertion is
# scoped to that block and anchored at both ends. The version this
# replaced made 692 unanchored `grep -qF` hits over the whole file,
# which pinned a multiset of strings: reversing the renderer's emission
# order, or welding a suffix onto every heading, left it reporting
# "52 passed, 0 failed".
axdl_facts() {
  local axdl="$1" golden="$2" label="$3"
  local rc=0 nE nW headE headW line ndiag want_blocks k

  nE="$(grep -cE '^E ' "$axdl")"
  nW="$(grep -cE '^W ' "$axdl")"
  headE="$(grep -cE '^error\[AX[0-9]{4}\]: ' "$golden")"
  headW="$(grep -cE '^warning\[AX[0-9]{4}\]: ' "$golden")"

  # Severities counted SEPARATELY. A single total is satisfied by a
  # renderer that prints an error as a warning and a warning as an
  # error, which is precisely the confusion the exit-status derivation
  # above rests on. (The per-block heading equality below pins the
  # severity of each diagnostic individually; these two also catch a
  # heading that appears somewhere other than at the head of a block,
  # which the pairing alone would not look at.)
  if grep -qE '^[NH] ' "$axdl"; then
    echo "FAIL $label (AXDL note/help severity has no heading rule in this gate)"
    rc=1
  fi
  facts=$((facts + 2)); f_block=$((f_block + 2))
  if [[ "$nE" != "$headE" ]]; then
    echo "FAIL $label (AXDL has $nE errors, human has $headE error headings)"
    rc=1
  fi
  if [[ "$nW" != "$headW" ]]; then
    echo "FAIL $label (AXDL has $nW warnings, human has $headW warning headings)"
    rc=1
  fi

  local -a DL
  DL=()
  ndiag=0
  while IFS= read -r line; do
    DL[$ndiag]="$line"
    ndiag=$((ndiag + 1))
  done < <(grep -E '^[EWNH] ' "$axdl")

  read_blocks "$golden"

  # The shape of the document, before anything about its contents: one
  # block per diagnostic, in order, plus exactly one trailer block iff
  # the case has an error. A renderer that dropped, duplicated or merged
  # a diagnostic changes this count even when every string it prints is
  # still somewhere in the file.
  want_blocks="$ndiag"
  [[ "$nE" -gt 0 ]] && want_blocks=$((ndiag + 1))
  facts=$((facts + 1)); f_block=$((f_block + 1))
  if [[ "$NB" != "$want_blocks" ]]; then
    echo "FAIL $label (human golden has $NB blank-line-separated block(s); the AXDL's $ndiag diagnostic(s) call for $want_blocks)"
    return 1
  fi

  for (( k = 0; k < ndiag; k++ )); do
    local sev code locspan slug f rest L C crest tail C2 run bs be
    local want_sev primary relmsg kind text src nlines plabel
    local -a helps helpfix notes
    read -r sev code locspan slug _ <<< "${DL[$k]}"
    bs="${BS[$k]}"
    be="${BE[$k]}"

    primary=""
    relmsg=""
    plabel=""
    helps=()
    helpfix=()
    notes=()
    while IFS=$'\t' read -r kind text; do
      case "$kind" in
        msg)   primary="$text" ;;
        rel)   relmsg="$text" ;;
        label) plabel="$text" ;;
        help)  helps[${#helps[@]}]="$text"; helpfix[${#helpfix[@]}]="" ;;
        note)  notes[${#notes[@]}]="$text" ;;
        # An expansion-backtrace frame renders as a note, the way rustc
        # reports the same thing.
        trace) notes[${#notes[@]}]="in this expansion of $text" ;;
        # The replacement half of a fix attaches to the help it follows.
        # Parsed and paired here, but NOT yet folded into the help-line
        # equality below: the renderer does not print it yet, and a gate
        # that demanded output the compiler was never asked for would
        # fail the corpus rather than describe it.
        fix)   (( ${#helps[@]} > 0 )) && helpfix[$(( ${#helps[@]} - 1 ))]="$text" ;;
        *)
          echo "FAIL $label (AXDL string in a field this gate does not know how to assert: $text)"
          rc=1 ;;
      esac
    done < <(axdl_fields "${DL[$k]}")

    # The heading, as an EQUALITY. Severity, code, message text, and the
    # absence of anything else, in one statement: `grep -qF -- "$msg"`
    # said only "appears somewhere as a substring", which a renderer
    # that printed the right text plus a debug tag satisfied for free.
    want_sev="error"
    [[ "$sev" == W ]] && want_sev="warning"
    facts=$((facts + 1)); f_head=$((f_head + 1))
    if [[ "${GL[$bs]}" != "$want_sev[$code]: $primary" ]]; then
      echo "FAIL $label (block $((k + 1)) heading is \`${GL[$bs]}\`; the AXDL calls for \`$want_sev[$code]: $primary\`)"
      rc=1
    fi

    f="${locspan%%:*}"
    rest="${locspan#*:}"
    L="${rest%%:*}"
    crest="${rest#*:}"
    if [[ "$crest" == *-* ]]; then
      C="${crest%%-*}"
      tail="${crest#*-}"
    else
      C="$crest"
      tail=""
    fi

    if ! src="$(resolve_fixture "$f")"; then
      echo "FAIL $label (AXDL names $f, which is not a file in tests/diagnostics)"
      rc=1
      continue
    fi
    nlines="$(grep -c '' "$src" | tr -d ' ')"

    # An end-of-file diagnostic names a line PAST the last one - an
    # unclosed `(` runs out at the position after the final newline.
    # There is still a line to point at, and the renderer points at the
    # last one with the caret one past its final character. Derived
    # here from the fixture's own bytes, so it stays a fact about the
    # file rather than a fact about the golden. (stage0 agreed while it
    # existed: its AXDL said 4:1 for the three-line 900-unexpected-eof
    # and its caret sat at 3:10.)
    if (( L > nlines )); then
      L="$nlines"
      C=$(( $(char_len "$(fixture_line "$src" "$nlines")") + 1 ))
      tail=""
    fi

    facts=$((facts + 1)); f_loc=$((f_loc + 1))
    if ! block_trim_eq "$bs" "$be" "--> $f:$L:$C"; then
      echo "FAIL $label (block $((k + 1)) has no \`--> $f:$L:$C\` header line)"
      rc=1
    fi

    # Layout derived from the span rather than trusted to the golden.
    # `L:C-C2` is end-exclusive in characters; a bare `L:C` is a width-1
    # span. A span that crosses lines (810-unterminated-string is
    # `4:23-5:1`) is underlined to end of line, and how long that line
    # is comes from the FIXTURE - the one right-hand side no bless can
    # write.
    if [[ "$tail" == *:* ]]; then
      run=$(( $(char_len "$(fixture_line "$src" "$L")") - C + 1 ))
    elif [[ -n "$tail" ]]; then
      C2="$tail"; run=$((C2 - C))
    else
      run=1
    fi
    [[ "$run" -lt 1 ]] && run=1

    # The same span in DISPLAY columns, and the window the line is quoted
    # in. `run` above counts characters, which is what AXDL reports; a
    # tab before or inside the span makes that a different number from
    # where the caret lands. Both conversions are the identity on today's
    # corpus - no tabs, longest line 83 against a 160-column window - so
    # this derivation reproduces the previous one exactly until a fixture
    # gives it something to do.
    local rawline dw dC dEnd drun wstart wend cpad
    rawline="$(fixture_line "$src" "$L")"
    dw="$(disp_width "$rawline")"
    dC="$(disp_col "$rawline" "$C")"
    dEnd="$(disp_col "$rawline" "$((C + run))")"
    drun=$((dEnd - dC)); [[ "$drun" -lt 1 ]] && drun=1
    read -r wstart wend < <(trunc_window "$dw" "$dC")
    # A caret is clamped to the window it is drawn in.
    (( dC - 1 + drun > wend )) && drun=$(( wend - (dC - 1) ))
    [[ "$drun" -lt 1 ]] && drun=1
    # One leading space for the bar, three more if the row opens with an
    # elision marker, then the span's offset within the window.
    cpad=$(( 1 + (wstart > 0 ? 3 : 0) + (dC - 1 - wstart) ))

    facts=$((facts + 2)); f_gutter=$((f_gutter + 1)); f_caret=$((f_caret + 1))
    if ! block_re "$bs" "$be" "^ *${L} \\| "; then
      echo "FAIL $label (block $((k + 1)): source line $L not in the snippet gutter)"
      rc=1
    fi
    # The primary label, when the AXDL carries one, is part of the caret
    # row and is asserted with it: the caret row equality is anchored at
    # both ends, so a label is either exactly right or the row is wrong.
    local want_caret
    want_caret="$(printf '%*s' "$cpad" '')$(printf '%*s' "$drun" '' | tr ' ' '^')"
    if [[ -n "$plabel" ]]; then
      want_caret="$want_caret $plabel"
      facts=$((facts + 1)); f_label=$((f_label + 1))
    fi
    if ! block_bar_eq "$bs" "$be" "$want_caret"; then
      echo "FAIL $label (block $((k + 1)): no caret row at col $dC width $drun for span $locspan${plabel:+ labelled \`$plabel\`})"
      rc=1
    fi
    local ncaret ndash
    ncaret="$(block_count_re "$bs" "$be" '^ *\| *\^+( .*)?$')"
    facts=$((facts + 1)); f_caret=$((f_caret + 1))
    if [[ "$ncaret" != 1 ]]; then
      echo "FAIL $label (block $((k + 1)) draws $ncaret caret rows; one diagnostic underlines one primary span)"
      rc=1
    fi

    # The related span's line must appear in the gutter too, with a dash
    # row of the span's width carrying the note verbatim after it.
    local rel RL rrest RC RC2 rrun
    rel="$(printf '%s\n' "${DL[$k]}" | grep -oE ' \^[0-9]+:[0-9]+(-[0-9]+)?:' | head -1 | sed 's/^ \^//; s/:$//')"
    if [[ -n "$rel" ]]; then
      RL="${rel%%:*}"
      rrest="${rel#*:}"
      RC="${rrest%%-*}"
      if [[ "$rrest" == *-* ]]; then RC2="${rrest#*-}"; else RC2=$((RC + 1)); fi
      rrun=$((RC2 - RC)); [[ "$rrun" -lt 1 ]] && rrun=1
      facts=$((facts + 2)); f_gutter=$((f_gutter + 1)); f_dash=$((f_dash + 1))
      if ! block_re "$bs" "$be" "^ *${RL} \\| "; then
        echo "FAIL $label (block $((k + 1)): related line $RL not in the snippet gutter)"
        rc=1
      fi
      local want_dash
      want_dash="$(printf '%*s' "$RC" '')$(printf '%*s' "$rrun" '' | tr ' ' '-')"
      [[ -n "$relmsg" ]] && want_dash="$want_dash $relmsg"
      if ! block_bar_eq "$bs" "$be" "$want_dash"; then
        echo "FAIL $label (block $((k + 1)): no dash row at col $RC width $rrun followed by \`$relmsg\`)"
        rc=1
      fi
    elif [[ -n "$relmsg" ]]; then
      echo "FAIL $label (block $((k + 1)): AXDL carries a related note with no span this gate can read)"
      rc=1
    fi
    # And no dash row the AXDL never asked for. A block whose AXDL line
    # has no `^` span must draw none at all, which is the assertion the
    # 71 related-less blocks make and the 15 others make as "exactly 1".
    ndash="$(block_count_re "$bs" "$be" '^ *\| *-+( .*)?$')"
    facts=$((facts + 1)); f_dash=$((f_dash + 1))
    if [[ -n "$rel" ]]; then
      [[ "$ndash" == 1 ]] || { echo "FAIL $label (block $((k + 1)) draws $ndash dash rows; the AXDL gives it one related span)"; rc=1; }
    else
      [[ "$ndash" == 0 ]] || { echo "FAIL $label (block $((k + 1)) draws $ndash dash rows; the AXDL gives it no related span)"; rc=1; }
    fi

    # Notes, before the helps, the way the renderer orders them. An
    # expansion-backtrace frame has already been turned into one above.
    local nt
    for nt in ${notes[@]+"${notes[@]}"}; do
      facts=$((facts + 1)); f_note=$((f_note + 1))
      if ! block_trim_eq "$bs" "$be" "= note: $nt"; then
        echo "FAIL $label (block $((k + 1)) has no note line reading exactly \`= note: $nt\`)"
        rc=1
      fi
    done

    local h
    for h in ${helps[@]+"${helps[@]}"}; do
      facts=$((facts + 1)); f_msg=$((f_msg + 1))
      if ! block_trim_eq "$bs" "$be" "= help: $h"; then
        echo "FAIL $label (block $((k + 1)) has no help line reading exactly \`= help: $h\`)"
        rc=1
      fi
    done
    [[ -n "$relmsg" ]] && { facts=$((facts + 1)); f_msg=$((f_msg + 1)); }
  done

  # The trailer, as an equality on the golden's last line. A count that
  # merely APPEARS somewhere is satisfied by a file that also says
  # something else afterwards.
  facts=$((facts + 1)); f_block=$((f_block + 1))
  local lastline="" i
  for (( i = NG - 1; i >= 0; i-- )); do
    if [[ -n "${GL[$i]}" ]]; then lastline="${GL[$i]}"; break; fi
  done
  if [[ "$nE" -gt 0 ]]; then
    local plural="errors"
    [[ "$nE" == 1 ]] && plural="error"
    if [[ "$lastline" != "compilation failed due to $nE previous $plural" ]]; then
      echo "FAIL $label (the golden ends \`$lastline\`; the AXDL's $nE error(s) call for \`compilation failed due to $nE previous $plural\`)"
      rc=1
    fi
  else
    if grep -q "compilation failed" "$golden"; then
      echo "FAIL $label (warnings-only case has a failure trailer)"
      rc=1
    fi
  fi

  return $rc
}

# ------------------------------------------------------------------
# check 4: every quoted source row, against the fixture's own bytes
# ------------------------------------------------------------------
# The one assertion in this gate that reads no golden at all on the
# right-hand side. `AXIOM_BLESS=1` can make the left-hand side say
# anything; the right-hand side is the compiler's INPUT.
source_rows() {
  local golden="$1" label="$2"
  local rc=0 row cur="" n text src
  while IFS= read -r row; do
    if [[ "$row" =~ ^\ *--\>\ ([^ :]+\.ax):[0-9]+:[0-9]+$ ]]; then
      if ! cur="$(resolve_fixture "${BASH_REMATCH[1]}")"; then
        echo "FAIL $label (snippet header names ${BASH_REMATCH[1]}, not a file in tests/diagnostics)"
        rc=1
        cur=""
      fi
    elif [[ "$row" =~ ^[[:space:]]*([0-9]+)\ \|(\ (.*))?$ ]]; then
      n="${BASH_REMATCH[1]}"
      text="${BASH_REMATCH[3]}"
      if [[ -z "$cur" ]]; then
        echo "FAIL $label (snippet row \`$row\` belongs to no \`-->\` header)"
        rc=1
        continue
      fi
      src="$(fixture_line "$cur" "$n")"
      rows=$((rows + 1))
      local exp w inner lmark rmark want
      exp="$(expand_tabs "$src")"
      w="$(disp_width "$src")"
      if (( w <= LINE_MAX )); then
        # The whole line, tabs expanded. This is the only branch today:
        # the corpus's longest line is 83 columns and none contains a
        # tab, so `exp` is `src` and this is the comparison that was
        # here before the window arithmetic existed.
        if [[ "$text" != "$exp" ]]; then
          echo "FAIL $label (snippet quotes $cur:$n as \`$text\`; the file says \`$exp\`)"
          rc=1
        fi
      else
        # A line too wide to quote whole is quoted as a window, marked
        # `...` on whichever side was elided. The window is always
        # exactly LINE_MAX columns - that falls out of trunc_window - so
        # its WIDTH is derivable here even though its ORIGIN depends on a
        # span this check does not read. When only one side is elided the
        # origin is pinned too, because the other side is the line's own
        # end. The origin in the both-elided case is pinned by the caret
        # pad in check 3, which does know the span.
        #
        # Markers are only read as markers on a line that could not have
        # been quoted whole, so a source line that genuinely begins with
        # three dots is never mistaken for a windowed one.
        inner="$text"; lmark=0; rmark=0
        [[ "$inner" == ...* ]] && { lmark=1; inner="${inner#...}"; }
        [[ "$inner" == *... ]] && { rmark=1; inner="${inner%...}"; }
        if (( lmark == 0 && rmark == 0 )); then
          echo "FAIL $label (snippet quotes all $w columns of $cur:$n; the window is $LINE_MAX)"
          rc=1
        elif [[ "$(char_len "$inner")" != "$LINE_MAX" ]]; then
          echo "FAIL $label (snippet window on $cur:$n is $(char_len "$inner") columns; the window is $LINE_MAX)"
          rc=1
        elif (( lmark == 0 )); then
          want="$(disp_slice "$exp" 0 "$LINE_MAX")"
          [[ "$inner" == "$want" ]] || {
            echo "FAIL $label (snippet window on $cur:$n is not the line's first $LINE_MAX columns)"; rc=1; }
        elif (( rmark == 0 )); then
          want="$(disp_slice "$exp" "$((w - LINE_MAX))" "$w")"
          [[ "$inner" == "$want" ]] || {
            echo "FAIL $label (snippet window on $cur:$n is not the line's last $LINE_MAX columns)"; rc=1; }
        else
          [[ "$exp" == *"$inner"* ]] || {
            echo "FAIL $label (snippet window on $cur:$n is not a run of columns from that line)"; rc=1; }
        fi
      fi
    fi
  done < "$golden"
  return $rc
}

# ------------------------------------------------------------------
# check 5: the escape stream, against the palette style.ax declares
# ------------------------------------------------------------------
# Color is the one part of the human surface with no counterpart in the
# AXDL golden or the fixture, so checks 3 and 4 - which strip it before
# comparing - say nothing about it, and check 1 is the re-blessable half.
# On its own that would mean a renderer could emit any escape stream it
# liked and have it blessed into all 52 goldens unchallenged, which is
# the shape of defect this script's header was written about.
#
# The right-hand side is therefore a THIRD artifact: the palette declared
# in self_host/style.ax. AXIOM_BLESS rewrites NAME.human; it cannot write
# the compiler's own palette table, so an escape sequence nothing
# declares fails with a freshly blessed golden in the tree.
#
# Before the color layer exists there is no style.ax, the declared
# alphabet is empty, and the only stream that passes is the empty one -
# which is exactly today's contract, asserted rather than assumed.
palette_file="self_host/style.ax"
PALETTE=""
if [[ -f "$palette_file" ]]; then
  PALETTE="$(grep -oE '"[0-9;]+"' "$palette_file" | tr -d '"' | sort -u)"
fi

escape_facts() {
  local golden="$1" label="$2" rc=0 p ln params
  # (1) ALPHABET. Every SGR parameter string in the golden is one
  #     style.ax declares, or the reset.
  while IFS= read -r p; do
    [[ -z "$p" && "$p" != "0" ]] && continue
    f_esc=$((f_esc + 1)); facts=$((facts + 1))
    if [[ "$p" != "0" ]] && ! grep -qxF -- "$p" <<< "$PALETTE"; then
      echo "FAIL $label (renders SGR \`$p\`, which $palette_file does not declare)"
      rc=1
    fi
  done < <(LC_ALL=C grep -oE $'\x1b\\[[0-9;]*m' "$golden" 2>/dev/null \
           | LC_ALL=C sed $'s/^\x1b\\[//; s/m$//')

  # (2) BALANCE. Escapes are emitted by painting a finished fragment, so
  #     every line's sequences read open, reset, open, reset. A colour
  #     left open at end of line bleeds into whatever the terminal prints
  #     next, and a golden is exactly where that would go unnoticed.
  while IFS= read -r ln; do
    [[ "$ln" != *$'\x1b'* ]] && continue
    params="$(printf '%s' "$ln" | LC_ALL=C grep -oE $'\x1b\\[[0-9;]*m' \
              | LC_ALL=C sed $'s/^\x1b\\[//; s/m$//' | tr '\n' ' ')"
    local -a ps; read -r -a ps <<< "$params"
    facts=$((facts + 1)); f_esc=$((f_esc + 1))
    local j bad=0
    (( ${#ps[@]} % 2 == 1 )) && bad=1
    for (( j = 0; j < ${#ps[@]}; j++ )); do
      if (( j % 2 == 0 )); then [[ "${ps[j]}" == "0" ]] && bad=1
      else                      [[ "${ps[j]}" != "0" ]] && bad=1; fi
    done
    if (( bad )); then
      echo "FAIL $label (a line's SGR sequences do not read open/reset in pairs: $params)"
      rc=1
    fi
  done < "$golden"

  # (3) PLACEMENT. The gutter of a snippet row may be painted; the source
  #     text it quotes may not - that text is the fixture's bytes, and
  #     colouring it is what made ariadne's output undiffable. The trailer
  #     is printed in every format, including the machine ones, so it
  #     carries no escapes at all.
  local nbad
  nbad="$(LC_ALL=C grep -cE $'^[^|]*\\|[^\x1b]*\x1b' "$golden" 2>/dev/null || true)"
  facts=$((facts + 1)); f_esc=$((f_esc + 1))
  if [[ "${nbad:-0}" != 0 ]]; then
    echo "FAIL $label ($nbad snippet row(s) carry an escape after the gutter bar)"
    rc=1
  fi
  facts=$((facts + 1)); f_esc=$((f_esc + 1))
  if LC_ALL=C grep -q $'^.*compilation failed.*\x1b' "$golden" 2>/dev/null \
     || LC_ALL=C grep -q $'\x1b.*compilation failed' "$golden" 2>/dev/null; then
    echo "FAIL $label (the failure trailer carries an escape; it is printed in every format)"
    rc=1
  fi
  return $rc
}

# ------------------------------------------------------------------
# the sweep
# ------------------------------------------------------------------

passed=0
failed=0
cases=0
want_fail=0   # cases the AXDL golden says must fail
want_ok=0     # cases it says must succeed

for axdl in tests/diagnostics/*.axdl; do
  name="$(basename "$axdl" .axdl)"
  if [[ -n "$filter" && "$name" != "$filter"* ]]; then
    continue
  fi
  cases=$((cases + 1))
  golden="tests/diagnostics/$name.human"

  if [[ -f "tests/diagnostics/$name.ax" ]]; then
    cp "tests/diagnostics/$name.ax" "$work/$name.ax"
  else
    cp "tests/diagnostics/$name.axbad" "$work/$name.ax"
  fi

  (cd "$work" && ./axc check "$name.ax" 2>"$work/h.err" >"$work/h.out")
  s1=$?

  # Check 6a: the same case rendered as JSON Lines. The trailer is
  # dropped the way check-diagnostics.sh drops it from AXDL -
  # `compilation failed due to N previous errors` is printed in every
  # format and is pinned by the human golden, and a JSON Lines file
  # whose last line is not JSON is one no consumer can read to the end.
  (cd "$work" && ./axc --diagnostic-format=json check "$name.ax" \
       2>"$work/j.raw" >/dev/null)
  grep -E '^\{' "$work/j.raw" > "$work/j.err" || true

  # A bless writes the golden and then goes on to be CHECKED, exactly as
  # if it had been in the tree all along. Checks 2, 3 and 4 read the
  # AXDL golden and the fixture, neither of which this script writes, so
  # they are as sharp against a golden one second old as against a
  # committed one - and the summary below refuses the whole bless if any
  # of them fired. check-diagnostics.sh has refused on the same grounds
  # since it grew its span verifier; the version of this script that
  # `continue`d past every check and always exited 0 let a compiler
  # write down its own defects and call it provenance.
  if [[ "$bless" == 1 ]]; then
    cp "$work/h.err" "$repo_root/$golden"
    cp "$work/j.err" "$repo_root/tests/diagnostics/$name.json"
    echo "blessed $name"
  fi

  if [[ ! -f "$golden" ]]; then
    echo "FAIL $name (no golden at $golden; run with AXIOM_BLESS=1)"
    failed=$((failed + 1))
    continue
  fi

  # Agreement by silence is not agreement: a case that renders nothing
  # matches an empty golden for free.
  if [[ ! -s "$golden" ]]; then
    echo "FAIL $name (golden is empty)"
    failed=$((failed + 1))
    continue
  fi
  if ! grep -qE '^[EWNH] ' "$axdl"; then
    echo "FAIL $name (AXDL golden has no diagnostic line - nothing to derive from)"
    failed=$((failed + 1))
    continue
  fi

  # Check 2. Expected status and stdout read off the AXDL golden.
  if grep -qE '^E ' "$axdl"; then
    want_status=1
    want_fail=$((want_fail + 1))
    : > "$work/want.out"
  else
    want_status=0
    want_ok=$((want_ok + 1))
    printf 'OK\n' > "$work/want.out"
  fi

  ok=1
  if [[ "$s1" != "$want_status" ]]; then
    if (( s1 > 128 )); then
      echo "FAIL $name: died of signal $((s1 - 128)); the AXDL golden calls for status $want_status"
    else
      echo "FAIL $name: exited $s1; the AXDL golden has $(grep -cE '^E ' "$axdl") error line(s), which calls for status $want_status"
    fi
    ok=0
  fi
  # stdout is its own stream and its own contract: `check` prints `OK`
  # there whenever it does not fail - success and warnings-only alike -
  # and nothing at all on errors. A gate that watched only stderr passed
  # while the renderer printed no OK at all.
  if ! cmp -s "$work/want.out" "$work/h.out"; then
    echo "FAIL $name: stdout is $(wc -c <"$work/h.out" | tr -d ' ') bytes, want $(wc -c <"$work/want.out" | tr -d ' ') ($(head -c 40 "$work/want.out" | tr '\n' ' '))"
    ok=0
  fi

  # Check 1.
  if ! cmp -s "$golden" "$work/h.err"; then
    echo "FAIL $name (the rendering differs from the golden)"
    diff "$golden" "$work/h.err" | head -8 | sed 's/^/    /'
    ok=0
  fi

  # Check 6a. The JSON golden, byte for byte, and no colour in the
  # stream it came from - JSON is a machine surface like AXDL. 6b, the
  # derivation from the AXDL golden and the fixture, runs once over the
  # whole corpus after the sweep.
  facts=$((facts + 1)); f_esc=$((f_esc + 1))
  if LC_ALL=C grep -q $'\x1b' "$work/j.raw"; then
    echo "FAIL $name (\`--diagnostic-format=json\` emitted an ANSI escape)"
    ok=0
  fi
  if [[ ! -f "tests/diagnostics/$name.json" ]]; then
    echo "FAIL $name (no JSON golden; run with AXIOM_BLESS=1)"
    ok=0
  elif ! cmp -s "tests/diagnostics/$name.json" "$work/j.err"; then
    echo "FAIL $name (the JSON rendering differs from the golden)"
    diff "tests/diagnostics/$name.json" "$work/j.err" | head -4 | sed 's/^/    /'
    ok=0
  fi

  # Checks 3, 4 and 5. Three and four read a colour-STRIPPED copy: their
  # right-hand sides are the AXDL golden and the fixture, neither of
  # which has any colour in it to compare against, so leaving the
  # escapes in would turn every layout equality into an inequality and
  # the gate would have to be weakened to substrings to survive - the
  # exact trade this script exists to refuse. Check 5 reads the golden
  # raw, because the escapes are what it is about.
  strip_ansi < "$golden" > "$work/plain.human"
  axdl_facts "$axdl" "$work/plain.human" "$name" || ok=0
  source_rows "$work/plain.human" "$name" || ok=0
  escape_facts "$golden" "$name" || ok=0

  if [[ "$ok" == 1 ]]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
done

if [[ -n "$filter" ]]; then
  echo "NOTE: filtered run (\`$filter\`): $cases case(s), corpus floors and drills skipped."
  if [[ "$bless" == 1 ]]; then
    if [[ "$failed" != 0 ]]; then
      echo "REFUSED: $cases case(s) blessed, $passed of them still derivable from their AXDL golden and fixture, $failed check(s) failed - the goldens are on disk to look at, the run is a failure"
      exit 1
    fi
    echo "check-render-selfhost: blessed $cases case(s), all still derivable from their AXDL goldens and fixtures (PROBE not gate)"
    exit 0
  fi
  echo "check-render-selfhost: $passed passed, $failed failed ($cases cases, PROBE not gate)"
  [[ "$failed" == 0 ]]
  exit
fi

# A sweep that read fewer cases than exist is a sweep that can pass by
# not looking (the glob-rot lesson: a pattern that stops matching removes
# files while the section keeps reporting the silence it was looking
# for). Same for the derived halves: if the AXDL parse ever stops
# producing facts, every per-case assertion becomes vacuously true and
# the gate goes green while checking one `cmp` per case.
if [[ "$cases" -lt 38 ]]; then
  echo "FAIL: swept $cases cases; the floor is 38"
  failed=$((failed + 1))
fi
if [[ "$rows" -lt 80 ]]; then
  echo "FAIL: only $rows snippet rows were checked against fixture bytes; the floor is 80"
  failed=$((failed + 1))
fi

# ONE FLOOR PER FAMILY, not one for the total. The aggregate floor this
# replaced was 400 against a total of 692, so the entire message family
# - the newest and most valuable of them - could stop producing
# assertions (a broken field parser, an AXDL quoting change) and leave
# 528, comfortably green, with the headline check evaporated. Today's
# counts over the 52-case corpus, measured 2026-08-08:
#   block  208   head  86   loc  86   msg  78   caret  172   dash  101
#            (gutter 101, and 101 source rows in check 4)
# `msg` is the helps and the related notes; the 86 primary messages are
# asserted by the heading equality and counted under `head`, which is
# why that family shrank from 164 while gaining an anchor at both ends.
# Each floor sits just under its count and far above what a family that
# stopped matching would produce, which is zero.
floor_fail() {
  echo "FAIL: only $2 $1 assertions were made; the floor is $3 - that family stopped matching, which is not the same as nothing being wrong"
  failed=$((failed + 1))
}
[[ "$f_block"  -lt 190 ]] && floor_fail "block-shape and severity-count" "$f_block"  190
[[ "$f_head"   -lt  80 ]] && floor_fail "heading-equality"               "$f_head"    80
[[ "$f_loc"    -lt  80 ]] && floor_fail "location-equality"              "$f_loc"     80
[[ "$f_msg"    -lt  70 ]] && floor_fail "help/related-text equality"     "$f_msg"     70
[[ "$f_caret"  -lt 160 ]] && floor_fail "caret-row equality and count"   "$f_caret"  160
[[ "$f_dash"   -lt  90 ]] && floor_fail "dash-row equality and count"    "$f_dash"    90
[[ "$f_gutter" -lt  90 ]] && floor_fail "snippet-gutter"                 "$f_gutter"  90

# Three families whose AXDL field no diagnostic emits yet. Their floors
# are 0 BECAUSE the corpus produces none of them, which is a fact worth
# writing down rather than an omission: each is raised by the step that
# starts emitting the field, and a floor still sitting at 0 afterwards is
# the signal that the renderer and the gate went out of step.
#   f_label - AXDL `#"..."`, the primary label
#   f_note  - AXDL `!"..."` and `&"..."`, notes and expansion frames
[[ "$f_label" -lt 0 ]] && floor_fail "primary-label equality"            "$f_label"    0
[[ "$f_note"  -lt 0 ]] && floor_fail "note-line equality"                "$f_note"     0

# The escape family is NOT one of those. Two of its assertions - no
# escape after a snippet's gutter bar, none on the trailer - are made
# per case whether or not the golden has any colour in it, so it counts
# 104 today and a floor belongs on it now. The alphabet and balance
# assertions are what will lift it further when the colour layer lands.
[[ "$f_esc"   -lt 100 ]] && floor_fail "escape-stream"                   "$f_esc"    100

# The status derivation has to DISTINGUISH something. A corpus in which
# every case wants the same status is satisfied by a `check` that always
# fails, or always succeeds, and check 2 would be reporting a constant.
if (( want_fail == 0 || want_ok == 0 )); then
  echo "FAIL: every case wants the same exit status ($want_fail fail / $want_ok ok) - the derivation distinguishes nothing"
  failed=$((failed + 1))
fi

# ------------------------------------------------------------------
# check 6b: every JSON golden, derived from the AXDL golden and the
#           fixture
# ------------------------------------------------------------------
# The half of the JSON gate a re-bless cannot satisfy, and the reason
# check 6a is allowed to be a plain `cmp`. Run once over the corpus
# rather than per case because its right-hand sides - NAME.axdl and the
# fixture - are the same files the whole way through.
echo "--- every JSON golden, against its AXDL golden and the fixture's bytes ---"
if ! python3 tests/diagnostics/verify-json.py tests/diagnostics; then
  echo "FAIL: a JSON golden says something its AXDL golden and the fixture do not"
  failed=$((failed + 1))
fi

# ------------------------------------------------------------------
# drills: the comparators, negative-tested, every run
# ------------------------------------------------------------------
# A gate whose comparison is wired to the wrong file, or whose regex
# stopped matching, reports every case green forever. Each drill
# corrupts a copy of a real golden in one specific way and requires the
# check that owns that way to see it - and first requires the corruption
# to have actually changed the file, so a no-op mutation cannot pass the
# drill by accident. Drills (e), (f) and (g) are the three renderer
# defects that went green against the unanchored version of check 3,
# reproduced here as edits to a golden rather than to a compiler.
drill_golden="$(ls tests/diagnostics/*.human 2>/dev/null | head -1)"
if [[ -z "$drill_golden" ]]; then
  echo "FAIL: no goldens exist for the drills"
  failed=$((failed + 1))
else
  drill_axdl="${drill_golden%.human}.axdl"
  drill_name="$(basename "$drill_golden" .human)"
  # The layout drills corrupt a COLOUR-STRIPPED copy, because the checks
  # they are drilling read a stripped copy too - a `sed` anchored at
  # `^error\[` would stop matching the moment a heading opens with an
  # escape, and a drill that silently stops corrupting anything is a
  # drill that passes forever. Drill (a) keeps the raw golden: the byte
  # comparison is about the bytes.
  drill_plain="$work/drill.plain"
  strip_ansi < "$drill_golden" > "$drill_plain"
  # The drills run their own assertions; the corpus counters are the
  # sweep's report and must not be inflated by them.
  facts_kept="$facts"; rows_kept="$rows"
  bk="$f_block"; hk="$f_head"; lk="$f_loc"; mk="$f_msg"
  ck="$f_caret"; dk="$f_dash"; gk="$f_gutter"
  lbk="$f_label"; nk="$f_note"; ek="$f_esc"

  # (a) the byte comparison itself. A gate whose `cmp` is wired to the
  # wrong file reports every case green forever.
  sed 's/error/errro/' "$drill_golden" > "$work/corrupt.human"
  if cmp -s "$drill_golden" "$work/corrupt.human"; then
    echo "FAIL drill(cmp): the byte comparison did not see a corrupted golden"
    failed=$((failed + 1))
  fi

  # (b) check 4: a snippet row that no longer matches the fixture. One
  # character appended to the first quoted source line - the smallest
  # edit a renderer that mis-slices a line would make.
  awk 'BEGIN{d=0} { if (!d && $0 ~ /^ *[0-9]+ \| /) { print $0 "X"; d=1 } else print }' \
    "$drill_plain" > "$work/rowbad.human"
  if cmp -s "$drill_plain" "$work/rowbad.human"; then
    echo "FAIL drill(rows): the corruption changed nothing - the row pattern matched no line"
    failed=$((failed + 1))
  elif source_rows "$work/rowbad.human" "drill" >/dev/null 2>&1; then
    echo "FAIL drill(rows): a snippet row that contradicts the fixture was accepted"
    failed=$((failed + 1))
  fi

  # (c) check 3: a heading that keeps its code, its location, its
  # carets and its trailer, and says something the diagnostic never
  # said. Only the heading equality can see this one, which is why it
  # is drilled apart from (b).
  sed -E '/^error\[AX[0-9]{4}\]: /s/(\]: ).*/\1a message this compiler never emitted/' \
    "$drill_plain" > "$work/msgbad.human"
  if cmp -s "$drill_plain" "$work/msgbad.human"; then
    echo "FAIL drill(messages): the corruption changed nothing - no heading matched"
    failed=$((failed + 1))
  elif axdl_facts "$drill_axdl" "$work/msgbad.human" "drill" >/dev/null 2>&1; then
    echo "FAIL drill(messages): a heading with the wrong message text was accepted"
    failed=$((failed + 1))
  fi

  # (d) check 2: the status derivation reads the AXDL golden rather
  # than returning a constant. Downgrade the drill case's errors to
  # warnings in a copy and the derived status must flip - if it does
  # not, the rule is not a function of the file and every case's status
  # assertion is decoration.
  sed 's/^E /W /' "$drill_axdl" > "$work/statusbad.axdl"
  grep -qE '^E ' "$drill_axdl"; d_before=$?
  grep -qE '^E ' "$work/statusbad.axdl"; d_after=$?
  if [[ "$d_before" != 0 ]]; then
    echo "FAIL drill(status): $drill_name has no E line, so the derivation cannot be exercised here"
    failed=$((failed + 1))
  elif [[ "$d_after" == 0 ]]; then
    echo "FAIL drill(status): errors downgraded to warnings still derive a failing status"
    failed=$((failed + 1))
  fi

  # (e) attack A, as an edit: one more caret than the span calls for.
  # This is what `(repByte (+ run 1) ch)` did to all 52 goldens, and the
  # substring form of this assertion could not fail on it - a prefix is
  # a substring, so no span could ever be too WIDE.
  awk 'BEGIN{d=0} { if (!d && $0 ~ /^ *\| *\^+$/) { print $0 "^"; d=1 } else print }' \
    "$drill_plain" > "$work/caretbad.human"
  if cmp -s "$drill_plain" "$work/caretbad.human"; then
    echo "FAIL drill(caret): the corruption changed nothing - no caret row matched"
    failed=$((failed + 1))
  elif axdl_facts "$drill_axdl" "$work/caretbad.human" "drill" >/dev/null 2>&1; then
    echo "FAIL drill(caret): a caret run one character wider than the span was accepted"
    failed=$((failed + 1))
  fi

  # (f) attack C, as an edit: the right text plus something else. The
  # containment form accepted every suffix, prefix and interleaving.
  awk 'BEGIN{d=0} { if (!d && $0 ~ /^(error|warning)\[AX[0-9][0-9][0-9][0-9]\]: /) { print $0 " [debug: span=?]"; d=1 } else print }' \
    "$drill_plain" > "$work/suffixbad.human"
  if cmp -s "$drill_plain" "$work/suffixbad.human"; then
    echo "FAIL drill(suffix): the corruption changed nothing - no heading matched"
    failed=$((failed + 1))
  elif axdl_facts "$drill_axdl" "$work/suffixbad.human" "drill" >/dev/null 2>&1; then
    echo "FAIL drill(suffix): a heading carrying the right message plus a debug tag was accepted"
    failed=$((failed + 1))
  fi

  # (g) attack B, as an edit: the same blocks, emitted in the wrong
  # order. Needs a case with more than one diagnostic, so it picks its
  # own golden rather than reusing the first one - and fails loudly if
  # the corpus no longer has such a case, because then nothing in this
  # gate is pinning order.
  order_axdl=""
  for cand in tests/diagnostics/*.axdl; do
    if [[ "$(grep -cE '^[EWNH] ' "$cand")" -ge 2 && -f "${cand%.axdl}.human" ]]; then
      order_axdl="$cand"; break
    fi
  done
  if [[ -z "$order_axdl" ]]; then
    echo "FAIL drill(order): no case has two diagnostics - emission order is unpinnable"
    failed=$((failed + 1))
  else
    order_golden="${order_axdl%.axdl}.human"
    order_plain="$work/order.plain"
    strip_ansi < "$order_golden" > "$order_plain"
    awk 'BEGIN{RS=""; n=0} {b[++n]=$0} END{ t=b[1]; b[1]=b[2]; b[2]=t; for (i=1;i<=n;i++) printf "%s\n\n", b[i] }' \
      "$order_plain" > "$work/orderbad.human"
    if ! grep -qE '^(error|warning)\[AX[0-9]{4}\]: ' "$work/orderbad.human"; then
      echo "FAIL drill(order): the reordered copy has no headings - the block split matched nothing"
      failed=$((failed + 1))
    elif [[ "$(grep -cE '^(error|warning)\[AX[0-9]{4}\]: ' "$work/orderbad.human")" \
         != "$(grep -cE '^(error|warning)\[AX[0-9]{4}\]: ' "$order_plain")" ]]; then
      echo "FAIL drill(order): the reordered copy lost or gained a heading - it is not a permutation"
      failed=$((failed + 1))
    elif ! axdl_facts "$order_axdl" "$order_plain" "drill" >/dev/null 2>&1; then
      # This drill is the only one whose corruption is an INVOLUTION: if
      # the golden on disk is already in the wrong order - which is
      # exactly what a bless from a renderer with a reversed emission
      # loop leaves behind - then swapping two of its blocks puts them
      # back and the drill would report the comparator broken when the
      # corpus is. Say which.
      echo "FAIL drill(order): $(basename "$order_golden") does not satisfy its own AXDL golden, so there is no correct baseline to reorder (the sweep above names the case)"
      failed=$((failed + 1))
    elif axdl_facts "$order_axdl" "$work/orderbad.human" "drill" >/dev/null 2>&1; then
      echo "FAIL drill(order): $(basename "$order_golden")'s diagnostics, emitted in the wrong order, were accepted"
      failed=$((failed + 1))
    fi
  fi

  # (h) the colour layer's three failure modes. Until style.ax exists
  # the goldens carry no escapes, so these run on a SYNTHETIC copy -
  # a real golden with paint applied to its heading. Drilling the
  # machinery before it is load-bearing is the point: the step that
  # turns colour on must not also be the step that writes the check on
  # it, or the check is only as good as the output it was written
  # against. Once the goldens are coloured, (h1) additionally proves
  # they are - see the f_esc floor.
  esc=$'\x1b'
  sed "1s/^/${esc}[1;31m/; 1s/\$/${esc}[0m/" "$drill_plain" > "$work/esc.human"

  # (h1) the stripper actually strips. If strip_ansi silently stopped
  # matching, checks 3 and 4 would be reading coloured text and failing
  # loudly - but a stripper that removed too much, or a golden that
  # never had colour, both leave it a no-op, and only one of those is
  # fine. Compare the two directions separately.
  if cmp -s "$work/esc.human" "$drill_plain"; then
    echo "FAIL drill(ansi-inject): the synthetic corruption added no escapes"
    failed=$((failed + 1))
  elif ! cmp -s <(strip_ansi < "$work/esc.human") "$drill_plain"; then
    echo "FAIL drill(ansi-strip): stripping a painted copy did not restore the plain one"
    failed=$((failed + 1))
  fi

  # (h2) a BROKEN escape - one whose `[` is missing, so the stripper
  # cannot repair it - must leave the layout equalities failing rather
  # than passing on a mangled heading. This is what proves checks 3 and
  # 4 see THROUGH the colour rather than being blinded by it.
  sed "1s/^/${esc}1;31m/" "$drill_plain" > "$work/escbad.human"
  if cmp -s "$drill_plain" "$work/escbad.human"; then
    echo "FAIL drill(ansi-broken): the corruption changed nothing"
    failed=$((failed + 1))
  elif axdl_facts "$drill_axdl" <(strip_ansi < "$work/escbad.human") "drill" >/dev/null 2>&1; then
    echo "FAIL drill(ansi-broken): a heading carrying an unstrippable escape was accepted"
    failed=$((failed + 1))
  fi

  # (h3) an SGR the palette does not declare. The one drill a re-bless
  # cannot get out from under: the alphabet lives in self_host/style.ax.
  sed "1s/^/${esc}[5;35m/; 1s/\$/${esc}[0m/" "$drill_plain" > "$work/palbad.human"
  if cmp -s "$drill_plain" "$work/palbad.human"; then
    echo "FAIL drill(ansi-palette): the corruption changed nothing"
    failed=$((failed + 1))
  elif escape_facts "$work/palbad.human" "drill" >/dev/null 2>&1; then
    echo "FAIL drill(ansi-palette): SGR \`5;35\`, which $palette_file does not declare, was accepted"
    failed=$((failed + 1))
  fi

  # (i) the display-column arithmetic, on synthetic input. Every one of
  # these functions is the identity on today's corpus - no tabs, no line
  # near the window - so nothing in the sweep above exercises them, and
  # an identity that is wrong in the general case would sit here unnoticed
  # until the fixture that needed it arrived and the golden was blessed
  # around the bug.
  drill_disp() {
    local what="$1" got="$2" want="$3"
    facts=$((facts + 1))
    if [[ "$got" != "$want" ]]; then
      echo "FAIL drill(display): $what is \`$got\`, want \`$want\`"
      failed=$((failed + 1))
    fi
  }
  tabline=$'\tx\ty'          # -> "    x   y": tab to 4, x at 5, tab to 8, y at 9
  drill_disp "expand_tabs on a tab-indented line" \
             "$(expand_tabs "$tabline")" "    x   y"
  drill_disp "disp_width of that line"    "$(disp_width "$tabline")"     9
  drill_disp "disp_col of its 2nd char"   "$(disp_col "$tabline" 2)"     5
  drill_disp "disp_col of its 4th char"   "$(disp_col "$tabline" 4)"     9
  drill_disp "disp_col one past its end"  "$(disp_col "$tabline" 5)"     10
  # A character column and a display column differ here, which is the
  # whole reason the conversion exists: `y` is character 4, column 9.
  drill_disp "expand_tabs is identity without tabs" \
             "$(expand_tabs 'plain (fn (main) 0)')" 'plain (fn (main) 0)'
  # Multi-byte: an em dash is one character and one column, three bytes.
  drill_disp "disp_col past an em dash"   "$(disp_col 'a—b' 3)"          3
  drill_disp "disp_slice keeps a character whole" \
             "$(disp_slice 'a—bc' 1 3)"   '—b'
  # The window: a line that fits is quoted whole; one that does not is
  # quoted in exactly LINE_MAX columns, pushed back at the line's end.
  drill_disp "trunc_window on a short line"        "$(trunc_window 83 6)"    "0 83"
  drill_disp "trunc_window at the head of a wide line" \
             "$(trunc_window 300 30)"     "9 169"
  drill_disp "trunc_window near the end of a wide line" \
             "$(trunc_window 300 295)"    "140 300"
  drill_disp "trunc_window at the very start"      "$(trunc_window 300 1)"   "0 160"

  # (j) check 6b: a JSON golden that contradicts the fixture. `char_start`
  # is the leg that reads the file's own bytes, and the one a regression
  # from characters back to bytes would move - so that is the field the
  # drill moves. Run in a scratch directory holding one case, so the
  # verifier's own corpus floors are not what makes it fail: the drill
  # requires the per-CASE line, not a non-zero exit.
  jd="$work/jdrill"
  rm -rf "$jd"; mkdir -p "$jd"
  cp "$drill_axdl" "${drill_golden%.human}.json" "$jd/" 2>/dev/null
  if jf="$(resolve_fixture "$drill_name.ax")"; then
    cp "$jf" "$jd/$(basename "$jf")"
  fi
  # The verifier's output is captured rather than piped: `set -o pipefail`
  # is on, and `python3 (exit 1) | grep -q (exit 0)` is a FAILING
  # pipeline under it, so a piped form reads as "grep did not match"
  # exactly when it did. Found by this drill reporting its own
  # corruption uncaught while the verifier caught it by hand.
  jout=""
  if [[ ! -f "$jd/$drill_name.json" ]]; then
    echo "FAIL drill(json): $drill_name has no JSON golden to corrupt"
    failed=$((failed + 1))
  else
    jout="$(python3 tests/diagnostics/verify-json.py "$jd" 2>&1 || true)"
    if grep -q "^FAIL $drill_name" <<< "$jout"; then
      echo "FAIL drill(json): $drill_name's own JSON golden is not derivable, so there is no correct baseline to corrupt"
      failed=$((failed + 1))
    else
      sed 's/"char_start":[0-9]*/"char_start":9999/' "$jd/$drill_name.json" \
        > "$jd/j.tmp" && mv "$jd/j.tmp" "$jd/$drill_name.json"
      jout="$(python3 tests/diagnostics/verify-json.py "$jd" 2>&1 || true)"
      if cmp -s "${drill_golden%.human}.json" "$jd/$drill_name.json"; then
        echo "FAIL drill(json): the corruption changed nothing - no char_start matched"
        failed=$((failed + 1))
      elif ! grep -q "^FAIL $drill_name.*'span'" <<< "$jout"; then
        echo "FAIL drill(json): a JSON span whose char_start contradicts the fixture was accepted"
        failed=$((failed + 1))
      fi
    fi
  fi

  facts="$facts_kept"; rows="$rows_kept"
  f_block="$bk"; f_head="$hk"; f_loc="$lk"; f_msg="$mk"
  f_caret="$ck"; f_dash="$dk"; f_gutter="$gk"
  f_label="$lbk"; f_note="$nk"; f_esc="$ek"
fi

if [[ "$bless" == 1 ]]; then
  if [[ "$failed" != 0 ]]; then
    echo "REFUSED: $cases case(s) blessed, $passed of them still derivable from their AXDL golden and fixture, $failed check(s) failed - the goldens are on disk to look at, the run is a failure"
    exit 1
  fi
  echo "check-render-selfhost: blessed $cases cases, all still derivable from their AXDL goldens and fixtures ($facts AXDL facts, $rows source rows)"
  exit 0
fi

echo "check-render-selfhost: $passed passed, $failed failed ($cases cases, $facts AXDL facts [block $f_block, head $f_head, loc $f_loc, msg $f_msg, caret $f_caret, dash $f_dash, gutter $f_gutter, label $f_label, note $f_note, esc $f_esc], $rows source rows, $want_fail fail/$want_ok ok by derivation)"
[[ "$failed" == 0 ]]
