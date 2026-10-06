#!/usr/bin/env bash
# Every gate on disk is run by CI, and every gate CI names exists.
#
# `run-gates.sh` globs `scripts/check-*.sh`, so the local battery cannot
# drift. `.github/workflows/ci.yml` names its gates one `run:` line at a
# time, because it also decides which job and platform runs each one.
# That list is kept by hand, so it can drift both ways:
#
#   - a gate on disk that no job runs. It never fails, so it looks
#     exactly like a gate that passes.
#   - a step naming a gate that is not there, so that job fails on a
#     missing file.
#
# Coverage is read from the workflow step by step, never grepped.
# `ci.yml` names gates in its comments all the time, and a whole-file
# grep would call a gate covered as soon as someone wrote its name in a
# sentence. Ablation C below is that case and must go red.
#
# A gate allowed to go uncovered is listed in a table in this file with
# the reason it is printed with, as `run-gates.sh` does with NOTRUN_RE.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || { echo "FAIL: no repository root at $repo_root" >&2; exit 1; }

# This gate compares lists of file names and runs no Axiom program, so
# it finds `$repo_root` itself instead of calling `gate_init`, which
# bootstraps a compiler on a clean checkout. `check-tree-sitter.sh` and
# `check-examples.sh` do the same.

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
# The comparison is a function taking the workflow file to read, so the
# ablations at the bottom run the real comparison against a doctored
# copy. An ablation that re-implemented the check would prove only
# itself.
#
# A mention is not an execution. A step's `name:`, an `echo` of the
# path, `if: false`, `continue-on-error: true` and a trailing `|| true`
# each put a gate's path in a step without its failure failing the job.
# `scripts/lib/ci-steps.py` walks jobs and steps and counts an
# invocation only when it is a whole command line of a narrow form in a
# step's own `run:`: a straight-line script, under bash with `-e`, in a
# step and job that no literally false `if` disables and no
# `continue-on-error` hides. Its header states the rule in full. Any
# other condition (a platform, a schedule, a changed-path output) is
# printed with the invocation, not overruled.
# --------------------------------------------------------------------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

disk="$work/disk"
( cd "$repo_root/scripts" && ls check-*.sh 2>/dev/null | LC_ALL=C sort ) > "$disk"

# Every RUN/REFUSED record for one workflow file. A workflow the reader
# cannot parse answers READER-FAILED, so a broken reader is reported as
# one and not as a workflow in which no step runs anything.
steps_of() {
  local out
  if ! out="$(python3 "$repo_root/scripts/lib/ci-steps.py" "$1")"; then
    echo "READER-FAILED"
    return 0
  fi
  printf '%s\n' "$out"
}

# Names a workflow file actually runs.
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
# The table is empty, and every use of it is guarded on the count
# rather than left to a loop that never runs: a check whose success
# condition is an empty set has to survive the empty set. A `grep -v`
# that matches nothing exits 1, for example, which `set -e` treats as a
# failure.
#
# `check-windows-hello.sh` is excluded by `run-gates.sh` but not here.
# A bare invocation of it is a usage error, because it has two halves on
# two machines. CI runs both: `--emit windows-hello` on the emitting
# host and `--run windows-hello` on the Windows runner.
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

# The conditions, shown. A gate whose every invocation sits under an
# `if:` runs only when that holds. That is often the design (the
# nightly, a docs-only change, a changed path), so it is printed, not
# failed. A mention the reader refused is printed too, with its reason,
# even when the gate is run properly elsewhere.
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
# 3. The exclusion table is current: every excluded gate exists, and CI
#    runs none of them. Otherwise an entry could outlive its reason and
#    exempt a gate that was later wired up or deleted.
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
# The ablations. Each doctors a copy of the workflow, runs on every
# invocation and must go red: a coverage check that cannot fail is the
# defect it exists to catch. C is the comment case the header
# describes.
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

# B. a step naming a gate that is not there.
{ cat "$ci_yml"; printf '      - name: ablation\n        run: ./scripts/check-not-a-real-gate.sh\n'; } > "$work/b.yml"
ablate "a step running a gate that does not exist" "$work/b.yml" \
       "ci.yml runs scripts/check-not-a-real-gate.sh, which is not in the tree"

# C. the uncovered gate is named, but only inside a comment.
{ grep -v "scripts/$victim" "$ci_yml"
  printf '      # see scripts/%s for the same idea\n' "$victim"; } > "$work/c.yml"
ablate "scripts/$victim named only in a comment" "$work/c.yml" \
       "scripts/$victim is on disk and no CI step runs it"

# Mentions that are not executions. Each of D-J keeps the gate's path
# outside a comment, where a grep would count it, and must still be
# refused. Each doctors the one `run: ./scripts/<gate>` line of a gate
# that exactly one step runs, so the edit is a single line with a clear
# effect. The gate is the first such in name order, not a name written
# here, so a rename cannot turn the edits into no-ops; the match count
# is asserted too.
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
    # Passed through the environment because BSD awk refuses a newline
    # in a `-v` assignment, and some replacements span several lines.
    REP="$2" awk -v at="$lone_at" 'NR == at { print ENVIRON["REP"]; next } { print }' "$ci_yml" > "$1"
    cmp -s "$ci_yml" "$1" && bad "doctoring line $lone_at changed nothing"
  }

  # D. the step echoes the path instead of running it.
  doctor "$work/d.yml" "${lone_ind}run: echo ./scripts/$lone"
  ablate "scripts/$lone echoed rather than run" "$work/d.yml" "$want (named in a step, but \`echo ./scripts/$lone\` is a mention"

  # E. the step's name carries the path; its run does something else.
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

# The audit's copy: the real `check-scope-equiv.sh` step turned into an
# echo of itself. It reproduces one known failure, so the gate is named
# here rather than chosen, and the seam's count fails instead of going
# quiet if the step moves or the gate is renamed.
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
