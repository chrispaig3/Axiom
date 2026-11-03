#!/usr/bin/env bash
# Every gate on disk is planned by CI exactly once, and the workflow
# executes the plan.
#
# The battery is no longer a hand-written step list: `scripts/ci-plan.py`
# discovers `scripts/check-*.sh` and assigns each gate to the battery
# or to the dedicated job in its SPECIAL table, and the workflow runs
# the plan through `scripts/ci-run.py`. Coverage can therefore drift in
# three new places instead of the old one:
#
#   - the plan drops or double-assigns a gate (a SPECIAL entry for a
#     renamed gate, a discovery glob that goes stale);
#   - the workflow stops executing the plan (the ci-run step deleted,
#     renamed, or reduced to a mention);
#   - a SPECIAL gate loses the literal step in its owning job.
#
# `ci-plan.py --audit` checks all three, reading SPECIAL invocations
# structurally through `scripts/lib/ci-steps.py`, so a comment or a
# step name does not count as running one. This gate is the wrapper
# that also proves the audit can fail: the ablations below doctor the
# plan and the workflow and each must be refused.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || { echo "FAIL: no repository root at $repo_root" >&2; exit 1; }

# This gate compares lists of file names and runs no Axiom program, so
# it finds `$repo_root` itself instead of calling `gate_init`, which
# bootstraps a compiler on a clean checkout.

ci_yml="$repo_root/.github/workflows/ci.yml"
[[ -f "$ci_yml" ]] || { echo "FAIL: $ci_yml is missing"; exit 1; }
# Overridable so the ablations can point the gate at a doctored copy
# without editing the workflow the repository ships.
ci_yml="${CI_YML_OVERRIDE:-$ci_yml}"

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

audit() {  # audit <workflow> [env assignments...]
  local yml="$1"; shift
  env "$@" python3 "$repo_root/scripts/ci-plan.py" --audit "$yml" 2>&1
}

# --------------------------------------------------------------------
# 1. The real workflow and the real plan agree with the tree.
# --------------------------------------------------------------------
echo "== every gate on disk is planned once, and the workflow runs the plan =="
complaints="$(audit "$ci_yml")"
if [[ -n "$complaints" ]]; then
  while IFS= read -r line; do bad "$line"; done <<< "$complaints"
else
  total="$(cd "$repo_root/scripts" && ls check-*.sh | wc -l | tr -d ' ')"
  ok "$total gate scripts on disk, each assigned once by ci-plan.py, and the workflow executes the plan"
fi
if check_out="$(python3 "$repo_root/scripts/ci-plan.py" --check 2>&1)"; then
  echo "     $check_out"
else
  bad "ci-plan.py --check failed: $check_out"
fi

# --------------------------------------------------------------------
# The ablations. Each doctors the plan or the workflow, runs on every
# invocation and must go red: a coverage check that cannot fail is the
# defect it exists to catch.
# --------------------------------------------------------------------
echo "== the ablations: each doctored input must be refused =="

ablate() {  # ablate <what> <wanted substring> <audit output>
  local what="$1" want="$2" got="$3"
  if [[ "$got" == *"$want"* ]]; then
    ok "ablation: $what -> refused"
  else
    bad "ablation: $what was NOT refused (this gate cannot fail that way)"
    echo "     wanted a complaint containing: $want"
    echo "     got: ${got:-<silence>}"
  fi
}

victim="$(python3 "$repo_root/scripts/ci-plan.py" --shard 1 | head -1)"
[[ -n "$victim" ]] || bad "ci-plan.py --shard 1 named no gate to ablate with"

# A. the plan drops a battery gate.
ablate "the plan drops scripts/$victim" \
       "scripts/$victim is assigned 0 times" \
       "$(audit "$ci_yml" "CI_PLAN_DROP=$victim")"

# B. the plan names a gate that is not there.
ablate "the plan names a gate that does not exist" \
       "the plan names scripts/check-not-a-real-gate.sh, which is not in the tree" \
       "$(audit "$ci_yml" "CI_PLAN_EXTRA_SPECIAL=check-not-a-real-gate.sh")"

# C. the workflow stops executing the plan's runner.
grep -v 'ci-run\.py' "$ci_yml" > "$work/c.yml"
ablate "the ci-run step deleted from the workflow" \
       "the test job never runs scripts/ci-run.py" \
       "$(audit "$work/c.yml")"

# D. a SPECIAL gate loses its literal step.
grep -v 'scripts/check-ffi\.sh' "$ci_yml" > "$work/d.yml"
ablate "the step running scripts/check-ffi.sh deleted" \
       "scripts/check-ffi.sh belongs to the \`ffi\` job and no step runs it" \
       "$(audit "$work/d.yml")"

# --------------------------------------------------------------------
# 2. The machinery's own tests: reuse and selection, the shard and
# cache contract, the toolchain record and the timer. They run here
# so nothing under tests/ci/ can rot unrun while the workflow it
# describes changes shape around it.
# --------------------------------------------------------------------
echo "== the CI machinery's own tests =="
for t in gate-cache shards toolchain-record timing; do
  if python3 "$repo_root/tests/ci/$t.py" > "$work/$t.log" 2>&1; then
    ok "tests/ci/$t.py"
  else
    bad "tests/ci/$t.py failed"
    sed 's/^/     /' "$work/$t.log" | head -20
  fi
done

echo
if (( failed )); then
  echo "FAIL ($failed) - the plan, the workflow and the tree disagree"
  exit 1
fi
echo "PASS $checks checks: plan, workflow and tree agree, and every ablation was refused"
