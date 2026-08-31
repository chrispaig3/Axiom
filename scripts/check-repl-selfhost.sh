#!/usr/bin/env bash
# The REPL, pinned without a second compiler.
#
# This gate used to be a differential: drive each session through the
# Rust compiler and the self-hosted one and require the same bytes, the
# same exit code, and empty stderr on both. That was right while the Rust
# compiler was the trusted reference. It is not available once the
# reference is deleted, and - the part worth being careful about - a
# differential does not FAIL when its reference disappears. Point
# `$axiom` at a self-hosted binary and every session becomes a compiler
# compared with itself: 12 sessions swept, zero differences, exit 0, and
# nothing tested. Agreement by mutual silence. So the stage0 arm is gone
# rather than repointed.
#
# What the gate pins now, in four layers:
#
#   1. SESSION INVARIANTS, no artifact involved. Every session must exit
#      0 with stderr EMPTY. This is the piped-surface contract the REPL
#      is written to (no prompt off-TTY, colors suppressed, results,
#      errors and command chatter all on stdout); an eval surface that
#      spills to stderr is passing vacuously somewhere else. Deliberately
#      NOT a checked-in per-session status manifest: all 12 sessions exit
#      0, so a manifest of them would be twelve copies of one value and
#      would be satisfied by a REPL that always exits 0 - the
#      all-identical shape this file refuses elsewhere.
#
#   2. BYTE GOLDENS for the deterministic surfaces (NNN-*.golden, 10 of
#      them): Int/Bool/Char/String result types and their printed
#      values, declaration OK lines, `type :` lines, semantic error
#      texts, the colon-command surface, comment and blank handling,
#      `:quit`'s no-farewell exit, a `fn` (and a signed, recursive
#      `fn`) spanning several physical lines (130-multiline, added
#      2026-08-31 with multi-line entries themselves), and an
#      IO-performing expression actually evaluating rather than
#      refusing at compile time with `\`__repl_result\` performs IO
#      and its declaration does not say so` (140-io, same date - see
#      `replCompileExpr` in self_host/repl.ax). Both are outside
#      verify-repl.py's model (`not modelled: unclosed form` /
#      `declaration head \`import\``, layer 4a below) and rest on this
#      layer's byte-pin plus the values being simple enough to check
#      by hand: 2+3=5, 5!=120, and `println "hi"` writes 3 bytes
#      (`hi\n`). (No Float: the bank has none, and this comment used
#      to claim one.)
#
#   3. MARKER SHAPES for the sessions whose output is not fixed text
#      (NNN-*-shape.markers, 4 of them): `:time` prints a duration,
#      `:llvm` prints this compiler's own IR, `:defs` renders one
#      indented line per declaration the session made, and redefining
#      `f` types (`type : Int`) and evaluates to the NEW body
#      (`result 1` then, after `(fn (f) 2)`, `result 2`) rather than
#      accumulating both and refusing every later expression with
#      `Error: duplicate definition` - the behavior through
#      2026-08-30, changed by `replDeclsSrcDropping` (self_host/repl.ax)
#      because the old one did not fail closed on just `f`: the
#      wrapper module recompiles the WHOLE session's declarations on
#      every expression, so one redefinition poisoned every name typed
#      afterward, recoverable only by `:reset` (which discards
#      everything else too). Substring markers only; nothing
#      else is compared - but the markers are HAND-MAINTAINED, and
#      AXIOM_BLESS does not write them, which is what makes layer 3 a
#      check rather than a record. 100-defs-shape leans on that: its
#      session declares alpha, beta and gamma (the last by signature
#      alone) and the markers require the rendered `  alpha`, `  beta`,
#      `  gamma` lines, which nothing but replCmdDefs prints - the
#      declaration echo is `OK: alpha defined`, a different string.
#
#   4. TWO DERIVED HALVES A RE-BLESS CANNOT SATISFY. Layer 2 is a
#      record of what the compiler printed. It does not know what the
#      answer should be: regenerate it from a compiler that evaluates
#      `(+ 1 2)` as 4 and `result 4` is the new golden and the gate is
#      green. Both halves below are computed from artifacts the bless
#      does not write.
#
#      4a. tests/repl/verify-repl.py re-derives the transcripts in
#          PYTHON from each session file's own bytes - tokenizing and
#          evaluating the Int/Bool/Char/String subset the sessions use,
#          and predicting the `OK: x defined`, `type : T`, `result V`,
#          `Type error: undefined variable` and `Goodbye!` lines - then
#          compares that prediction to the golden. All 8 goldens, 76
#          transcript lines, re-derived with no compiler in the loop.
#          7 match BYTE FOR BYTE. 050-commands cannot: half of it is
#          `:help`'s banner and the REPL's own error wording, text with
#          no semantics to re-derive and which the model must not
#          transcribe. It is ANCHORED instead - every derived line
#          present, in order and consecutive where the model says
#          consecutive, each chatter window at least as long as the
#          number of commands that fed it, and no `result`/`type :`/
#          `OK:`/`Type error:`/`Goodbye!` line allowed to hide inside a
#          window. So `:reset` must really drop the declarations before
#          `(f 1)` is an unbound name, and `:type (+ 1 2)` must really
#          answer Int. It was skipped by name until 2026-08-08, and
#          that skip is what drill 3 below walked through. The floors
#          inside the verifier (8 sessions, 7 of them byte-exact, 70
#          lines, 5 anchored) are what stop the model from going blind
#          again and reporting success.
#
#      4b. tests/repl/crosscheck/ pairs a REPL session with an ORDINARY
#          PROGRAM computing the same value, and requires the REPL's
#          `result` to equal what the compiled program prints. Two
#          independent paths through one binary: the REPL types the line
#          against accumulated declarations, picks a printer from the
#          RENDERED type string, builds stage0's wrapper template around
#          it and trims the child's stdout, while the program goes
#          through the ordinary driver. A wrapper that picked the Int
#          printer for a Bool, a dropped declaration, a trim that ate a
#          character, or a silent child falling back to the exit code
#          all diverge here - and there is no golden to re-bless,
#          because neither side of the comparison is checked in as a
#          value. 8 cases: nested calls into two definitions, negative
#          and zero Ints, both Bools, a String, a Char, and a recursive
#          `fact 10`. Two honest limits. 030-zero answers `0` whether
#          the wrapper printed it or the rc-0 fallback did, so it is the
#          one case that cannot fail for the intended reason; the
#          distinct-value floor is what stops that mattering. And the
#          fallback's RENDERING is never exercised, because all 8
#          wrappers print - so repl.ax:376 formatting an exit code
#          through fmtIntStr, which answers "1" for anything above 3, is
#          out of this layer's reach and out of layer 4a's too.
#
# The floors and the anti-vacuousness checks are at the bottom. One of
# the two negative tests down there is real - it rebuilds a cross-check
# program to compute something else and requires the agreement to break.
# The other only proves `cmp` and `sed` still work; it is kept because
# it costs nothing, and it is not evidence about the compiler.
#
# Provenance of tests/repl/crosscheck/, materialized while both
# compilers still existed: on 2026-08-08 (darwin-aarch64) each of the 8
# cases was measured FOUR ways - Rust REPL, Rust driver, self-hosted
# REPL, self-hosted driver - and all four agreed on all 8 (49, -12345,
# 0, true, false, `cross path`, Z, 3628800), stderr empty and exit 0
# throughout. That is the last moment two compilers existed to compare;
# the cases carry no blessed value, so nothing here needs re-checking.
# verify-repl.py needs no such note - it agrees with goldens that
# predate this conversion, and it consults no compiler at all.
#
# Ablation drills, run at introduction rather than assumed, each a
# single edit in a `cp -a` copy so the shared self_host/ was never
# touched. Honest run for reference: 12 sessions (8 byte, 4 shape),
# verify-repl 8 sessions / 7 byte-exact / 76 lines / 5 anchored / 0
# mismatched, 8/8 cross-path, exit 0. 1m51s on an idle machine, 3m05s
# with other gates running; ~1m40s of that is building the compiler
# under test.
#
#   1. The wrapper's Int printer emits `(+ 1 (__repl_result 0))`, so
#      every Int-typed REPL result is off by one and nothing else
#      changes.
#        * goldens intact -> 13 checks fail: 7 of 8 byte sessions, the
#          `result 3` marker of 110-time-shape, 4 of 8 cross-path
#          cases, and the distinct-value floor
#        * RE-BLESS every golden from that build, then re-run -> all 8
#          byte sessions go green and the gate still exits 1:
#          verify-repl.py reports every modelled session mismatched, 4
#          cross-path cases disagree, and the marker (which a bless does
#          not write) is still missing
#        * restore -> 12/12 sessions, 8/8 cases, exit 0
#
#   2. replCmdDefs' per-name `(replOut ...)` replaced by `0`, so `:defs`
#      prints its header and no definitions. This drill was run against
#      the gate as it stood on 2026-08-08 and the gate PASSED it: `ok
#      100-defs-shape  2 required marker(s) present`, exit 0, goldens
#      untouched, a user-visible command gutted. Those two markers were
#      the static header and `OK: f defined` - the declaration echo,
#      printed before `:defs` runs. With the session and markers of fix
#      2 above: three FAILs (`output lacks '  alpha'`, `'  beta'`,
#      `'  gamma'`), exit 1, no re-bless needed to catch it.
#
#   3. THE LAUNDERING DRILL. `(set declsSrc "")` in the `:reset` arm
#      replaced by `0`, so the REPL announces a reset and keeps every
#      declaration. Exactly one golden moves under a bless: 050-commands,
#      858B -> 843B, its line 25 ``Type error: undefined variable `f` ``
#      becoming `type : Int` / `result 1`. The gate as it stood passed
#      BOTH halves of this - the bless run exited 0, and so did the
#      clean re-run against the laundered golden (`ok 050-commands 843B
#      byte-identical to the golden`, "all checks passed") - because
#      050-commands was the one golden layer 4a skipped by name. Now:
#      the bless run exits 1 and the clean re-run exits 1, with layer 4a
#      naming all four problems -
#          unpredicted output inside the :reset announcement: 'type : Int'
#          unpredicted output inside the :reset announcement: 'result 1'
#          unpredicted output inside the :reset announcement: 'Goodbye!'
#          derived line(s) 'Type error: undefined variable `f`' never
#            appear after the :reset announcement
#      while layer 2 still reports the laundered golden byte-identical,
#      which is exactly the point: layer 2 cannot see this and never
#      could.
#
# AXIOM_BLESS=1 regenerates the goldens from the compiler under test and
# then RUNS LAYER 4 ANYWAY. Every golden in the bank now has a derived
# half - 7 re-derived byte for byte, the eighth anchored - so a bless
# cannot launder a wrong ANSWER into a green gate; drill 3 is that claim
# tested rather than asserted. What a bless can still change unchallenged
# is the WORDING inside a chatter window: `:help`'s banner, the
# unknown-command and usage errors, the reset announcement. Their
# presence and length are checked, their prose is not, and re-deriving a
# compiler's prose from the compiler's own source would check nothing.
#
# THAT HAZARD IS CLOSED, and this paragraph replaces it rather than
# deleting it, because the stale version very nearly cost the battery
# two gates' worth of parallelism. It read: repl.ax builds its scratch
# path as `/tmp/axiom-repl-<fmtIntStr pid>`, `fmtIntStr` renders only
# 0..3 and answers "1" above that, so every REPL on the machine writes
# /tmp/axiom-repl-1.{ll,o,out} and two at once corrupt each other -
# "run this gate serially with anything else that starts a REPL until
# that is fixed".
#
# It was fixed twice, and repl.ax's own comment at `replEval` records
# both: DISTINCTNESS 2026-08-08, moving the pid through `diag$decStr`,
# which renders any non-negative integer; and PREDICTABILITY
# 2026-08-23, putting all four scratch files inside a private
# `<tmp>/axiom-repl-<pid>.d` at mode 0700, created with an exclusive
# `sysMkdir`. MEASURED 2026-08-31, when check-repl-tui.sh arrived and
# started REPLs of its own: six `axiom repl` processes launched
# together each answered its own expression correctly - 101, 202, 303,
# 404, 505, 606 - and /tmp held no `axiom-repl*` entry before or after.
# Neither REPL gate needs to be serial, and neither is.
#
# The general point is one this repository keeps relearning: a hazard
# recorded in a comment is a claim with no expiry, and the next reader
# acts on it. This one was about to add two entries to run-gates.sh's
# serial list.
#
# Usage:  scripts/check-repl-selfhost.sh
#         AXIOM_BLESS=1 scripts/check-repl-selfhost.sh
#         scripts/check-repl-selfhost.sh 010     # partial, NOT a gate result

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

filter="${1:-}"
bless="${AXIOM_BLESS:-0}"

# The compiler under test is the one built FROM SOURCE by `$axiom`, not
# `$axiom` itself: this gate exists to test self_host/repl.ax, and
# `$axiom` may be an older seed-descended binary that predates the change
# being tested.
gate_build_axc axc

# Both the sessions and the cross-check programs run from the work dir:
# the REPL writes scratch .ll/.o/executables beside the CWD and resolves
# relative imports from it, and HOME/XDG are redirected so a history file
# never touches the user's real one.
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
  # The value the REPL announced. `result ` lines only - a session that
  # errored has none, and the emptiness check below is what catches it.
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

# Likewise for the cross-path values: eight agreements on one value would
# be satisfied by a REPL and a driver that both always print `0`.
distinct_results="$(sort -u "$work/results.txt" | wc -l | tr -d ' ')"
if [[ "$distinct_results" -lt 5 ]]; then
  echo "FAIL: the cross-path cases produced only $distinct_results distinct"\
       "values; the floor is 5 - they agree on too little to mean anything"
  failed=$((failed + 1))
fi

# The differ, self-checked on every run: a corrupted golden must compare
# unequal. This exercises `cmp` and `sed`, NOT the compiler - it cannot
# fail unless the first golden contains no "result" - and it is kept only
# because a differ that silently stopped differing would be invisible.
# The real negative test is the rebuild below it.
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
