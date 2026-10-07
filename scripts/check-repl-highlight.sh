#!/usr/bin/env bash
# ---------------------------------------------------------------------
# The REPL highlighter: what `tests/selfhost/272-highlight.ax` cannot
# check from inside a single fixture.
#
# The fixture is the primary gate. It runs in the sweep of
# `tests/selfhost/*.ax` by `check-self-host.sh` and `check-bootstrap.sh`:
# twenty part-typed buffers, each with its classification, paren depth
# and matching delimiter written by hand, plus a negative control, an
# escape-byte floor and a distinct-letter floor. It cannot compare itself
# with a module it does not import, read its own source, or prove it can
# fail. The layers below do those.
#
# This gate tests the leaf module `self_host/replhl.ax`, not the
# compiler, so it does not call `gate_build_axc`. The resolved `$axiom`
# compiles a fixture that imports the working tree's `replhl.ax`, so
# every edit to that file is visible. Staying out of `gate_build_axc`
# also keeps this gate out of the count `check-gate-lib.sh` checks.
#
# Nothing here writes the working tree or touches
# `/tmp/axiom-repl-<pid>.d`, so it can run beside the two REPL gates.
# ---------------------------------------------------------------------

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
# The fixture and generated probes import the working tree's leaf modules.
export AXIOM_PATH="$repo_root/self_host${AXIOM_PATH:+:$AXIOM_PATH}"

failed=0
checks=0

fixture=tests/selfhost/272-highlight.ax
module=self_host/replhl.ax

# ---------------------------------------------------------------------
# Layer 1: the fixture answers what its own first line says.
#
# The expected status is read from the file, not copied here. A second
# copy is one more number that could be blessed into agreement with the
# classifier it checks.
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
    echo "      1..20   the classification of that case moved"
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
# Layer 2: the reconciliation, which is why this script exists.
#
# `replParenDepth` in repl.ax decides whether the REPL waits for another
# line. That is piped-surface behaviour, so the highlighter may not
# change it. The highlighter keeps its own typed bracket walk, because
# `replParenDepth`'s single mixed counter cannot tell `( ]` from a
# balanced form. Two walks over the same brackets drift, and the symptom
# is the prompt calling a form closed while the REPL waits for a line.
#
# So they are compared on real source: every prefix of every line of
# three compiler modules, the mid-edit states a person types through.
# The fixture cannot do this, because importing `repl` pulls in `driver`
# and `codegen`, far too much for a case built on every run.
#
# The same sweep checks two whole-buffer invariants at scale, with the
# cursor at the edit point, as the editor calls it on every keystroke:
#
#   the HlSpans partition [0, strLen pre): contiguous, non-empty,
#   starting at 0 and ending exactly at the end          total coverage
#   visLen (replHlPaint pre cur 0) == visLen pre         the wrap property
#
# Coverage is re-derived from the public span accessors. `replHlClass`
# answers one `strAlloc` of the source length whatever the scanner did,
# so a check that asked it could never fail.
#
# The fixture's hand-written cases pin the classification. The sweep's
# real buffers pin that nothing drops a byte, runs a comment scan off
# the end, or paints a slice at the wrong offset. Neither replaces the
# other.
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
        (let ((stop (match (strFindByte src 10 i)
            ((None) n)
            ((Some e) e)
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
        ))
      (writeStr stdout (concat "swept " (concat (fmtI cmp) (concat " mid-edit buffers of " (concat path (concat ", " (concat (fmtI bad) " failures\n")))))))
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
    (concat (fmtI (/ x 10)) (strSlice "0123456789" (% x 10) 1))
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
# Layer 3: the declaration heads exist twice, and the copy is checked.
#
# `isDeclLine` in repl.ax holds them inline in one boolean over a whole
# line, so it is not callable as a name predicate, and this subsystem
# does not modify repl.ax. `hlIsDeclHead` is a copy. A head missing from
# a copy sends that declaration down the expression path; the note under
# `isDeclLine` shows what that did to `impl`.
# ---------------------------------------------------------------------
# The sed range ends at the blank line after the function. The formatter
# joins the closing parens onto the boolean's last line, so a range
# ending at a bare `)` line would run on into `replDispatch`'s command
# words, which are not declaration heads.
heads_of() {  # <file> <function name> -> the quoted words, sorted
  sed -n "/pub fn ($2 /,/^$/p" "$1" \
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
# Layer 4: no tenth colour.
#
# Every colour the highlighter uses must be one of style.ax's nine
# exported constants. ESC has no literal spelling (`isEscapeChar` accepts
# exactly \n \t \r \\ \" \' \0), so a colour cannot be written inline
# as an escape. An SGR parameter string can be: `(paint "1;31" x)` would
# compile and hide a tenth colour outside the palette.
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

# An SGR parameter string spelled by hand. Any string of only digits and
# semicolons, such as `"1;31"`, `"93"` or `"0"`, is a colour, and colours
# live only in the palette.
checks=$((checks + 1))
if grep -n '"[0-9][0-9;]*"' "$module" | grep -v '^[0-9]*:;' >"$work/inline.txt"; then
  echo "FAIL: $module spells an SGR parameter string of its own:"
  sed 's/^/    /' "$work/inline.txt"
  failed=$((failed + 1))
else
  echo "ok   $module spells no colour of its own"
fi

# ---------------------------------------------------------------------
# The negative controls: proof that layer 1 can fail.
#
# Layer 1 alone passes a highlighter that is wired in and does nothing,
# and one whose expectations were edited to agree with it. So the module
# is copied to a scratch tree and broken two ways, and the fixture must
# notice each with the exact status that names the break. Neither probe
# writes the working tree.
#
# The two breaks are this subsystem's real risks. The first paints a
# keyword in every position, not only at a form head, so the ordinary
# name `data` in case 1, `(fn (g data) data)`, reads as a keyword. The
# second is a highlighter that is present, imported and silent.
# ---------------------------------------------------------------------
probe() {  # <label> <python edit> <expected status>
  local label="$1" edit="$2" expect="$3"
  local sandbox="$work/neg-$expect"
  rm -rf "$sandbox"
  mkdir -p "$sandbox/tests/selfhost"
  cp -R self_host "$sandbox/self_host"
  cp "$fixture" "$sandbox/tests/selfhost/"
  # The edit must land. A `replace` that matched nothing would leave the
  # module intact, the fixture would answer 42, and this probe would
  # blame the fixture for missing a break that was never made.
  python3 - "$sandbox/$module" <<PYEOF
import sys
p = sys.argv[1]
s = orig = open(p).read()
$edit
assert s != orig, "the ablation matched nothing in " + p
open(p, "w").write(s)
PYEOF
  set +e
  ( cd "$sandbox" && AXIOM_PATH="$sandbox/self_host${AXIOM_PATH:+:$AXIOM_PATH}" "$axiom" run "$fixture" >/dev/null 2>&1 )
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
