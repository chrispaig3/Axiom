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
# `run:` in YAML can open a block scalar (`run: |`) whose body is many
# lines, and a gate invoked inside one of those bodies is genuinely
# run. So the extractor takes every line, and the whole discrimination
# is that COMMENTS ARE STRIPPED FIRST, on the `#`-at-start-of-token
# rule YAML uses.
# --------------------------------------------------------------------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

disk="$work/disk"
( cd "$repo_root/scripts" && ls check-*.sh 2>/dev/null | LC_ALL=C sort ) > "$disk"

# Names a workflow file actually RUNS, comments removed.
names_run_by() {
  LC_ALL=C sed 's/[[:space:]]#.*$//; s/^[[:space:]]*#.*$//' "$1" \
    | grep -oE 'scripts/check-[a-z0-9-]+\.sh' \
    | sed 's|^scripts/||' | LC_ALL=C sort -u
}

# Every complaint about one workflow file, one per line, empty when
# there is nothing to say. Both the real run and every ablation call
# this and nothing else.
coverage_complaints() {
  local yml="$1" named="$work/named.$$" g
  names_run_by "$yml" > "$named"

  while IFS= read -r g; do
    [[ -z "$g" ]] && continue
    grep -qx "$g" "$named" && continue
    is_excluded "$g" && continue
    echo "scripts/$g is on disk and no CI step runs it"
  done < "$disk"

  while IFS= read -r g; do
    [[ -z "$g" ]] && continue
    [[ -f "$repo_root/scripts/$g" ]] \
      || echo "ci.yml runs scripts/$g, which is not in the tree"
  done < "$named"

  rm -f "$named"
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
  ok "$(wc -l < "$disk" | tr -d ' ') gate scripts on disk, $(names_run_by "$ci_yml" | wc -l | tr -d ' ') named by a step, and the two sets agree"
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

# --------------------------------------------------------------------
echo
if (( failed )); then
  echo "check-ci-coverage: $checks checks, $failed FAILED"
  exit 1
fi
echo "check-ci-coverage: $checks checks - every gate script in the tree is"
echo "                   run by a CI step or excluded by name with a reason,"
echo "                   every gate a step names is present, the exclusion"
echo "                   table still describes the tree, and three doctored"
echo "                   workflows are each refused"
