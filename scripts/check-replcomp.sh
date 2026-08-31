#!/usr/bin/env bash
# ---------------------------------------------------------------------
# REPL identifier completion, pinned WITHOUT A TERMINAL.
#
# `self_host/replcomp.ax` answers a question - "what are the candidates
# at this cursor, and what should the screen show" - and answers it as
# a value. No file descriptor, no key, no protocol. That is a design
# choice made FOR this gate: the interesting half of tab completion is
# which names are offered and in what order, and a pty harness would
# put a terminal emulator between that question and its answer for no
# gain. So `tests/replcomp/drive.ax` supplies a session, a buffer and a
# cursor offset from the command line and prints what the module
# answers, and everything below asserts on text.
#
# WHAT IS DELIBERATELY OUT OF SCOPE: the key bindings. Nothing here
# says that Tab is byte 9 or that Shift-Tab is `ESC [ Z`, because
# nothing in `replcomp.ax` says so either - `replComplTab` takes a
# direction, and the line editor that owns `self_host/repl.ax` decides
# which keys produce it. When that editor lands, the gate that covers
# it covers the binding.
#
# NOTHING HERE IS BLESSED. Every expected set is recomputed, from
# artifacts the module under test does not write:
#
#   * the colon-command vocabulary, from the `(strEq w ":...")`
#     dispatch sites in `self_host/repl.ax`. `replcomp.ax` carries its
#     own copy of that list and must - it cannot import `repl.ax`,
#     because `repl.ax` is its future consumer and the import would
#     close a cycle - so the copy is checked instead, the way
#     `check-lsp-selfhost.sh` checks `lspKeywords` against
#     `parser.ax`'s `kwEq` sites.
#   * the imported-name set, from `(pub :: ...)` in `stdlib/Str.ax`.
#   * the gather cap, from `LSP_COMPL_MAX`'s own definition in
#     `self_host/lsp.ax` - the constant `replcomp.ax` inherits by
#     importing `lspComplWants` rather than reimplementing the filter.
#
# There is nothing for `AXIOM_BLESS` to write, and a re-bless cannot
# make this gate green.
#
# THE ONE NAME THAT EXISTS IN NO FILE. Layer 4 completes
# `zzsessionhelper`, a name typed into a session and never written to
# disk - the whole point of REPL completion as distinct from the LSP's,
# which only ever sees documents. "No file contains it" is a CHECKED
# claim: the gate greps the tree for that spelling first and refuses to
# run if it finds it anywhere but the one fixture and this script.
#
# THE COMPILER. This gate does not call `gate_build_axc`, and that is
# not an oversight. `gate_build_axc` exists so that a gate whose
# SUBJECT is the compiler tests the compiler in the working tree. The
# subject here is one module, `self_host/replcomp.ax`, which the driver
# imports from the working tree on every run - so an ablation of it is
# visible to this gate whichever compiler compiled it, which is the
# property that function exists to provide. Building a second compiler
# first would cost a minute per run and check nothing more.
#
# ABLATIONS. `AXIOM_ABLATE=<name>` copies `self_host/` to a scratch
# directory, breaks one thing in `replcomp.ax` there, and runs the
# whole gate against the broken copy - which must FAIL. The patch is
# applied by exact string match and the run ABORTS if the string is not
# found, because an ablation that silently does not apply is a drill
# that proves the gate can pass, which is the opposite of the point.
# `--ablations` runs all of them and requires each to go red.
#
#   matcher   `replComplOffer` stops asking `lspComplWants`
#   session   this session's own declarations are never offered
#   sig       a signature-only binding stops being a name
#   lcp       the inline step inserts the first candidate, not the
#             common prefix
#   colon     a command prefix loses its `:`
#   rows      `replComplRows` forgets the detail line
#   width     the state machine lays the menu out at 80 columns
#             whatever the terminal is
#   fits      the menu renders however narrow the terminal is, so a
#             row wraps and the editor erases too few
#   selrange  a selection index outside the vector is trusted, which
#             is a SEGFAULT rather than a wrong answer
#
# Usage:
#   scripts/check-replcomp.sh              # the gate
#   scripts/check-replcomp.sh --ablations  # the six drills, each red
#   AXIOM_ABLATE=lcp scripts/check-replcomp.sh
# ---------------------------------------------------------------------

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"

# --ablations re-enters this script once per drill, before gate_init,
# so the drills do not share a work directory with each other.
if [[ "${1:-}" == "--ablations" ]]; then
  self="${BASH_SOURCE[0]}"
  red=0
  ran=0
  for ab in matcher session sig lcp colon rows width fits selrange; do
    ran=$((ran + 1))
    echo "== ablation: $ab =="
    if AXIOM_ABLATE="$ab" bash "$self" > "/tmp/replcomp-ablate-$ab.log" 2>&1; then
      echo "FAIL ablation '$ab' left the gate GREEN - it checks nothing about this."
    elif grep -q '^ *ABORT: ablation' "/tmp/replcomp-ablate-$ab.log"; then
      # A drill whose patch did not apply exits non-zero and would
      # otherwise be counted as a success - the exact shape of a check
      # that cannot fail, in the code whose job is to prove this one
      # can. It happened for real: `axiom fmt` reflowed three anchors
      # and three drills silently became no-ops.
      grep -E '^ *ABORT' "/tmp/replcomp-ablate-$ab.log" | head -2 | sed 's/^/     /'
      echo "FAIL ablation '$ab' never applied, so it drilled nothing. Re-anchor it."
    else
      red=$((red + 1))
      grep -E '^(FAIL|ABORT)' "/tmp/replcomp-ablate-$ab.log" | head -4 | sed 's/^/     /'
      echo "  ok   red, for the reason above"
    fi
  done
  echo
  if (( red != ran )); then
    echo "check-replcomp --ablations: $((ran - red)) of $ran drills did not go red"
    exit 1
  fi
  echo "check-replcomp --ablations: $ran of $ran drills went red"
  exit 0
fi

gate_init

failed=0
checks=0

note() { echo "ok   $1"; }
bad()  { echo "FAIL $1"; failed=$((failed + 1)); }

# --------------------------------------------------------------
# The tree under test: the working one, or a scratch copy with one
# thing broken in it.
# --------------------------------------------------------------
src_root="$repo_root"
if [[ -n "${AXIOM_ABLATE:-}" ]]; then
  mkdir -p "$work/tree"
  cp -a "$repo_root/self_host" "$work/tree/self_host"
  target="$work/tree/self_host/replcomp.ax"
  if ! python3 - "$AXIOM_ABLATE" "$target" <<'PY'
import sys
name, path = sys.argv[1], sys.argv[2]
s = open(path).read()
subs = {
 # the prefix filter, the dedupe and the cap all stop applying
 "matcher": ("(pub fn (replComplOffer out seen label origin tag detail prefix)\n  (if (lspComplWants seen label prefix)",
             "(pub fn (replComplOffer out seen label origin tag detail prefix)\n  (if true"),
 # this session's own declarations are never walked
 "session": ("            (if (== decls 0)\n              0\n              (replComplDecls\n                out                seen                (memGetWordStr e 0)                decls                prefix\n              )\n            )",
             "            (if (== decls 0)\n              0\n              0\n            )"),
 # a signature with no `fn` stops being a session binding
 "sig":     ("(pub fn (replComplWantsDecl tag) (|| (lspWantsSymbol tag) (== tag TAG_D_SIG)))",
             "(pub fn (replComplWantsDecl tag) (lspWantsSymbol tag))"),
 # the inline step inserts a whole candidate instead of the shared prefix
 "lcp":     ("        (strSlice first 0 n)", "        first"),
 # a command prefix loses the colon that makes it one
 "colon":   ('            (memSetWord\n              r              1              (if atCmd\n                (strConcat ":" word)\n                word\n              )\n            )',
             '            (memSetWord r 1 word)'),
 # the height the editor erases stops counting the detail line
 # a menu wider than its terminal is printed anyway
 "fits":    ("(pub fn (replComplFits cands sel width) (<= (replComplMaxLine cands sel width) (replComplWidthOf width)))",
             "(pub fn (replComplFits cands sel width) true)"),
 # an index past the end of the vector is handed to vecGet
 "selrange": ("(pub fn (replComplSelOf cands sel)\n  (if (>= sel (vecLen cands))",
              "(pub fn (replComplSelOf cands sel)\n  (if false"),
 # the layout stops following the terminal
 "width":   ("    (menu (replComplMenu cands sel width))\n    (rows (replComplRows cands sel width))",
             "    (menu (replComplMenu cands sel 80))\n    (rows (replComplRows cands sel 80))"),
 "rows":    ("        (+\n          (+\n            grid            (if (> (vecLen cands) shown)\n              1\n              0\n            )\n          )          (if (>= sel 0)\n            1\n            0\n          )\n        )",
             "        (+\n            grid            (if (> (vecLen cands) shown)\n              1\n              0\n            )\n          )"),
}
# A WHOLE-FUNCTION drill, for the one whose body the formatter keeps
# reflowing out from under a string anchor. Anchored on the header
# line and the closing paren at column 0, which `axiom fmt` does not
# move - the string-anchored version of this drill silently stopped
# applying twice, which is why the runner now treats a drill that did
# not apply as a failure rather than a red.
funcs = {
 # the height the editor erases stops counting the detail line
 "rows": ("(pub fn (replComplRows cands sel0 width)", """(pub fn (replComplRows cands sel0 width)
  (let ((sel (replComplSelOf cands sel0)))
    (if (|| (== (vecLen cands) 0) (if (replComplFits cands sel width)
      false
      true
    ))
      0
      (let (
        (cols (replComplCols width (replComplWidest cands)))
        (shown (replComplPageCount cands sel width))
      )
        (let ((grid (/ (+ shown (- cols 1)) cols)))
          (+ grid (if (> (vecLen cands) shown)
            1
            0
          ))
        )
      )
    )
  )
)"""),
}
if name in funcs:
    hdr, body = funcs[name]
    lines = s.split("\n")
    if hdr not in lines:
        print("ABORT: ablation '%s' did not apply - %s is no longer a line of replcomp.ax." % (name, hdr))
        sys.exit(1)
    i = lines.index(hdr)
    j = i + 1
    while lines[j] != ")":
        j += 1
    open(path, "w").write("\n".join(lines[:i] + body.split("\n") + lines[j+1:]))
    print("     ablated: %s (whole function)" % name)
    sys.exit(0)

if name not in subs:
    print("ABORT: no ablation named '%s'; try one of: %s" % (name, " ".join(sorted(subs))))
    sys.exit(1)
old, new = subs[name]
if old not in s:
    print("ABORT: ablation '%s' did not apply - its anchor is no longer in replcomp.ax." % name)
    print("       An ablation that does not apply is a drill that proves nothing.")
    sys.exit(1)
open(path, "w").write(s.replace(old, new, 1))
print("     ablated: %s" % name)
PY
  then
    exit 1
  fi
  src_root="$work/tree"
fi

# stage1 resolves `(import replcomp)` through the working directory, so
# the tree under test has to be reachable from where the compiler runs.
ln -s "$src_root/self_host" "$work/self_host"
ln -s "$repo_root/stdlib" "$work/stdlib"
cp "$repo_root"/tests/replcomp/*.session "$repo_root"/tests/replcomp/*.pending "$work/"
cp "$repo_root/tests/replcomp/drive.ax" "$work/drive.ax"

echo "== building the harness against $( [[ -n "${AXIOM_ABLATE:-}" ]] && echo "the ABLATED tree" || echo "self_host/replcomp.ax" ) =="
if ! (cd "$work" && "$axiom" build --input drive.ax --output drive) > "$work/build.log" 2>&1; then
  echo "FAIL: could not build tests/replcomp/drive.ax"
  sed 's/^/    /' "$work/build.log" | head -25
  exit 1
fi

drive() { (cd "$work" && ./drive "$@"); }

# --------------------------------------------------------------
echo "== 1. the colon commands are the ones self_host/repl.ax dispatches =="
# --------------------------------------------------------------
derived_cmds="$(grep -oE '\(strEq w ":[a-z]+"\)' "$repo_root/self_host/repl.ax" \
                | grep -oE ':[a-z]+' | sort -u)"
n_cmds=$(printf '%s\n' "$derived_cmds" | grep -c .)
checks=$((checks + 1))
if (( n_cmds < 10 )); then
  echo "ABORT: only $n_cmds colon commands derived from self_host/repl.ax; the floor is 10."
  echo "       The dispatch was reworded and this derivation stopped reading it, so an"
  echo "       equality against it would assert almost nothing."
  exit 1
fi
note "$n_cmds commands derived from repl.ax's dispatch sites"
actual_cmds="$(drive none.pending none.pending "" 0 commands | sort -u)"
checks=$((checks + 1))
if [[ "$derived_cmds" == "$actual_cmds" ]]; then
  note "replcomp.ax offers exactly those $n_cmds"
else
  bad "the command list in replcomp.ax has drifted from repl.ax's dispatch"
  diff <(echo "$derived_cmds") <(echo "$actual_cmds") | sed 's/^/     /'
fi

# --------------------------------------------------------------
echo "== 2. a prefix matching stdlib names =="
# --------------------------------------------------------------
derived_str="$(grep -oE '^\(pub :: strIs[A-Za-z0-9]+' "$repo_root/stdlib/Str.ax" \
               | awk '{print $3}' | sort -u)"
n_str=$(printf '%s\n' "$derived_str" | grep -c .)
checks=$((checks + 1))
if (( n_str < 4 )); then
  echo "ABORT: only $n_str \`strIs*\` names derived from stdlib/Str.ax; the floor is 4."
  exit 1
fi
strIs_out="$(drive 010-stdlib.session none.pending "strIs" 5 cands)"
actual_str="$(echo "$strIs_out" | grep '^I ' | awk '{print $2}' | sort -u)"
checks=$((checks + 1))
if [[ "$derived_str" == "$actual_str" ]]; then
  note "prefix \`strIs\` offers exactly the $n_str names stdlib/Str.ax declares"
else
  bad "prefix \`strIs\` does not match stdlib/Str.ax"
  diff <(echo "$derived_str") <(echo "$actual_str") | sed 's/^/     /'
fi
checks=$((checks + 1))
if [[ "$(echo "$strIs_out" | grep -c '^I .* | Str$')" == "$n_str" ]]; then
  note "each of them names \`Str\` as the module it came from"
else
  bad "an imported candidate did not carry its module in the detail column"
  echo "$strIs_out" | sed 's/^/     /'
fi

# --------------------------------------------------------------
echo "== 3. a prefix matching nothing =="
# --------------------------------------------------------------
checks=$((checks + 1))
none_out="$(drive 050-imports.session none.pending "zzqqnope" 8 cands)"
if [[ "$none_out" == "COUNT 0" ]]; then
  note "an unmatched prefix answers an EMPTY vector, not 0 and not an error"
else
  bad "an unmatched prefix answered something other than an empty vector"
  echo "$none_out" | sed 's/^/     /'
fi
checks=$((checks + 1))
none_tab="$(drive 050-imports.session none.pending "zzqqnope" 8 tabs "+" 80)"
if [[ "$none_tab" == "BUF zzqqnope CUR 8 ROWS 0
MENUNL 0
ESCBYTES 0" ]]; then
  note "Tab on it leaves the buffer, the cursor and the screen alone"
else
  bad "Tab with no candidates changed something"
  echo "$none_tab" | sed 's/^/     /'
fi

# --------------------------------------------------------------
echo "== 4. a name this session defined, which no file contains =="
# --------------------------------------------------------------
stray="$(grep -rl 'zzsessionhelper' "$repo_root" \
          --exclude-dir=.git --exclude-dir=.claude --exclude-dir=.axiom-bin \
          --exclude-dir=target --exclude-dir=node_modules 2>/dev/null \
        | grep -v 'tests/replcomp/020-session-name.session' \
        | grep -v 'scripts/check-replcomp.sh')"
checks=$((checks + 1))
if [[ -n "$stray" ]]; then
  echo "ABORT: \`zzsessionhelper\` appears in the tree, so completing it would no longer"
  echo "       show that a name existing ONLY in the session is completed:"
  printf '%s\n' "$stray" | sed 's/^/       /'
  exit 1
fi
note "\`zzsessionhelper\` is in no file but the one session fixture"
checks=$((checks + 1))
sess_out="$(drive 020-session-name.session none.pending "zzsession" 9 cands)"
if [[ "$sess_out" == "L zzsessionhelper | 
COUNT 1" ]]; then
  note "and it completes, from the session's accumulated source alone"
else
  bad "a name defined only in this session did not complete"
  echo "$sess_out" | sed 's/^/     /'
fi

# --------------------------------------------------------------
echo "== 5. a signature with no definition is a session binding =="
# --------------------------------------------------------------
checks=$((checks + 1))
sig_out="$(drive 030-sig-only.session none.pending "zzgamma" 7 cands)"
if [[ "$sig_out" == "L zzgammaonly | Int
COUNT 1" ]]; then
  note "\`(:: zzgammaonly Int)\` completes, and shows the type it declares"
else
  bad "a signature-only binding did not complete - lspWantsSymbol was reused unwidened"
  echo "$sig_out" | sed 's/^/     /'
fi

# --------------------------------------------------------------
echo "== 6. an identifier on an earlier line of an unfinished entry =="
# --------------------------------------------------------------
checks=$((checks + 1))
pend_out="$(drive 010-stdlib.session 060-inflight.pending "zzparam" 7 cands)"
if [[ "$pend_out" == "W zzparamword | 
COUNT 1" ]]; then
  note "a parameter of a form that does not balance completes - no parse can see it"
else
  bad "an in-flight identifier did not complete"
  echo "$pend_out" | sed 's/^/     /'
fi

# --------------------------------------------------------------
echo "== 7. an empty prefix, and the cap that bounds it =="
# --------------------------------------------------------------
cap="$(grep -oE '\(pub fn \(LSP_COMPL_MAX\) [0-9]+\)' "$repo_root/self_host/lsp.ax" \
       | grep -oE '[0-9]+')"
checks=$((checks + 1))
if [[ -z "$cap" ]] || (( cap < 50 )); then
  echo "ABORT: could not derive LSP_COMPL_MAX from self_host/lsp.ax (got '${cap:-}')."
  exit 1
fi
note "the gather cap derives from lsp.ax as $cap"
empty_out="$(drive 050-imports.session none.pending "" 0 cands)"
checks=$((checks + 1))
if [[ "$(echo "$empty_out" | tail -1)" == "COUNT $cap" ]]; then
  note "an empty prefix offers everything in scope, stopped at exactly that cap"
else
  bad "an empty prefix did not stop at the cap"
  echo "$empty_out" | tail -3 | sed 's/^/     /'
fi
checks=$((checks + 1))
if [[ -z "$(echo "$empty_out" | grep -E '^[CLTIKW] \|')" ]]; then
  note "no candidate has an empty label"
else
  bad "a candidate with an empty label was offered"
fi
# The UI's own answer to an empty prefix is to do nothing, which is a
# different decision from the gather's and is checked separately.
checks=$((checks + 1))
empty_tab="$(drive 050-imports.session none.pending "" 0 tabs "+" 80)"
if [[ "$empty_tab" == "BUF  CUR 0 ROWS 0
MENUNL 0
ESCBYTES 0" ]]; then
  note "Tab on an empty prefix prints no menu - $cap names is a listing, not a menu"
else
  bad "Tab on an empty prefix did something"
  echo "$empty_tab" | sed 's/^/     /'
fi

# --------------------------------------------------------------
echo "== 8. a command prefix keeps its colon =="
# --------------------------------------------------------------
want_t="$(printf '%s\n' "$derived_cmds" | grep '^:t' | sort)"
checks=$((checks + 1))
got_t="$(drive 050-imports.session none.pending ":t" 2 cands | grep '^C ' | awk '{print $2}' | sort)"
if [[ "$want_t" == "$got_t" ]]; then
  note "\`:t\` offers exactly $(printf '%s ' $want_t)- the colon is part of the word"
else
  bad "\`:t\` did not offer the commands beginning \`:t\`"
  diff <(echo "$want_t") <(echo "$got_t") | sed 's/^/     /'
fi
checks=$((checks + 1))
if [[ -z "$(drive 050-imports.session none.pending ":t" 2 cands | grep -vE '^(C |COUNT )')" ]]; then
  note "and nothing else: a command position offers commands alone"
else
  bad "an identifier was offered in command position"
fi

# --------------------------------------------------------------
echo "== 9. the Tab state machine: extend, list, cycle, wrap, back =="
# --------------------------------------------------------------
checks=$((checks + 1))
tabs_raw="$(drive 040-ambiguous.session none.pending "hel" 3 tabs "+++++-" 80)"
tabs_out="$(echo "$tabs_raw" | grep -v '^ESCBYTES ')"
read -r -d '' tabs_want <<'WANT'
BUF help CUR 4 ROWS 0
MENUNL 0
BUF help CUR 4 ROWS 1
MENUNL 1
BUF helper CUR 6 ROWS 2
MENUNL 2
BUF helpful CUR 7 ROWS 2
MENUNL 2
BUF helper CUR 6 ROWS 2
MENUNL 2
BUF helpful CUR 7 ROWS 2
MENUNL 2
WANT
if [[ "$tabs_out" == "$tabs_want" ]]; then
  note "Tab extends to \`help\` with no menu, then lists, then walks and wraps; Shift-Tab goes back"
else
  bad "the Tab sequence differs"
  diff <(echo "$tabs_want") <(echo "$tabs_out") | sed 's/^/     /'
fi

# The width is the TERMINAL'S, threaded through the state machine
# rather than assumed. At 16 columns the same two candidates no longer
# share a row, so the list step is two rows deep instead of one and the
# editor has two rows to erase. A `replComplTab` holding a literal 80 -
# which it did for one draft - answers the first sequence and gets this
# one wrong, which is the only way to tell the two apart from a
# transcript.
checks=$((checks + 1))
narrow="$(drive 040-ambiguous.session none.pending "hel" 3 tabs "++" 16)"
if [[ "$(echo "$narrow" | grep -v '^ESCBYTES ')" == "BUF help CUR 4 ROWS 0
MENUNL 0
BUF help CUR 4 ROWS 2
MENUNL 2" ]]; then
  note "at 16 columns the same list is 2 rows, not 1 - the width reaches the state machine"
else
  bad "the narrow-terminal Tab sequence differs"
  echo "$narrow" | sed 's/^/     /'
fi

# WORD 2 IS NON-EMPTY EXACTLY WHEN THERE IS SOMETHING TO PRINT. The
# editor writes word 2 and then erases `rows` rows on the next
# keystroke; bytes with no rows would never be erased, and rows with no
# bytes would erase a menu that was never printed. The exact lengths
# are not pinned - they move with the fixture's labels and say nothing -
# but the correspondence is.
checks=$((checks + 1))
pairs_bad="$(paste -d' ' <(echo "$tabs_raw" | grep '^BUF ' | awk '{print $6}') \
                        <(echo "$tabs_raw" | grep '^ESCBYTES ' | awk '{print $2}') \
             | awk '{ if (($1 == 0) != ($2 == 0)) print NR": rows="$1" bytes="$2 }')"
if [[ -z "$pairs_bad" ]]; then
  note "every step prints menu bytes exactly when it reports rows to erase"
else
  bad "a step reported rows with no bytes, or bytes with no rows"
  printf '%s\n' "$pairs_bad" | sed 's/^/     /'
fi

# --------------------------------------------------------------
echo "== 9b. Escape puts back what was typed, and erases what it printed =="
# --------------------------------------------------------------
# The erase is asserted by ITS BYTE COUNT and by carrying no newline,
# which is the property that matters and the one a transcript cannot
# show: `replComplErase` moves down with `ESC [ B` rather than a
# newline, because a newline at the bottom of the screen SCROLLS and
# takes the input line out from under the editor's redraw. One row is
# `ESC [ B` (3) + `ESC [ 2K` (4) + `ESC [ 1A` (4) = 11 bytes.
checks=$((checks + 1))
cancel_out="$(drive 040-ambiguous.session none.pending "hel" 3 tabs "++." 80)"
if [[ "$(echo "$cancel_out" | tail -3)" == "BUF hel CUR 3 ROWS 0
MENUNL 0
ESCBYTES 11" ]]; then
  note "Escape restores \`hel\`, and answers an 11-byte erase with no newline in it"
else
  bad "Escape did not restore the typed prefix or its erase is the wrong shape"
  echo "$cancel_out" | tail -3 | sed 's/^/     /'
fi

# --------------------------------------------------------------
echo "== 10. the menu's reported height is the height it renders =="
# --------------------------------------------------------------
# The editor moves down and erases by `replComplRows`; the screen is
# dirtied by the bytes. A disagreement is debris on the terminal and
# there is no way to see it from a transcript, so it is asserted here
# for every shape the menu has: one page, a paged one, a selection, and
# a narrow terminal that forces one column.
menus=0
for spec in "040-ambiguous.session|hel|3|n|80" \
            "040-ambiguous.session|hel|3|0|80" \
            "050-imports.session|str|3|n|80" \
            "050-imports.session|s|1|n|80" \
            "050-imports.session|s|1|45|80" \
            "010-stdlib.session|strIs|5|n|30"; do
  IFS='|' read -r f b c s w <<< "$spec"
  out="$(drive "$f" none.pending "$b" "$c" menu "$s" "$w")"
  rows="$(echo "$out" | grep '^ROWS ' | awk '{print $2}')"
  nl="$(echo "$out" | grep '^MENUNL ' | awk '{print $2}')"
  menus=$((menus + 1))
  checks=$((checks + 1))
  if [[ "$rows" == "$nl" && "$rows" -gt 0 ]]; then
    note "$b at width $w, sel $s: $rows rows reported, $nl rendered"
  else
    bad "$b at width $w, sel $s: reports $rows rows and renders $nl"
  fi
done
checks=$((checks + 1))
if (( menus >= 6 )); then
  note "$menus menu shapes measured"
else
  bad "only $menus menu shapes measured; the floor is 6"
fi

# --------------------------------------------------------------
echo "== 10b. no menu is ever wider than the terminal it was laid out for =="
# --------------------------------------------------------------
# EXHAUSTIVE, because the interesting widths are the ones nobody picks
# by hand. Every width from 1 to 100, plus the three a terminal query
# can answer that are not widths at all: 0 (a pty that was never
# sized, through a SUCCESSFUL ioctl - stdlib/Sys.ax says so on
# `sysTermSize`), and -25/-9 (ENOTTY and EBADF, which is what an
# editor hands over if it passes `sysTermSize`'s return value where it
# meant `sysTermCols`' field). Four selection states each, including
# two that are OUT OF RANGE for the candidate vector.
#
# Three properties, on every one of them:
#   * the reported row count equals the rendered newline count;
#   * no rendered line is wider than the terminal, counting neither
#     escapes nor UTF-8 continuation bytes;
#   * zero rows means zero bytes - the editor must not be told to
#     erase nothing while something was printed, or the reverse.
#
# The sweep runs inside ONE process, in `runSweep`, because a
# subprocess per width would cost more than the check.
sweep_ok=1
sweep_crashed=0
sweep_lines=0
sweep_rendered=0
sweep_suppressed=0
for fx in 050-imports.session 040-ambiguous.session 010-stdlib.session; do
  case "$fx" in
    050-imports.session)   sb=str;   sc=3 ;;
    040-ambiguous.session) sb=hel;   sc=3 ;;
    010-stdlib.session)    sb=strIs; sc=5 ;;
  esac
  if ! out="$(drive "$fx" none.pending "$sb" "$sc" sweep 2>&1)"; then
    # A harness that DIED is not a sweep that found nothing. Without
    # this arm the failure surfaced as "the sweep produced only 8
    # layouts", which names the floor rather than the segfault that
    # tripped it.
    sweep_ok=0
    sweep_crashed=1
    bad "the harness DIED part-way through the width sweep ($fx, prefix \`$sb\`)"
    printf '%s\n' "$out" | tail -2 | sed 's/^/       /'
  fi
  n=$(printf '%s\n' "$out" | grep -c '^W ')
  sweep_lines=$((sweep_lines + n))
  sweep_rendered=$((sweep_rendered + $(printf '%s\n' "$out" | grep -c ' ROWS [1-9]')))
  sweep_suppressed=$((sweep_suppressed + $(printf '%s\n' "$out" | grep -c ' ROWS 0 ')))
  offenders="$(printf '%s\n' "$out" | awk '
    { w=$2; rows=$6; nl=$8; vis=$10;
      eff = (w+0 <= 0) ? 80 : w+0;
      if (rows != nl)                 print "  " $0 "   (rows != newlines)";
      else if (rows == 0 && vis != 0) print "  " $0 "   (0 rows, but bytes)";
      else if (rows != 0 && vis > eff) print "  " $0 "   (line wider than the terminal)";
    }')"
  if [[ -n "$offenders" ]]; then
    sweep_ok=0
    echo "     $fx / $sb:"
    printf '%s\n' "$offenders" | head -6
  fi
done
checks=$((checks + 1))
if (( sweep_lines < 900 )); then
  if (( sweep_crashed )); then
    echo "ABORT: the width sweep stopped at $sweep_lines layouts because the harness"
    echo "       CRASHED, not because it ran out of widths - see the FAIL above. The"
    echo "       floor is reported second so it cannot be mistaken for the cause."
  else
    echo "ABORT: the width sweep produced only $sweep_lines layouts; the floor is 900."
    echo "       A sweep that stopped sweeping is the defect this file exists to refuse."
  fi
  exit 1
fi
note "$sweep_lines layouts swept: $sweep_rendered rendered, $sweep_suppressed suppressed"
checks=$((checks + 1))
if (( sweep_rendered < 100 || sweep_suppressed < 10 )); then
  bad "the sweep found $sweep_rendered rendered and $sweep_suppressed suppressed - it must exercise both"
else
  note "both outcomes are exercised, so neither branch is asserted vacuously"
fi
checks=$((checks + 1))
if (( sweep_ok )); then
  note "at every width, rows == rendered lines, nothing exceeds the terminal, 0 rows means 0 bytes"
else
  bad "a menu was wider than its terminal, or misreported its height"
fi

# --------------------------------------------------------------
echo "== 11. the truncation line tells the truth about the page =="
# --------------------------------------------------------------
total="$(drive 050-imports.session none.pending "s" 1 cands | tail -1 | awk '{print $2}')"
checks=$((checks + 1))
if (( total > 40 )); then
  note "prefix \`s\` gathers $total candidates - more than one screen holds"
else
  bad "prefix \`s\` gathered only $total; this layer needs an overflowing menu"
fi
for sel in n 45; do
  more="$(drive 050-imports.session none.pending "s" 1 menu "$sel" 80 | grep -oE '\.\.\. [0-9]+-[0-9]+ of [0-9]+')"
  checks=$((checks + 1))
  if [[ "$more" == *"of $total" ]]; then
    note "at sel=$sel it says '$more' - the range on screen, out of everything Tab walks"
  else
    bad "at sel=$sel the truncation line said '$more', not a range out of $total"
  fi
done

# --------------------------------------------------------------
echo "== 12. the escape stream stays inside style.ax's alphabet =="
# --------------------------------------------------------------
alphabet="$(grep -oE '"[0-9;]+"' "$repo_root/self_host/style.ax" | tr -d '"' | sort -u)"
n_alpha=$(printf '%s\n' "$alphabet" | grep -c .)
checks=$((checks + 1))
if (( n_alpha < 5 )); then
  echo "ABORT: only $n_alpha SGR parameters found in self_host/style.ax."
  exit 1
fi
note "$n_alpha SGR parameters declared in style.ax"
drive 050-imports.session none.pending "s" 1 menu 45 80 > "$work/menu.bytes"
checks=$((checks + 1))
if python3 - "$work/menu.bytes" <<PY
import re, sys
alphabet = set("""$alphabet""".split())
data = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
params = re.findall(r"\x1b\[([0-9;]*)m", data)
bad = [p for p in params if p != "0" and p not in alphabet]
if bad:
    print("FAIL: the menu emitted SGR %s, which self_host/style.ax does not declare" % sorted(set(bad)))
    sys.exit(1)
opens = [p for p in params if p != "0"]
resets = [p for p in params if p == "0"]
if len(opens) != len(resets):
    print("FAIL: %d opening escapes and %d resets - they must pair" % (len(opens), len(resets)))
    sys.exit(1)
ident = re.compile(r"[A-Za-z0-9_]")
for m in re.finditer(r"\x1b\[[0-9;]*m", data):
    before, after = data[m.start()-1:m.start()], data[m.end():m.end()+1]
    if before and after and ident.match(before) and ident.match(after):
        print("FAIL: an escape sits between two identifier bytes at offset %d" % m.start())
        sys.exit(1)
if len(opens) < 5:
    print("FAIL: only %d painted fragments in the menu; nothing was really checked" % len(opens))
    sys.exit(1)
print("     %d painted fragments, %d resets, all inside the declared alphabet" % (len(opens), len(resets)))
PY
then
  note "every escape the menu emits is style.ax's, paired, and wraps a whole lexeme"
else
  bad "the menu's escape stream is outside style.ax's alphabet or unpaired"
fi

echo
if (( failed > 0 )); then
  echo "check-replcomp: $failed of $checks checks failed"
  exit 1
fi
echo "check-replcomp: $checks checks - the candidate set at a cursor is derived from"
echo "                repl.ax's dispatch, stdlib/Str.ax and lsp.ax's own cap rather"
echo "                than blessed; a name that exists in no file completes; and the"
echo "                menu's reported height is the height it renders"
