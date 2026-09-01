#!/usr/bin/env bash
# ---------------------------------------------------------------------
# The REPL highlighter: the three things `tests/selfhost/272-highlight.ax`
# cannot say from inside a single fixture.
#
# The fixture is the primary gate and it runs for free, on every build,
# inside `check-self-host.sh`'s and `check-bootstrap.sh`'s existing
# sweep of `tests/selfhost/*.ax` - seventeen buffers a person could be
# part-way through typing, each with its classification, its paren
# depth and its matching-delimiter answer written by hand beside it,
# plus a negative control, an escape-byte floor and a distinct-letter
# floor. What it cannot do is compare itself with a module it does not
# import, read its own source, or prove it is able to go red at all.
# Those are the four layers here.
#
# THIS SCRIPT DOES NOT CALL `gate_build_axc`, deliberately. It does not
# test the compiler built from `self_host/`; it tests `replhl.ax` - a
# leaf module - and for that the resolved `$axiom` compiling a fixture
# that IMPORTS the working tree's `self_host/replhl.ax` makes every
# ablation of that file visible, which is the whole property
# `gate_build_axc` buys elsewhere. Staying out of that count also
# keeps this gate off the six prose sites `check-gate-lib.sh` sweeps.
#
# Run order: nothing here writes the working tree, and nothing here
# touches `/tmp/axiom-repl-<pid>.d`, so it is safe beside the two REPL
# gates rather than serial with them.
# ---------------------------------------------------------------------

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

failed=0
checks=0

fixture=tests/selfhost/272-highlight.ax
module=self_host/replhl.ax

# ---------------------------------------------------------------------
# LAYER 1 - the fixture answers what its own first line says.
#
# The expected status is READ from the file rather than typed here.
# Two copies of a number are two things to keep in step, and this is
# the gate whose subject is a classifier that must not be blessed into
# agreement with itself.
# ---------------------------------------------------------------------
want="$(sed -n '1s/^; expect \([0-9]*\).*/\1/p' "$fixture")"
checks=$((checks + 1))
if [[ -z "$want" ]]; then
  echo "FAIL: $fixture has no '; expect N' on its first line, so nothing was checked"
  failed=$((failed + 1))
elif [[ "$want" == 0 ]]; then
  echo "FAIL: $fixture expects 0, which is indistinguishable from a silent failure"
  failed=$((failed + 1))
else
  set +e
  "$axiom" run "$fixture" >"$work/fixture.out" 2>"$work/fixture.err"
  got=$?
  set -e
  if [[ "$got" == "$want" ]]; then
    echo "ok   $fixture answers $got"
  else
    echo "FAIL: $fixture answered $got, not $want"
    echo "      1..17   the classification of that case moved"
    echo "      50+i    visLen(painted) != visLen(source) for that case"
    echo "      100+i   replHlDepth disagreed with the hand-written depth"
    echo "      150+i   replHlMatch named the wrong partner"
    echo "      200     the negative control passed - the comparator cannot fail"
    echo "      201     no escape byte anywhere - the painter stopped painting"
    echo "      202     fewer than 9 distinct class letters"
    head -5 "$work/fixture.err" | sed 's/^/    /'
    failed=$((failed + 1))
  fi
fi

# ---------------------------------------------------------------------
# LAYER 2 - THE RECONCILIATION, which is why this script exists.
#
# `replParenDepth` (repl.ax:1406) decides whether the REPL waits for
# another physical line. That answer is PIPED-SURFACE behaviour, so the
# highlighter may not change it - and the highlighter has its own,
# typed bracket walk, because `replParenDepth`'s single mixed counter
# cannot tell `( ]` from a balanced form. Two walks over the same
# brackets is exactly the shape that drifts, and the drift's symptom is
# the worst kind: the prompt says the form is closed while the REPL
# sits waiting for another line.
#
# So they are compared, on a corpus that is REAL SOURCE rather than a
# hand-picked list: every line of three compiler modules, and every
# PREFIX of every line, which is the mid-edit state a person types
# through. The fixture cannot do this - importing `repl` means
# importing `driver` and `codegen`, sixty thousand lines, in a case
# that `check-self-host.sh` builds on every run.
#
# The same sweep carries the two whole-buffer invariants at scale,
# with the cursor at the edit point - which is the call the editor
# actually makes on every keystroke:
#
#   the HlSpans partition [0, strLen pre) - contiguous, non-empty,
#   starting at 0 and ending exactly at the end          total coverage
#   visLen (replHlPaint pre cur 0) == visLen pre         the wrap property
#
# Coverage is re-derived HERE from the public span accessors rather
# than asked of `replHlClass`, whose result is one `strAlloc` of the
# source length and therefore has that length whatever the scanner
# did. That spelling was written first and was a check that could not
# fail; it is named rather than quietly replaced.
#
# Seventeen hand-written cases pin the CLASSIFICATION; eighty thousand
# real ones pin that nothing anywhere drops a byte, runs a comment
# scan off the end, or paints a slice at the wrong offset. Neither is
# the other's substitute.
# ---------------------------------------------------------------------
cat > "$work/reconcile.ax" <<'AXEOF'
(import Str)

(import Vec)

(import IO)

(import style)

(import repl)

(import replhl)

; The spans cover [0, n) with no gap, no overlap and nothing empty.
; Walked from the module's own public accessors, so the gate re-derives
; the property instead of asking the module to grade itself.
(:: spansCover (-> String Int))

(fn (spansCover src)
  (let (
    (sp (hlScanSpans (hlScan src)))
    (n (strLen src))
    (mut i 0)
    (mut p 0)
    (mut ok 1)
  )
    {
      (while (< i (vecLen sp))
        {
          (let ((s (vecGet sp i)))
            {
              (set ok (if (== (hlSpanStart s) p)
                ok
                0
              ))
              (set ok (if (> (hlSpanEnd s) (hlSpanStart s))
                ok
                0
              ))
              (set p (hlSpanEnd s))
            }
          )
          (set i (+ i 1))
        })
      (if (&& (== ok 1) (== p n))
        1
        0
      )
    }
  )
)

(:: sweepLine (-> String Int Int Int))

(fn (sweepLine line acc bad)
  (let (
    (n (strLen line))
    (mut i 0)
    (mut b bad)
  )
    {
      (while (<= i n)
        {
          (let ((pre (strSlice line 0 i)))
            {
              (set b (if (== (replParenDepth pre) (replHlDepth pre))
                b
                (+ b 1)
              ))
              (set b (if (== (spansCover pre) 1)
                b
                (+ b 1000)
              ))
              (set b (if (== (visLen (replHlPaint pre i 0)) (visLen pre))
                b
                (+ b 1000000)
              ))
            }
          )
          (set i (+ i 1))
        })
      b
    }
  )
)

(:: sweepFile (-> String Int))

;@axiom:effect(io)
(fn (sweepFile path)
  (let (
    (src (readFile path))
    (n (strLen src))
    (mut i 0)
    (mut cmp 0)
    (mut bad 0)
  )
    {
      (while (< i n)
        (let ((e (strFindByte src 10 i)))
          (let ((stop (if (< e 0)
            n
            e
          )))
            {
              (let ((line (strSlice src i (- stop i))))
                {
                  (set bad (sweepLine line 0 bad))
                  (set cmp (+ cmp (+ (strLen line) 1)))
                }
              )
              (set i (+ stop 1))
            }
          )
        ))
      (writeStr 1 (strConcat "swept " (strConcat (fmtI cmp) (strConcat " mid-edit buffers of " (strConcat path (strConcat ", " (strConcat (fmtI bad) " failures\n")))))))
      (if (> bad 0)
        1
        ; A per-file floor, so a path that moved makes this fail
        ; rather than agree about nothing. The smallest of the three
        ; modules is style.ax at 6,995 buffers.
        (if (< cmp 5000)
          2
          0
        )
      )
    }
  )
)

(:: fmtI (-> Int String))

(fn (fmtI x)
  (if (< x 10)
    (strSlice "0123456789" x 1)
    (strConcat (fmtI (/ x 10)) (strSlice "0123456789" (% x 10) 1))
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let ((a (sweepFile "self_host/replhl.ax")))
    (let ((b (sweepFile "self_host/style.ax")))
      (let ((c (sweepFile "self_host/lexer.ax")))
        (if (> (+ a (+ b c)) 0)
          (+ a (+ b c))
          42
        )
      )
    )
  )
)
AXEOF
checks=$((checks + 1))
if ! "$axiom" build "$work/reconcile.ax" -o "$work/reconcile" >"$work/reconcile.build" 2>&1; then
  echo "FAIL: could not build the depth-reconciliation probe"
  head -20 "$work/reconcile.build" | sed 's/^/    /'
  failed=$((failed + 1))
else
  set +e
  "$work/reconcile" >"$work/reconcile.out" 2>&1
  rc=$?
  set -e
  sed 's/^/     /' "$work/reconcile.out"
  if [[ "$rc" == 42 ]]; then
    echo "ok   every mid-edit prefix of three modules: total coverage, visLen preserved, and replHlDepth == replParenDepth"
  elif [[ "$rc" == 2 ]]; then
    echo "FAIL: the reconciliation swept too few buffers - a path moved and it measured almost nothing"
    failed=$((failed + 1))
  else
    echo "FAIL: the mid-edit sweep found failures (status $rc). The count printed above"
    echo "      says which invariant: under 1000 is replHlDepth disagreeing with"
    echo "      replParenDepth - the prompt would call a form closed while the REPL waits"
    echo "      for another line, or the reverse, and replParenDepth is the piped surface"
    echo "      that must not move. A multiple of 1000 is coverage: replHlClass did not"
    echo "      answer one letter per source byte. A multiple of 1000000 is the paint:"
    echo "      visLen(painted) != visLen(source), which breaks the editor's wrapping."
    failed=$((failed + 1))
  fi
fi

# ---------------------------------------------------------------------
# LAYER 3 - the twelve declaration heads exist twice, and the copy is
# checked.
#
# `isDeclLine` (repl.ax:221) holds them inline inside one boolean over a
# whole LINE, so it is not callable as a name predicate, and this
# subsystem does not modify repl.ax. `hlIsDeclHead` is therefore a
# copy - and the comment directly under `isDeclLine` records what an
# unchecked copy of this exact list already cost once, when `impl` was
# missing from it and a trait implementation typed at the prompt was
# read as an application.
# ---------------------------------------------------------------------
heads_of() {  # <file> <function name> -> the quoted words, sorted
  sed -n "/pub fn ($2 /,/^)/p" "$1" \
    | grep -o '(strEq [a-z]* "[^"]*")' \
    | sed 's/.*"\(.*\)".*/\1/' \
    | LC_ALL=C sort
}
repl_heads="$(heads_of self_host/repl.ax isDeclLine)"
hl_heads="$(heads_of "$module" hlIsDeclHead)"
n_repl="$(printf '%s\n' "$repl_heads" | grep -c . || true)"
n_hl="$(printf '%s\n' "$hl_heads" | grep -c . || true)"

checks=$((checks + 1))
if (( n_repl < 10 )); then
  echo "FAIL: read only $n_repl declaration heads out of repl.ax's isDeclLine - the extraction broke,"
  echo "      and a census that reads nothing is indistinguishable from one that agrees"
  failed=$((failed + 1))
elif [[ "$repl_heads" == "$hl_heads" ]]; then
  echo "ok   $n_hl declaration heads, identical in repl.ax's isDeclLine and $module's hlIsDeclHead"
else
  echo "FAIL: the declaration-head lists have drifted ($n_repl in repl.ax, $n_hl in $module)"
  diff <(printf '%s\n' "$repl_heads") <(printf '%s\n' "$hl_heads") | sed 's/^/    /' || true
  failed=$((failed + 1))
fi

# ---------------------------------------------------------------------
# LAYER 4 - no tenth colour.
#
# Every colour the highlighter uses must be one of style.ax's nine
# exported constants. The language half-enforces this already: ESC has
# no literal spelling (`isEscapeChar` accepts exactly \n \t \r \\ \" \'
# \0), so a colour cannot be written inline as an escape - but an SGR
# PARAMETER string can be, and `(paint "1;31" x)` would compile fine
# and put a tenth colour in a file nobody looks at for a palette.
# ---------------------------------------------------------------------
used="$(grep -o 'SGR_[A-Z]*' "$module" | LC_ALL=C sort -u)"
n_used="$(printf '%s\n' "$used" | grep -c . || true)"
checks=$((checks + 1))
if (( n_used < 5 )); then
  echo "FAIL: found only $n_used SGR constants in $module - it paints with almost nothing, or the scan broke"
  failed=$((failed + 1))
else
  unknown=0
  for name in $used; do
    if ! grep -q "^(pub :: $name String)" self_host/style.ax; then
      echo "FAIL: $module uses $name, which style.ax does not export"
      unknown=$((unknown + 1))
    fi
  done
  if (( unknown == 0 )); then
    echo "ok   all $n_used colours in $module come from style.ax's palette"
  else
    failed=$((failed + 1))
  fi
fi

# An SGR parameter string spelled by hand. `"1;31"`, `"93"`, `"0"` -
# anything that is only digits and semicolons - is a colour, and the
# palette is the only place one may live.
checks=$((checks + 1))
if grep -n '"[0-9][0-9;]*"' "$module" | grep -v '^[0-9]*:;' >"$work/inline.txt"; then
  echo "FAIL: $module spells an SGR parameter string of its own:"
  sed 's/^/    /' "$work/inline.txt"
  failed=$((failed + 1))
else
  echo "ok   $module spells no colour of its own"
fi

# ---------------------------------------------------------------------
# THE NEGATIVE CONTROLS - the part that proves layer 1 can fail.
#
# Layer 1 as stated is passed perfectly by a highlighter that is wired
# in and does nothing, and by one whose expectations were edited to
# agree with it. So the module is copied to a scratch tree, broken two
# ways, and the fixture is REQUIRED to notice - each with the exact
# status that names the break. Neither probe writes the working tree.
#
# The two breaks are the two defects this subsystem was actually at
# risk of. The first is the one this repository has already paid for
# once: `fpIsReservedWord` reserved thirty-two words in EVERY position
# and was deleted on 2026-08-28 because it made `fmt` refuse
# `(fn (g data) data)` while `check` accepted it. The second is a
# highlighter that is present, imported and silent.
# ---------------------------------------------------------------------
probe() {  # <label> <python edit> <expected status>
  local label="$1" edit="$2" expect="$3"
  local sandbox="$work/neg-$expect"
  rm -rf "$sandbox"
  mkdir -p "$sandbox/tests/selfhost"
  cp -R self_host "$sandbox/self_host"
  cp "$fixture" "$sandbox/tests/selfhost/"
  # The edit must actually LAND. A `replace` that matched nothing
  # would leave the module intact, the fixture would answer 42, and
  # this probe would report "the fixture cannot see this break" about
  # a break that was never made - a probe lying in the direction that
  # looks like a real finding.
  python3 - "$sandbox/$module" <<PYEOF
import sys
p = sys.argv[1]
s = orig = open(p).read()
$edit
assert s != orig, "the ablation matched nothing in " + p
open(p, "w").write(s)
PYEOF
  set +e
  ( cd "$sandbox" && "$axiom" run "$fixture" >/dev/null 2>&1 )
  local rc=$?
  set -e
  checks=$((checks + 1))
  if [[ "$rc" == "$expect" ]]; then
    echo "ok   negative control: $label -> $rc, as it must"
  else
    echo "FAIL: negative control: $label answered $rc, not $expect."
    echo "      The fixture cannot see this break, so its green says less than it appears to."
    failed=$((failed + 1))
  fi
}

probe "a keyword painted in every position, not only a form head" \
      's = s.replace("(if (&& isHead (hlIsKeyword lx))", "(if (hlIsKeyword lx)")' \
      1

probe "every class left unpainted - wired in, emitting no escape" \
      'i = s.index("(pub fn (hlSgr cls)"); j = s.index("; ------------------------------------------------------------------\n; A classified byte range"); s = s[:i] + "(pub fn (hlSgr cls) (if (== cls HL_PLAIN) \"\" \"\"))\n\n" + s[j:]' \
      201

echo
if (( failed )); then
  echo "check-repl-highlight: $failed of $checks checks FAILED"
  exit 1
fi
echo "check-repl-highlight: $checks checks passed"
