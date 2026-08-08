#!/usr/bin/env bash
# stage1's native human diagnostic renderer, three-way and cross-checked.
#
# This gate is NOT a stage0 comparison, and that is a decision with a
# paper trail (docs/self-hosting.md): stage0's human renderer is the
# third-party `ariadne` crate, whose per-character ANSI stream is an
# internal of the compiler being retired, not a design of Axiom's. The
# human layout here is stage1's own, so the gate pins it the only way
# a native surface can be pinned - against checked-in goldens:
#
#     golden == stage1's `check` stderr, byte for byte, per case
#
# Golden vacuousness is the failure mode of a gate whose goldens were
# written by the code under test, and three independent checks refuse
# it:
#
#   * every fact on the case's AXDL golden - which stage0 itself
#     byte-equals, three-way, in check-diagnostics.sh - must appear in
#     the human golden: the code, the file:line:col of every primary
#     span, one heading per AXDL line, and a trailer whose count
#     equals the number of E lines;
#   * exit status must equal stage0's for every case (the AXDL gate
#     compares bytes, not statuses - which is how a warnings-only file
#     exited 1 under stage1 and 0 under stage0 for a month with the
#     gate green; probed and fixed 2026-08-07);
#   * the differ itself is negative-tested: a deliberately corrupted
#     golden must fail, or the sweep exits 1 without reporting a pass.
#
# Regenerate a golden deliberately, never casually:
#   AXIOM_BLESS=1 scripts/check-render-selfhost.sh          # all
#   AXIOM_BLESS=1 scripts/check-render-selfhost.sh 010      # one
#
# Usage:
#   scripts/check-render-selfhost.sh          # every case
#   scripts/check-render-selfhost.sh 010      # one case, by prefix

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "building the compiler first (no binary at $axiom)" >&2
  cargo build --release
fi

export AXIOM_STDLIB="$repo_root/stdlib"

filter="${1:-}"
bless="${AXIOM_BLESS:-0}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Same work-dir shape as check-diagnostics.sh, for the same reason:
# the cases run from $work so the filename each renderer prints is a
# bare `NAME.ax`, and the helper modules for multi-file cases are
# copied flat because a module name is its filename stem.
ln -s "$repo_root/stdlib" "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"
ln -s "$repo_root/tests" "$work/tests"
cp "$repo_root"/tests/diagnostics/mods/*.ax "$work/" 2>/dev/null || true

if ! "$axiom" build --input self_host/main.ax --output "$work/stage1" >"$work/build.log" 2>&1; then
  echo "FAIL: could not build stage1" >&2
  tail -20 "$work/build.log" >&2
  exit 1
fi

passed=0
failed=0
cases=0

for axdl in tests/diagnostics/*.axdl; do
  name="$(basename "$axdl" .axdl)"
  if [[ -n "$filter" && "$name" != "$filter"* ]]; then
    continue
  fi
  cases=$((cases + 1))
  golden="tests/diagnostics/$name.human"

  # A case that deliberately does not parse is spelled `.axbad` (see
  # check-diagnostics.sh); either way it lands in the work directory as
  # `.ax` so the report names the file the way every other case does.
  if [[ -f "tests/diagnostics/$name.ax" ]]; then
    cp "tests/diagnostics/$name.ax" "$work/$name.ax"
  else
    cp "tests/diagnostics/$name.axbad" "$work/$name.ax"
  fi

  (cd "$work" && ./stage1 check "$name.ax" 2>"$work/h.err" >"$work/h.out")
  s1=$?
  (cd "$work" && "$axiom" check "$name.ax" --diagnostic-format=ai >"$work/a.out" 2>/dev/null)
  s0=$?

  if [[ "$bless" == 1 ]]; then
    cp "$work/h.err" "$repo_root/$golden"
    echo "blessed $name"
    continue
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

  if [[ "$s1" != "$s0" ]]; then
    echo "FAIL $name: exit status diverged (stage0=$s0 stage1=$s1)"
    failed=$((failed + 1))
    continue
  fi

  # stdout is its own stream and its own contract: stage0's check
  # prints `OK` there whenever it does not fail - success and
  # warnings-only alike - and nothing on errors. A gate that watched
  # only stderr passed while stage1 printed no OK at all.
  if ! cmp -s "$work/a.out" "$work/h.out"; then
    echo "FAIL $name: stdout differs from stage0's"
    diff "$work/a.out" "$work/h.out" | head -4 | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi

  if ! cmp -s "$golden" "$work/h.err"; then
    echo "FAIL $name (stage1's rendering differs from the golden)"
    diff "$golden" "$work/h.err" | head -8 | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi

  # Cross-check against the AXDL golden, which stage0 itself equals:
  # the same diagnostics, independently rendered, must tell the same
  # story. One heading per AXDL line; every code and every primary
  # file:line:col present; the trailer counting exactly the E lines.
  ok=1
  axdl_lines="$(grep -cE '^[EWNH] ' "$axdl")"
  headings="$(grep -cE '^(error|warning)\[AX[0-9]{4}\]: ' "$golden")"
  if [[ "$axdl_lines" != "$headings" ]]; then
    echo "FAIL $name (AXDL has $axdl_lines diagnostics, human has $headings headings)"
    ok=0
  fi
  while IFS= read -r line; do
    code="$(printf '%s\n' "$line" | grep -oE 'AX[0-9]{4}' | head -1)"
    loc="$(printf '%s\n' "$line" | grep -oE '[^ ]+\.ax:[0-9]+:[0-9]+' | head -1 | sed 's/-.*//')"
    if [[ -n "$code" ]] && ! grep -qF "[$code]" "$golden"; then
      echo "FAIL $name (AXDL code $code missing from human golden)"
      ok=0
    fi
    if [[ -n "$loc" ]] && ! grep -qF -- "--> $loc" "$golden"; then
      echo "FAIL $name (AXDL location $loc missing from human golden)"
      ok=0
    fi

    # Layout, derived from the AXDL golden rather than trusted to the
    # human golden: the caret row's column and width are functions of
    # the primary span, so a golden blessed from a renderer that
    # misplaced or missized its carets cannot satisfy the AXDL facts
    # even though it byte-equals the renderer that made it. `L:C-C2`
    # is end-exclusive in characters; a bare `L:C` is a width-1 span;
    # a span crossing lines carries a second `L:`, which no current
    # case produces and the assertion skips.
    span="$(printf '%s\n' "$line" | grep -oE '\.ax:[0-9]+:[0-9]+(-[0-9]+)?( |$)' | head -1 | sed 's/^\.ax://; s/ $//')"
    if [[ -n "$span" ]]; then
      L="${span%%:*}"
      rest="${span#*:}"
      C="${rest%%-*}"
      if [[ "$rest" == *-* ]]; then C2="${rest#*-}"; else C2=$((C + 1)); fi
      run=$((C2 - C)); [[ "$run" -lt 1 ]] && run=1
      # An end-of-file diagnostic names a line PAST the last one - an
      # unclosed `(` runs out at the position after the final newline.
      # There is still a line to point at, and both renderers point at
      # the same one: the last, with the caret one past its final
      # character. Derived here from the fixture's own bytes, so it
      # stays a fact about the file rather than a fact about the
      # golden. stage0's report agrees (its AXDL says 2:1 for a
      # one-line file and its caret sits at 1:11).
      nlines="$(wc -l < "$work/$name.ax" | tr -d ' ')"
      if [[ "$L" -gt "$nlines" ]]; then
        L="$nlines"
        C=$(( $(awk -v n="$nlines" 'NR==n {print length($0)}' "$work/$name.ax") + 1 ))
        run=1
      fi
      if ! grep -qE "^ *${L} \| " "$golden"; then
        echo "FAIL $name (source line $L not in the snippet gutter)"
        ok=0
      fi
      pad="$(printf '%*s' $((C - 1)) '')"
      carets="$(printf '%*s' "$run" '' | tr ' ' '^')"
      if ! grep -qF -- "| ${pad}${carets}" "$golden"; then
        echo "FAIL $name (no caret row at col $C width $run for span $span)"
        ok=0
      fi
    fi

    # The related span's line must appear in the gutter too, with a
    # dash row of the span's width.
    rel="$(printf '%s\n' "$line" | grep -oE ' \^[0-9]+:[0-9]+(-[0-9]+)?:' | head -1 | sed 's/^ \^//; s/:$//')"
    if [[ -n "$rel" ]]; then
      RL="${rel%%:*}"
      rrest="${rel#*:}"
      RC="${rrest%%-*}"
      if [[ "$rrest" == *-* ]]; then RC2="${rrest#*-}"; else RC2=$((RC + 1)); fi
      rrun=$((RC2 - RC)); [[ "$rrun" -lt 1 ]] && rrun=1
      rpad="$(printf '%*s' $((RC - 1)) '')"
      dashes="$(printf '%*s' "$rrun" '' | tr ' ' '-')"
      if ! grep -qE "^ *${RL} \| " "$golden"; then
        echo "FAIL $name (related line $RL not in the snippet gutter)"
        ok=0
      fi
      if ! grep -qF -- "| ${rpad}${dashes}" "$golden"; then
        echo "FAIL $name (no dash row at col $RC width $rrun for related span)"
        ok=0
      fi
    fi
  done < <(grep -E '^[EWNH] ' "$axdl")
  errs="$(grep -cE '^E ' "$axdl")" || true
  if [[ "$errs" -gt 0 ]]; then
    plural="errors"
    [[ "$errs" == 1 ]] && plural="error"
    if ! grep -qF "compilation failed due to $errs previous $plural" "$golden"; then
      echo "FAIL $name (trailer does not count $errs errors)"
      ok=0
    fi
  else
    if grep -q "compilation failed" "$golden"; then
      echo "FAIL $name (warnings-only case has a failure trailer)"
      ok=0
    fi
  fi

  if [[ "$ok" == 1 ]]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
done

if [[ "$bless" == 1 ]]; then
  echo "blessed $cases cases"
  exit 0
fi

# A sweep that read fewer cases than exist is a sweep that can pass by
# not looking (the glob-rot lesson: a pattern that stops matching
# removes files while the section keeps reporting the silence it was
# looking for).
if [[ "$cases" -lt 38 ]]; then
  echo "FAIL: swept $cases cases; the floor is 38"
  failed=$((failed + 1))
fi

# The differ itself, negative-tested: corrupt a copy of the first
# golden and require the comparison to see it. A gate whose cmp was
# wired to the wrong file reports every case green forever.
first_golden="$(ls tests/diagnostics/*.human 2>/dev/null | head -1)"
if [[ -n "$first_golden" ]]; then
  sed 's/error/errro/' "$first_golden" > "$work/corrupt.human"
  if cmp -s "$first_golden" "$work/corrupt.human"; then
    echo "FAIL: the negative test did not fail - the differ is blind"
    failed=$((failed + 1))
  fi
else
  echo "FAIL: no goldens exist for the negative test"
  failed=$((failed + 1))
fi

echo "check-render-selfhost: $passed passed, $failed failed ($cases cases)"
[[ "$failed" == 0 ]]
