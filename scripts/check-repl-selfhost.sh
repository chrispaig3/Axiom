#!/usr/bin/env bash
# The REPL, pinned without a second compiler.
#
# There is no reference compiler to diff against, and a differential
# whose reference is the compiler under test compares it with itself and
# always passes. So the gate pins the REPL in four layers.
#
#   1. Session invariants. Every session exits 0 with stderr empty: the
#      piped-surface contract (no prompt off a TTY, no colour, and results,
#      errors and command chatter all on stdout). There is no per-session
#      status manifest: every session exits 0, and a manifest of one
#      repeated value would pass a REPL that always exits 0.
#
#   2. Byte goldens (NNN-*.golden) for the deterministic surfaces: result
#      types and values for Int, Bool, Char and String, declaration OK
#      lines, `type :` lines, semantic errors, the colon commands, comments
#      and blank lines, `:quit`'s exit without a farewell, a `fn` spanning
#      several lines (130-multiline), and an IO-performing expression that
#      evaluates instead of being refused (140-io; see `replCompileExpr` in
#      self_host/repl.ax). Those two are outside verify-repl.py's model and
#      rest on this byte pin, with values simple enough to check by hand.
#
#   3. Marker shapes (NNN-*-shape.markers) for output that is not fixed
#      text: `:time` prints a duration, `:llvm` prints this compiler's IR,
#      `:defs` lists each declaration indented, an IO body under
#      `restrict(no-io)` is reported, and redefining `f` evaluates the new
#      body instead of refusing every later expression
#      (`replDeclsSrcDropping` in self_host/repl.ax). Only substrings are
#      compared. The markers are hand-maintained and AXIOM_BLESS never
#      writes them, so this layer is a check, not a record. 100-defs-shape
#      requires the `  alpha`, `  beta` and `  gamma` lines that only
#      `replCmdDefs` prints; the declaration echo is `OK: alpha defined`.
#
#   4. Two derived halves a re-bless cannot satisfy. A golden records what
#      the compiler printed, not what it should print: bless a compiler
#      that evaluates `(+ 1 2)` as 4 and `result 4` goes green. Both halves
#      below are computed from files a bless does not write.
#
#      4a. tests/repl/verify-repl.py re-derives each golden it models in
#          Python from the session file's own bytes, with no compiler
#          involved. It evaluates the Int/Bool/Char/String subset the
#          sessions use and predicts the `OK:`, `type :`, `result`,
#          `Type error:` and `Goodbye!` lines. Every modelled golden but
#          050-commands must match byte for byte. 050-commands mixes in
#          `:help`'s banner and the REPL's error wording, which the model
#          must not transcribe, so it is anchored instead: every derived
#          line present and in order, each chatter window at least as long
#          as the commands that fed it, and no modelled line inside a
#          window. So `:reset` must really drop declarations, and
#          `:type (+ 1 2)` must really answer Int. The verifier's floors
#          stop a model that went blind from passing.
#
#      4b. tests/repl/crosscheck/ pairs each REPL session with an ordinary
#          program computing the same value, and the REPL's `result` must
#          equal what the compiled program prints. The REPL types the line,
#          picks a printer from the rendered type, wraps the expression
#          and trims the child's stdout; the program goes through the
#          ordinary driver. A wrong printer, a dropped declaration, a trim
#          that eats a character or a child falling back to its exit code
#          all diverge here, and neither side is a value a bless writes.
#          Limits: 030-zero answers `0` whether the wrapper printed it or
#          the exit-code fallback did, so it cannot fail for the intended
#          reason; the distinct-value floor covers that. The fallback's
#          rendering is never exercised, because every wrapper prints.
#
# The floors and two negative tests are at the bottom. The cross-path one
# is real evidence: it rebuilds a program to compute something else and
# requires the agreement to break. The golden one only shows that `cmp`
# and `sed` still work.
#
# Three faults, and what catches each:
#
#   - The wrapper's Int printer off by one. The goldens, 110-time-shape's
#     `result 3` marker, the Int cross-path cases and the distinct-value
#     floor go red. Re-blessed goldens go green, and layer 4 and the marker
#     still fail the gate.
#   - `:defs` printing its header and no definitions. 100-defs-shape's
#     markers fail, with no re-bless needed.
#   - A `:reset` that announces a reset and keeps every declaration. Layer
#     4a fails both the bless run and the re-run, naming the `type : Int`,
#     `result 1` and `Goodbye!` lines inside the reset window. Layer 2
#     cannot see this.
#
# AXIOM_BLESS=1 regenerates the goldens from the compiler under test and
# still runs layer 4, so a bless cannot launder a wrong answer into a
# modelled golden. It can change the wording inside a chatter window
# unchallenged: `:help`'s banner, the unknown-command and usage errors,
# the reset announcement. Their presence and length are checked, not
# their prose, so read the diff of what you bless.
#
# The REPL keeps its scratch files in a private `<tmp>/axiom-repl-<pid>.d`
# (mode 0700, created exclusively; see `replEval` in self_host/repl.ax).
# Concurrent REPLs don't collide, so this gate need not run serially.
#
# Usage:  scripts/check-repl-selfhost.sh
#         AXIOM_BLESS=1 scripts/check-repl-selfhost.sh
#         scripts/check-repl-selfhost.sh 010     # partial, not a gate result

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

filter="${1:-}"
bless="${AXIOM_BLESS:-0}"

# The compiler under test is built from source by `$axiom`. This gate
# tests self_host/repl.ax, and `$axiom` may be an older seed-descended
# binary that predates the change.
gate_build_axc axc

# Sessions and cross-check programs run from the work dir, where the
# REPL resolves relative imports. HOME and XDG_CONFIG_HOME point there
# too, so a history file never touches the user's real one.
run_repl() {   # run_repl <session-file> <stdout> <stderr>
  (cd "$work" && HOME="$work" XDG_CONFIG_HOME="$work" \
     "$work/axc" repl --no-banner <"$1" >"$2" 2>"$3")
}

failed=0
passed=0
sessions=0
byte_sessions=0
shape_sessions=0

# ---------------------------------------------------------------
# Layers 1-3: the session bank
# ---------------------------------------------------------------
echo "== sessions: exit 0, empty stderr, and the checked-in shapes =="
for sess in tests/repl/*.txt; do
  name="$(basename "$sess" .txt)"
  if [[ -n "$filter" && "$name" != "$filter"* ]]; then
    continue
  fi
  sessions=$((sessions + 1))

  run_repl "$repo_root/$sess" "$work/a.out" "$work/a.err"
  rc=$?

  if [[ "$rc" != 0 ]]; then
    echo "FAIL $name: the piped surface exited $rc, not 0"
    failed=$((failed + 1))
    continue
  fi
  if [[ -s "$work/a.err" ]]; then
    echo "FAIL $name: stderr is not empty ($(wc -c <"$work/a.err" | tr -d ' ')B)"
    head -3 "$work/a.err" | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi
  if [[ ! -s "$work/a.out" ]]; then
    echo "FAIL $name: the session printed nothing at all"
    failed=$((failed + 1))
    continue
  fi

  if [[ "$name" == *-shape ]]; then
    shape_sessions=$((shape_sessions + 1))
    markers="tests/repl/$name.markers"
    if [[ ! -s "$markers" ]]; then
      echo "FAIL $name: $markers is missing or empty - a shape session with"\
           "no required markers asserts nothing"
      failed=$((failed + 1))
      continue
    fi
    ok=1
    nmark=0
    while IFS= read -r marker; do
      [[ -z "$marker" ]] && continue
      nmark=$((nmark + 1))
      if ! grep -qF -- "$marker" "$work/a.out"; then
        echo "FAIL $name: output lacks '$marker'"
        ok=0
      fi
    done < "$repo_root/$markers"
    if [[ "$nmark" == 0 ]]; then
      echo "FAIL $name: $markers has no non-blank marker lines"
      ok=0
    fi
    if [[ "$ok" == 1 ]]; then
      echo "ok   $name  $nmark required marker(s) present"
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    continue
  fi

  byte_sessions=$((byte_sessions + 1))
  golden="tests/repl/$name.golden"
  if [[ "$bless" == 1 ]]; then
    cp "$work/a.out" "$repo_root/$golden"
    echo "blessed $name ($(wc -c <"$golden" | tr -d ' ')B)"
    passed=$((passed + 1))
    continue
  fi

  if [[ ! -f "$golden" ]]; then
    echo "FAIL $name (no golden; run with AXIOM_BLESS=1)"
    failed=$((failed + 1))
    continue
  fi
  if [[ ! -s "$golden" ]]; then
    echo "FAIL $name (golden is empty - agreement by silence)"
    failed=$((failed + 1))
    continue
  fi
  if ! cmp -s "$golden" "$work/a.out"; then
    echo "FAIL $name: diverged from the checked-in golden"
    diff "$golden" "$work/a.out" | head -6 | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi
  echo "ok   $name  $(wc -c <"$golden" | tr -d ' ')B byte-identical to the golden"
  passed=$((passed + 1))
done

if [[ -n "$filter" ]]; then
  echo
  echo "PARTIAL RUN (filter '$filter'): floors and both derived halves were"
  echo "skipped. This is not a gate result."
  echo "check-repl-selfhost: $passed passed, $failed failed ($sessions sessions)"
  [[ "$failed" == 0 ]]
  exit
fi

# ---------------------------------------------------------------
# Layer 4a: the transcripts, re-derived in another language
# ---------------------------------------------------------------
echo
echo "== transcripts re-derived from the session sources, in Python =="
if ! python3 tests/repl/verify-repl.py tests/repl; then
  echo "FAIL: a golden is not what its session evaluates to"
  failed=$((failed + 1))
fi

# ---------------------------------------------------------------
# Layer 4b: REPL result == the same expression compiled and run
# ---------------------------------------------------------------
echo
echo "== cross-path: the REPL's result against the ordinary driver's =="
cases=0
: > "$work/results.txt"
for case in tests/repl/crosscheck/*.repl; do
  cname="$(basename "$case" .repl)"
  prog="tests/repl/crosscheck/$cname.ax"
  if [[ ! -s "$prog" ]]; then
    echo "FAIL $cname: no program at $prog to cross-check against"
    failed=$((failed + 1))
    continue
  fi
  cases=$((cases + 1))

  run_repl "$repo_root/$case" "$work/c.out" "$work/c.err"
  crc=$?
  if [[ "$crc" != 0 || -s "$work/c.err" ]]; then
    echo "FAIL $cname: the REPL exited $crc with $(wc -c <"$work/c.err" | tr -d ' ')B on stderr"
    failed=$((failed + 1))
    continue
  fi
  # The value the REPL announced, from `result ` lines only. A session
  # that errored has none, and the emptiness check below catches it.
  repl_val="$(grep '^result ' "$work/c.out" | tail -1 | sed 's/^result //')"

  if ! "$work/axc" build --input "$repo_root/$prog" --output "$work/c.bin" \
        >"$work/c.build.log" 2>&1; then
    echo "FAIL $cname: $prog does not build"
    tail -5 "$work/c.build.log" | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi
  (cd "$work" && ./c.bin >"$work/c.prog" 2>"$work/c.progerr")
  prc=$?
  if [[ "$prc" != 0 || -s "$work/c.progerr" ]]; then
    echo "FAIL $cname: the program exited $prc with $(wc -c <"$work/c.progerr" | tr -d ' ')B on stderr"
    failed=$((failed + 1))
    continue
  fi
  prog_val="$(sed -e 's/[[:space:]]*$//' "$work/c.prog" | tail -1)"

  if [[ -z "$repl_val" ]]; then
    echo "FAIL $cname: the REPL printed no result line - comparing nothing"
    head -5 "$work/c.out" | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi
  if [[ -z "$prog_val" ]]; then
    echo "FAIL $cname: the compiled program printed nothing - comparing nothing"
    failed=$((failed + 1))
    continue
  fi
  if [[ "$repl_val" != "$prog_val" ]]; then
    echo "FAIL $cname: the REPL evaluates this expression differently from the"\
         "same expression compiled: repl '$repl_val', program '$prog_val'"
    failed=$((failed + 1))
    continue
  fi
  echo "$repl_val" >> "$work/results.txt"
  echo "ok   $cname  repl and driver both answer '$repl_val'"
done

# ---------------------------------------------------------------
# Floors and anti-vacuousness
# ---------------------------------------------------------------
echo
if [[ "$sessions" -lt 14 ]]; then
  echo "FAIL: swept $sessions sessions; the floor is 14 - the glob stopped matching"
  failed=$((failed + 1))
fi
if [[ "$byte_sessions" -lt 10 ]]; then
  echo "FAIL: only $byte_sessions byte-gated sessions; the floor is 10"
  failed=$((failed + 1))
fi
if [[ "$shape_sessions" -lt 4 ]]; then
  echo "FAIL: only $shape_sessions marker-gated sessions; the floor is 4"
  failed=$((failed + 1))
fi
if [[ "$cases" -lt 6 ]]; then
  echo "FAIL: only $cases cross-path cases; the floor is 6"
  failed=$((failed + 1))
fi

# A bank of identical goldens proves nothing: it would be satisfied by a
# REPL that prints one fixed transcript for every input. `cksum <file`
# rather than md5/md5sum, which are spelled differently per platform.
distinct_goldens="$(for g in tests/repl/*.golden; do cksum < "$g"; done \
                    | sort -u | wc -l | tr -d ' ')"
if [[ "$distinct_goldens" -lt 6 ]]; then
  echo "FAIL: only $distinct_goldens distinct goldens - the bank cannot"\
       "distinguish sessions from each other"
  failed=$((failed + 1))
fi

# Likewise for the cross-path values: agreements on one value would be
# satisfied by a REPL and a driver that both always print `0`.
distinct_results="$(sort -u "$work/results.txt" | wc -l | tr -d ' ')"
if [[ "$distinct_results" -lt 5 ]]; then
  echo "FAIL: the cross-path cases produced only $distinct_results distinct"\
       "values; the floor is 5 - they agree on too little to mean anything"
  failed=$((failed + 1))
fi

# The differ, self-checked on every run: a corrupted golden must compare
# unequal. This exercises `cmp` and `sed`, not the compiler, and fails
# only if the first golden has no "result". It stays because a differ
# that stopped differing would be invisible. The real negative test is
# the rebuild below.
first_golden="$(ls tests/repl/*.golden 2>/dev/null | head -1)"
if [[ -n "$first_golden" ]]; then
  sed 's/result/resutl/' "$first_golden" > "$work/corrupt.golden"
  if cmp -s "$first_golden" "$work/corrupt.golden"; then
    echo "FAIL: the negative test did not fail - the differ is blind"
    failed=$((failed + 1))
  fi
else
  echo "FAIL: no goldens exist for the negative test"
  failed=$((failed + 1))
fi

# And the cross-path comparison, negative-tested the same way, with a
# real build rather than a string trick: change what one program computes
# and it must stop agreeing with the REPL that ran the original.
if [[ ! -s "$work/results.txt" ]]; then
  echo "FAIL: no cross-path values were recorded - nothing was compared"
  failed=$((failed + 1))
else
  sed 's/12345/12346/' tests/repl/crosscheck/020-negative.ax > "$work/neg.ax"
  if ! "$work/axc" build --input "$work/neg.ax" --output "$work/neg.bin" \
        >/dev/null 2>&1; then
    echo "FAIL: the negative cross-path probe would not build"
    failed=$((failed + 1))
  else
    (cd "$work" && ./neg.bin >"$work/neg.out" 2>/dev/null)
    neg_val="$(sed -e 's/[[:space:]]*$//' "$work/neg.out" | tail -1)"
    run_repl "$repo_root/tests/repl/crosscheck/020-negative.repl" \
             "$work/neg.repl.out" "$work/neg.repl.err"
    ref_val="$(grep '^result ' "$work/neg.repl.out" | tail -1 | sed 's/^result //')"
    if [[ -z "$neg_val" || -z "$ref_val" || "$neg_val" == "$ref_val" ]]; then
      echo "FAIL: a program changed to compute something else still compared"\
           "equal to the REPL ('$neg_val' vs '$ref_val') - the cross-path"\
           "check is blind"
      failed=$((failed + 1))
    fi
  fi
fi

echo
if [[ "$bless" == 1 ]]; then
  echo "NOTE: goldens were re-blessed from the compiler under test. Layer 4"
  echo "ran anyway: every golden has a derived half (7 re-derived byte for"
  echo "byte, 050-commands anchored), so a re-blessed wrong ANSWER still"
  echo "fails. Re-blessed command WORDING inside a chatter window does not -"
  echo "read the diff of what you blessed."
fi
if [[ $failed -eq 0 ]]; then
  echo "check-repl-selfhost: $passed sessions passed ($byte_sessions byte, $shape_sessions shape), $cases cross-path cases, all checks passed"
else
  echo "check-repl-selfhost: $failed check(s) failed ($sessions sessions, $cases cross-path cases)"
  exit 1
fi
