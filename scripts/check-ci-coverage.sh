#!/usr/bin/env bash
# EVERY GATE ON DISK IS RUN BY CI, AND EVERY GATE CI NAMES EXISTS.
#
# The local battery cannot drift: `run-gates.sh` globs
# `scripts/check-*.sh`, so a gate is in it the moment it is written.
# `.github/workflows/ci.yml` names its gates ONE AT A TIME, in a `run:`
# line per step, which is the right thing for a file that also decides
# WHICH JOB and WHICH PLATFORM each gate belongs to - and it means the
# list is maintained by hand, so it drifts silently in both directions.
#
# BOTH DIRECTIONS HAVE ALREADY HAPPENED HERE, and this gate exists
# because each was invisible until somebody counted.
#
#   a gate on disk that no job runs.  Measured 2026-09-04: SEVEN of the
#     78 gate scripts - dead-code, mir-projection, mir-roundtrip,
#     repl-highlight, repl-history, repl-tui, replcomp. All seven pass;
#     that is the point. A gate nobody runs is indistinguishable from a
#     gate that passes, and this file's own comments say so twice, in
#     the words of the people who found it the last two times: "a gate
#     no job runs is a script", and "a tool with no CI gate is silently
#     broken, as `fmt` was".
#
#   a step naming a gate that is not there.  `720a0d5` deleted
#     `check-game-of-life.sh` and the sample it ran, and left the step
#     that invoked it, so every run of that job failed on a missing
#     file. The comment recording that is still in `ci.yml` above the
#     step which replaced it.
#
# THE TRAP THIS GATE HAD TO AVOID, and it is the reason the extractor
# reads `run:` lines rather than the file. `ci.yml` is 1,300 lines and
# most of it is prose: gates are named in comments constantly, to
# explain what a neighbouring step does or why a step was replaced.
# Grepping the whole file for `scripts/check-*.sh` answers 72 where the
# `run:` lines answer 71 - and the one it invents is `check-game-of-life.sh`,
# the deleted script, named only in the comment that records its
# deletion. A whole-file grep would therefore have reported the
# game-of-life step as covered on the day it was broken, and would
# report any future gate as covered the moment somebody merely wrote
# its name in a sentence. Ablation C below is that exact scenario, and
# it is required to go red.
#
# WHAT IS ALLOWED TO BE UNCOVERED is a table in this file, not a
# silence, and each entry carries the reason it is printed with. That
# is the shape `run-gates.sh` already uses for the one gate a bare
# invocation cannot run: listed, excluded, and PRINTED, because "not
# run and silent would be the worse defect of the two".
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || { echo "FAIL: no repository root at $repo_root" >&2; exit 1; }

# This gate reads two lists of file names and runs no Axiom program, so
# it does not call `gate_init`: that helper resolves or BOOTSTRAPS a
# compiler, which on a clean checkout is a hundred seconds spent to
# answer a question about text. `check-tree-sitter.sh` and
# `check-memory-baseline.sh` are the precedent for a gate that finds
# `$repo_root` itself for the same reason.

ci_yml="$repo_root/.github/workflows/ci.yml"
[[ -f "$ci_yml" ]] || { echo "FAIL: $ci_yml is missing"; exit 1; }

# Overridable so the ablations below can point the gate at a doctored
# copy without editing the workflow the repository ships.
ci_yml="${CI_YML_OVERRIDE:-$ci_yml}"

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# --------------------------------------------------------------------
# The two lists, and the one function that compares them.
#
# The comparison is a FUNCTION taking the workflow file to read,
# because the ablations at the bottom have to run the real comparison
# against a doctored copy. A gate whose ablation re-implements the
# check proves only that the ablation works.
#
# A MENTION IS NOT AN EXECUTION, and the first version of this gate
# could not tell them apart. It stripped comments and grepped the rest
# of the file, so a step's `name:`, an `echo` of the path, a step behind
# `if: false`, a job with `continue-on-error: true` and a trailing
# `|| true` all counted as the gate being run. An audit on 2026-09-26
# turned the real `check-scope-equiv.sh` step into an `echo` of itself
# in a copy of `ci.yml` and this gate still reported every script run,
# with its own three ablations green. Ablation I below is that copy.
#
# So the workflow is now READ, not grepped: `scripts/lib/ci-steps.py`
# walks jobs and steps and counts an invocation only when it is a whole
# command line of a narrow form in a step's own `run:`, in a
# straight-line script, under bash with `-e`, in a step and job that a
# literally-false `if` does not disable and a `continue-on-error` does
# not hide. Its header states the rule in full. A condition that is not
# literally false - a platform, a schedule, a changed-path output - is
# PRINTED with the invocation, because the workflow is built out of
# those and the gate's job is to show them, not overrule them.
# --------------------------------------------------------------------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

disk="$work/disk"
( cd "$repo_root/scripts" && ls check-*.sh 2>/dev/null | LC_ALL=C sort ) > "$disk"

# Every RUN/REFUSED record for one workflow file. A workflow the reader
# cannot parse is a failure of this gate, not an empty answer: an empty
# answer would be reported as "no step runs anything", which is true of
# nothing and would read as a doctored file rather than a broken reader.
steps_of() {
  local out
  if ! out="$(python3 "$repo_root/scripts/lib/ci-steps.py" "$1")"; then
    echo "READER-FAILED"
    return 0
  fi
  printf '%s\n' "$out"
}

# Names a workflow file actually RUNS.
names_run_by() {
  steps_of "$1" | awk -F'\t' '$1 == "RUN" { print $2 }' | LC_ALL=C sort -u
}

# Every complaint about one workflow file, one per line, empty when
# there is nothing to say. Both the real run and every ablation call
# this and nothing else.
coverage_complaints() {
  local yml="$1" named="$work/named.$$" records="$work/records.$$" g why
  steps_of "$yml" > "$records"
  if grep -qx 'READER-FAILED' "$records"; then
    echo "scripts/lib/ci-steps.py could not read $(basename "$yml")"
    rm -f "$records"
    return 0
  fi
  awk -F'\t' '$1 == "RUN" { print $2 }' "$records" | LC_ALL=C sort -u > "$named"

  while IFS= read -r g; do
    [[ -z "$g" ]] && continue
    grep -qx "$g" "$named" && continue
    is_excluded "$g" && continue
    why="$(awk -F'\t' -v g="$g" '$1 == "REFUSED" && $2 == g { print $5; exit }' "$records")"
    echo "scripts/$g is on disk and no CI step runs it${why:+ (named in a step, but $why)}"
  done < "$disk"

  while IFS= read -r g; do
    [[ -z "$g" ]] && continue
    [[ -f "$repo_root/scripts/$g" ]] \
      || echo "ci.yml runs scripts/$g, which is not in the tree"
  done < "$named"

  rm -f "$named" "$records"
}

# --------------------------------------------------------------------
# Gates a CI job cannot run, each with the reason it is reported with.
#
# THIS TABLE IS EMPTY, AND IT IS WRITTEN FOR THE EMPTY SET ON THE DAY
# IT IS WRITTEN. That is a rule this repository learned the hard way:
# `compat/UNCOVERED` reaching zero - the state its whole work item was
# aiming at - made a `grep -v` match nothing, which exits 1, which
# under `set -e` killed the gate after its first heading and reported
# "1 failed in 2 seconds". A check whose success condition is an empty
# set has to survive the empty set, so the loop below is guarded on the
# count rather than falling through a `for` that never runs.
#
# It is empty because nothing needs to be in it. The one gate that
# looked like a candidate is `check-windows-hello.sh`, which
# `run-gates.sh` DOES exclude - a bare invocation of it is a usage
# error, since it is two halves on two machines. But CI is exactly the
# place that can run both halves, and it does: `--emit windows-hello`
# on the emitting host and `--run windows-hello` on the Windows runner.
# The two files disagree about that gate for a good reason, and this
# comment is here so the next reader does not "fix" the disagreement.
# --------------------------------------------------------------------
declare -a EXCLUDED_NAME=()
declare -a EXCLUDED_WHY=()

is_excluded() {
  local n="$1" i
  (( ${#EXCLUDED_NAME[@]} == 0 )) && return 1
  for i in "${!EXCLUDED_NAME[@]}"; do
    [[ "${EXCLUDED_NAME[$i]}" == "$n" ]] && return 0
  done
  return 1
}

# --------------------------------------------------------------------
# 1 and 2. The tree and the workflow agree, in both directions.
# --------------------------------------------------------------------
echo "== every gate on disk is run by a step, and every step's gate exists =="
complaints="$(coverage_complaints "$ci_yml")"
if [[ -n "$complaints" ]]; then
  while IFS= read -r line; do bad "$line"; done <<< "$complaints"
else
  ok "$(wc -l < "$disk" | tr -d ' ') gate scripts on disk, $(names_run_by "$ci_yml" | wc -l | tr -d ' ') invoked by a step, and the two sets agree"
fi

# THE CONDITIONS, SHOWN. A gate whose every invocation sits under an
# `if:` runs only when that condition holds; that is often the design
# (the nightly, a docs-only change, a changed path), and it is printed
# here so that it is a decision somebody can see rather than a fact
# nobody looked for. A mention the reader refused is printed too, with
# its reason, even when the gate is invoked properly elsewhere.
steps_of "$ci_yml" > "$work/real.records"
awk -F'\t' '$1 == "RUN" && $5 == "-" { print $2 }' "$work/real.records" | LC_ALL=C sort -u > "$work/uncond"
cond_only="$(awk -F'\t' '$1 == "RUN" && $5 != "-" { print $2 }' "$work/real.records" \
             | LC_ALL=C sort -u | LC_ALL=C comm -23 - "$work/uncond")"
if [[ -n "$cond_only" ]]; then
  echo "     invoked only under a condition, and which:"
  while IFS= read -r g; do
    awk -F'\t' -v g="$g" '$1 == "RUN" && $2 == g { printf "       %s  [%s] if %s\n", g, $3, $5 }' \
      "$work/real.records"
  done <<< "$cond_only"
fi
refused_real="$(awk -F'\t' '$1 == "REFUSED" { printf "       %s  [%s / %s] %s\n", $2, $3, $4, $5 }' "$work/real.records")"
if [[ -n "$refused_real" ]]; then
  echo "     named in a step but not counted as run there:"
  printf '%s\n' "$refused_real"
fi

# --------------------------------------------------------------------
# 3. The exclusion table describes reality: every excluded gate exists,
#    and no gate is excluded that CI actually runs. Without this an
#    entry could outlive its reason and silently exempt a gate somebody
#    later wired up - or, worse, one that had been deleted.
# --------------------------------------------------------------------
echo "== the exclusion table is current =="
stale=0
if (( ${#EXCLUDED_NAME[@]} == 0 )); then
  ok "the exclusion table is empty: every gate script in the tree is run by CI"
else
  named_now="$work/named.now"
  names_run_by "$ci_yml" > "$named_now"
  for i in "${!EXCLUDED_NAME[@]}"; do
    n="${EXCLUDED_NAME[$i]}"
    if [[ ! -f "$repo_root/scripts/$n" ]]; then
      bad "the exclusion table names scripts/$n, which is not in the tree"
      stale=$((stale + 1))
    elif grep -qx "$n" "$named_now"; then
      bad "scripts/$n is excluded as unrunnable, but a CI step runs it"
      stale=$((stale + 1))
    else
      echo "     not run by a bare CI step, and why:"
      echo "       $n"
      echo "${EXCLUDED_WHY[$i]}" | fold -s -w 62 | sed 's/^/         /'
    fi
  done
  (( stale == 0 )) && ok "${#EXCLUDED_NAME[@]} excluded gate(s), each present and each genuinely unrun"
fi

# --------------------------------------------------------------------
# THE ABLATIONS. Three, all required to go red, and they run on every
# invocation rather than living in a comment - this gate's whole
# subject is a check that was missing, so a check that cannot fail
# would be the same defect one level up.
#
# C is the one that matters and the reason the extractor strips
# comments. `ci.yml` is thirteen hundred lines and most of it is prose;
# gates are named in comments constantly, to explain a neighbouring
# step or to record a step that was replaced. A whole-file grep answers
# 72 where the `run:` lines answer 71, and the extra is
# `check-game-of-life.sh` - deleted in 720a0d5, named today only by the
# comment recording its deletion. A gate built on a whole-file grep
# would have called that step covered on the day it was broken.
# --------------------------------------------------------------------
echo "== the ablations: each doctored workflow must be refused =="

victim="$(head -1 "$disk")"

ablate() {
  local what="$1" file="$2" want="$3" got
  got="$(coverage_complaints "$file")"
  if [[ "$got" == *"$want"* ]]; then
    ok "ablation: $what -> refused"
  else
    bad "ablation: $what was NOT refused (this gate cannot fail that way)"
    echo "     wanted a complaint containing: $want"
    echo "     got: ${got:-<silence>}"
  fi
}

# A. a gate on disk that no step runs.
grep -v "scripts/$victim" "$ci_yml" > "$work/a.yml"
ablate "a step deleted for scripts/$victim" "$work/a.yml" \
       "scripts/$victim is on disk and no CI step runs it"

# B. a step naming a gate that is not there - the game-of-life failure.
{ cat "$ci_yml"; printf '      - name: ablation\n        run: ./scripts/check-not-a-real-gate.sh\n'; } > "$work/b.yml"
ablate "a step running a gate that does not exist" "$work/b.yml" \
       "ci.yml runs scripts/check-not-a-real-gate.sh, which is not in the tree"

# C. the uncovered gate is named, but only inside a comment.
{ grep -v "scripts/$victim" "$ci_yml"
  printf '      # see scripts/%s for the same idea\n' "$victim"; } > "$work/c.yml"
ablate "scripts/$victim named only in a comment" "$work/c.yml" \
       "scripts/$victim is on disk and no CI step runs it"

# THE MENTIONS THAT ARE NOT EXECUTIONS. Each of D-J keeps the gate's
# path in the workflow, outside a comment, in a place a grep would count,
# and each must still be refused. They need a gate that ONE step runs, on
# one `run: ./scripts/<gate>` line, so the doctoring is a single-line
# edit whose effect is unambiguous; the first such gate in file order is
# chosen rather than a name written here, so a renamed gate cannot turn
# them into edits of nothing - and the edit's match count is asserted.
single="$(awk -F'\t' '$1 == "RUN" { n[$2]++ } END { for (g in n) if (n[g] == 1) print g }' \
            "$work/real.records" | LC_ALL=C sort)"
lone=""
while IFS= read -r g; do
  [[ -z "$g" ]] && continue
  if [[ "$(grep -cE "^ +run: \./scripts/$g\$" "$ci_yml")" == 1 ]]; then lone="$g"; break; fi
done <<< "$single"
if [[ -z "$lone" ]]; then
  bad "no gate is run by exactly one single-line step, so ablations D-J have nothing to doctor"
else
  lone_at="$(grep -nE "^ +run: \./scripts/$lone\$" "$ci_yml" | cut -d: -f1)"
  lone_ind="$(sed -n "${lone_at}p" "$ci_yml" | sed 's/run:.*//')"
  want="scripts/$lone is on disk and no CI step runs it"
  doctor() {  # <out> <replacement lines for the run line, \n-separated>
    # Through the environment, not `-v`: BSD awk refuses a newline in a
    # `-v` assignment, and three of the replacements are two lines.
    REP="$2" awk -v at="$lone_at" 'NR == at { print ENVIRON["REP"]; next } { print }' "$ci_yml" > "$1"
    cmp -s "$ci_yml" "$1" && bad "doctoring line $lone_at changed nothing"
  }

  # D. the step echoes the path instead of running it.
  doctor "$work/d.yml" "${lone_ind}run: echo ./scripts/$lone"
  ablate "scripts/$lone echoed rather than run" "$work/d.yml" "$want (named in a step, but \`echo ./scripts/$lone\` is a mention"

  # E. the step's NAME carries the path; its run does something else.
  doctor "$work/e.yml" "${lone_ind}name: Run ./scripts/$lone
${lone_ind}run: 'true'"
  ablate "scripts/$lone only in a step name" "$work/e.yml" "$want"

  # F. the step is disabled by a literally false condition.
  doctor "$work/f.yml" "${lone_ind}if: false
${lone_ind}run: ./scripts/$lone"
  ablate "scripts/$lone behind \`if: false\`" "$work/f.yml" "$want (named in a step, but the step's \`if\` is literally false)"

  # G. the only invocation moves to a job that can never start.
  { grep -vE "^ +run: \./scripts/$lone\$" "$ci_yml"
    printf '  ablation-disabled:\n    if: ${{ false }}\n    runs-on: ubuntu-latest\n'
    printf '    steps:\n      - run: ./scripts/%s\n' "$lone"
    printf '  ablation-downstream:\n    needs: ablation-disabled\n    runs-on: ubuntu-latest\n'
    printf '    steps:\n      - run: ./scripts/%s\n' "$lone"; } > "$work/g.yml"
  ablate "scripts/$lone in a disabled job and one that needs it" "$work/g.yml" "$want (named in a step, but its job can never start"

  # H. the step's failure is hidden by continue-on-error.
  doctor "$work/h.yml" "${lone_ind}continue-on-error: true
${lone_ind}run: ./scripts/$lone"
  ablate "scripts/$lone under \`continue-on-error: true\`" "$work/h.yml" "$want (named in a step, but the step has \`continue-on-error\`"

  # I. the status is thrown away on the line itself.
  doctor "$work/i.yml" "${lone_ind}run: ./scripts/$lone || true"
  ablate "scripts/$lone followed by \`|| true\`" "$work/i.yml" "$want (named in a step, but \`./scripts/$lone || true\` is a mention"

  # J. the line is unreachable inside the step's own script.
  doctor "$work/j.yml" "${lone_ind}run: |
${lone_ind}  if false; then
${lone_ind}    ./scripts/$lone
${lone_ind}  fi"
  ablate "scripts/$lone inside \`if false\` in the script" "$work/j.yml" "$want (named in a step, but the step's script is not straight-line"
fi

# THE AUDIT'S OWN COPY, reproduced: the real `check-scope-equiv.sh`
# invocation turned into an echo of itself. Named here, not chosen,
# because it is a specific historical failure; if the step moves or
# the gate is renamed the seam's count says so rather than going quiet.
se_n="$(grep -cE '^ +run: \./scripts/check-scope-equiv\.sh$' "$ci_yml" || true)"
if [[ "$se_n" != 1 ]]; then
  bad "ablation I's seam, a single \`run: ./scripts/check-scope-equiv.sh\` line, matches $se_n lines"
else
  sed -E 's|^( +run: )\./scripts/check-scope-equiv\.sh$|\1echo ./scripts/check-scope-equiv.sh|' \
    "$ci_yml" > "$work/audit.yml"
  ablate "the audit's copy: check-scope-equiv.sh echoed" "$work/audit.yml" \
         "scripts/check-scope-equiv.sh is on disk and no CI step runs it"
fi

# --------------------------------------------------------------------
echo
if (( failed )); then
  echo "check-ci-coverage: $checks checks, $failed FAILED"
  exit 1
fi
echo "check-ci-coverage: $checks checks - every gate script in the tree is"
echo "                   run by a CI step or excluded by name with a reason,"
echo "                   every gate a step names is present, the exclusion"
echo "                   table still describes the tree, and eleven doctored"
echo "                   workflows - three that drop a step and eight that keep"
echo "                   a gate's path where a grep would count it - are each"
echo "                   refused"
