#!/usr/bin/env bash
# Assert that `gate_build_axc`'s cache cannot hide a change to the tree.
#
# WHY THIS GATE EXISTS AT ALL. `scripts/lib/gate.sh` is not a gate; it
# is the preamble twenty gates share, and `gate_build_axc` is the
# line in it that makes those nineteen test the compiler in the
# WORKING TREE rather than whatever binary happens to be on disk. Its
# own comment says so: building from `self_host/` "is also what makes
# an ablation of `self_host/` visible to that gate rather than
# invisible."
#
# Then a cache was added to it, because nineteen rebuilds of the same
# 60,881 lines was about sixteen minutes of every CI run, measured on
# all three legs. An environment variable naming a prebuilt compiler is
# EXACTLY the shape that deletes the property above, silently, in every
# one of those twenty gates at once - and the failure would look like
# green CI, which is the worst way for a gate to be wrong.
#
# So the cache is content-addressed: `$AXIOM_AXC` is used only when
# `$AXIOM_AXC.stamp` equals `gate_source_stamp` for the tree as it is
# right now. This file is the probe that the addressing works, and it
# is written the only way that proves anything - by planting a builder
# that CANNOT BUILD. If the cache is used, `gate_build_axc` succeeds
# and the bytes are the planted ones. If it is not, the stub runs and
# the call fails. If the path is not a build product at all, neither
# happens and the call refuses. Each outcome is therefore read off the
# artifact and the stub's own shout rather than inferred from a timing
# or a log line.
#
# NOTHING HERE TOUCHES THE REAL TREE. `gate_source_stamp` hashes
# `$repo_root`, so the probes point `repo_root` at a sandbox holding
# two fake `.ax` files. That is what lets the ablation probe modify a
# source file at all: the interesting case is "a byte of `self_host/`
# changed", and doing that to the actual checkout to test a cache would
# be its own kind of wrong.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

failed=0
checks=0

sandbox="$work/tree"
mkdir -p "$sandbox/self_host" "$sandbox/stdlib"
printf '(:: main Int)\n\n(fn (main) 0)\n'  > "$sandbox/self_host/main.ax"
printf '(pub :: helper Int)\n\n(fn (helper) 1)\n' > "$sandbox/stdlib/Mem.ax"

# A builder that cannot build. Its presence in the output is the signal
# that the cache was NOT used.
stub="$work/stub-builder"
cat > "$stub" <<'STUB'
#!/usr/bin/env bash
echo "STUB-BUILDER-RAN" >&2
exit 1
STUB
chmod +x "$stub"

# The artifact a CI step would hand over, with contents nothing else
# could produce.
planted="$work/planted-axc"
printf 'PLANTED-ARTIFACT\n' > "$planted"
chmod +x "$planted"

stamp_of_sandbox() { ( repo_root="$sandbox"; axiom="$stub"; gate_source_stamp ); }

# run_probe <want: reuse|rebuild|refuse> <label>
#
# Calls `gate_build_axc` in a subshell - it exits on a build failure,
# which here is the expected outcome half the time - with `repo_root`
# and `axiom` pointed at the sandbox and the stub.
#
# THREE outcomes, not two. `reuse` and `rebuild` are read off the
# artifact and the stub's own shout. `refuse` is the third: the caller
# named something that is not a stamped build product, and
# `gate_build_axc` stops instead of quietly building. It is
# distinguishable from `rebuild` by the stub never having run - which
# is exactly the difference that matters, because a refusal that ran
# the builder anyway would be a rebuild wearing a louder message.
run_probe() {
  local want="$1" label="$2" out="$work/out-$RANDOM" rc=0
  ( repo_root="$sandbox"; axiom="$stub"; work="$work"
    gate_build_axc probe_axc "$out" ) >"$work/probe.log" 2>&1 || rc=$?
  checks=$((checks + 1))

  local got
  if (( rc == 0 )) && [[ -f "$out" ]] && grep -q 'PLANTED-ARTIFACT' "$out"; then
    got="reuse"
  elif (( rc != 0 )) && grep -q 'STUB-BUILDER-RAN' "$work/probe.log"; then
    got="rebuild"
  elif (( rc != 0 )) && grep -q 'FAIL: AXIOM_AXC names' "$work/probe.log" \
       && ! grep -q 'STUB-BUILDER-RAN' "$work/probe.log"; then
    got="refuse"
  else
    echo "FAIL $label: no outcome - exit $rc, and the log is:"
    sed 's/^/     /' "$work/probe.log" | head -5
    failed=$((failed + 1))
    return
  fi

  if [[ "$got" == "$want" ]]; then
    echo "ok   $label"
  else
    echo "FAIL $label: wanted $want, got $got"
    failed=$((failed + 1))
  fi
}

echo "== the cache is used when, and only when, the stamp matches =="

# 1. POSITIVE. Without this the rest is satisfied by a cache that never
#    fires, which would pass every negative probe below and save
#    nothing.
stamp_of_sandbox > "$planted.stamp"
AXIOM_AXC="$planted" run_probe reuse "a matching stamp reuses the artifact"

# 2. THE LOAD-BEARING ONE. A byte of the sandbox's `self_host/` moves
#    AFTER the stamp was taken. This is the property `gate_build_axc`
#    exists for, and the one an env-var cache would have deleted.
printf '\n; an ablation\n' >> "$sandbox/self_host/main.ax"
AXIOM_AXC="$planted" run_probe rebuild "a changed self_host/ invalidates it"

# 3. The same for the standard library, which the compiler build also
#    reads - `self_host/` imports Fmt, Intern, Json, Mem, Path and Rpc,
#    so a stamp over `self_host/` alone would hide six modules.
stamp_of_sandbox > "$planted.stamp"
printf '\n; an ablation\n' >> "$sandbox/stdlib/Mem.ax"
AXIOM_AXC="$planted" run_probe rebuild "a changed stdlib/ invalidates it"

# 4. No stamp beside the artifact - the shape a hand-set `AXIOM_AXC`
#    takes, and the one that must never be trusted. It used to be
#    IGNORED, and that is the hole this probe was rewritten to close:
#    `AXIOM_AXC=.axiom-bin/axiom` names a real, working, seed-descended
#    compiler with no stamp, and every gate ran green against it while
#    silently rebuilding. Green for a build that never happened is the
#    failure mode the whole content address exists to prevent, so an
#    unstamped path is now refused rather than ignored.
stamp_of_sandbox > "$planted.stamp"
rm -f "$planted.stamp"
AXIOM_AXC="$planted" run_probe refuse "an unstamped artifact is refused"

# 4a. A path that names nothing at all. The typo case, and the case
#     where a CI step meant to build the artifact failed earlier and
#     left the variable set - which must not read as "no cache today".
AXIOM_AXC="$work/no-such-artifact" run_probe refuse "a missing artifact is refused"

# 4b. A path that exists but is not executable. A stamp beside it does
#     not rescue it: whatever produced it, it is not a compiler.
printf 'not a compiler\n' > "$work/plain-file"
stamp_of_sandbox > "$work/plain-file.stamp"
AXIOM_AXC="$work/plain-file" run_probe refuse "a non-executable artifact is refused"

# 5. A stamp that is merely present and WRONG, which is a different
#    event from having none: the artifact is a build product, it just
#    describes a tree that has since moved. That is a cache miss and
#    must stay one - `check-fmt.sh` reaches this arm on every run,
#    because it runs its inner gates against a copy of the tree and the
#    stamp legitimately does not match it. Refusing here would break
#    that gate, so the two arms are separated by the stamp's presence
#    rather than by its value.
echo "0000000000000000000000000000000000000000000000000000000000000000" > "$planted.stamp"
AXIOM_AXC="$planted" run_probe rebuild "a stale stamp rebuilds, and does not refuse"

# 6. The builder is in the stamp too, so an artifact built by a
#    different compiler is not reused even with the sources untouched.
stamp_of_sandbox > "$planted.stamp"
other="$work/other-builder"; cp "$stub" "$other"; printf '# different\n' >> "$other"
( repo_root="$sandbox"; axiom="$other"; work="$work"
  AXIOM_AXC="$planted" gate_build_axc probe_axc "$work/out-6" ) >"$work/probe.log" 2>&1 || true
checks=$((checks + 1))
if grep -q 'STUB-BUILDER-RAN' "$work/probe.log"; then
  echo "ok   a different builder invalidates it"
else
  echo "FAIL a different builder was not noticed by the stamp"
  failed=$((failed + 1))
fi

# 7. Unset is the default every developer runs, and it must build.
stamp_of_sandbox > "$planted.stamp"
( repo_root="$sandbox"; axiom="$stub"; work="$work"
  unset AXIOM_AXC
  gate_build_axc probe_axc "$work/out-7" ) >"$work/probe.log" 2>&1 || true
checks=$((checks + 1))
if grep -q 'STUB-BUILDER-RAN' "$work/probe.log"; then
  echo "ok   with AXIOM_AXC unset the compiler is built, as before"
else
  echo "FAIL AXIOM_AXC unset did not build"
  failed=$((failed + 1))
fi

echo
echo "== the stamp covers every file the build reads =="
# A stamp that misses an input is a cache that hides that input's
# ablation, so the file list is asserted rather than trusted. The
# compiler's own imports are the source of truth for which stdlib
# modules count, and the stamp takes ALL of them rather than tracking
# that list - so this check is that the glob still reaches both trees
# and finds the volume it found on 2026-08-24.
n_ax=$(ls "$repo_root"/self_host/*.ax "$repo_root"/stdlib/*.ax \
          "$repo_root"/stdlib/*/*.ax 2>/dev/null | wc -l | tr -d ' ')
checks=$((checks + 1))
if (( n_ax < 35 )); then
  echo "FAIL: the stamp globbed only $n_ax .ax files; there were 43 on 2026-08-24."
  echo "      A stamp that reaches nothing hashes nothing and matches always."
  failed=$((failed + 1))
else
  echo "ok   the stamp reaches $n_ax source files across both trees"
fi

# And it must actually change when one of them does - the same
# vacuousness check one level down.
checks=$((checks + 1))
before="$(stamp_of_sandbox)"
printf '\n; another ablation\n' >> "$sandbox/stdlib/Mem.ax"
after="$(stamp_of_sandbox)"
if [[ "$before" == "$after" ]]; then
  echo "FAIL: the stamp did not move when a source file did"
  failed=$((failed + 1))
else
  echo "ok   the stamp moves when a source file moves"
fi

echo
echo "== the count those comments state is the count the tree has =="
# THE DRIFT THIS CLOSES. On 2026-08-24 six places stated how many gates
# call `gate_build_axc`, and they said seventeen, eighteen and nineteen
# - three answers to one countable fact, in the prose that explains why
# the cache is safe. Nothing compared any of them to the tree, because
# `check-doc-drift.sh` sweeps the ten prose documents and these live in
# `scripts/` and in the workflow.
#
# The number is small and it moves whenever a gate is added, which is
# exactly the shape that goes stale silently. So it is recomputed here,
# beside the function it describes.
#
# `check-gate-lib.sh` itself is excluded from the count: it calls
# `gate_build_axc` only inside the sandboxed probes above, and it is
# the prober rather than one of the gates that rests on the cache.
n_axc=$(grep -l '^[[:space:]]*gate_build_axc' "$repo_root"/scripts/*.sh \
        | grep -v 'check-gate-lib.sh' | wc -l | tr -d ' ')

word_for() {
  case "$1" in
    15) echo fifteen ;;   16) echo sixteen ;;    17) echo seventeen ;;
    18) echo eighteen ;;  19) echo nineteen ;;   20) echo twenty ;;
    21) echo "twenty-one" ;; 22) echo "twenty-two" ;; 23) echo "twenty-three" ;;
    *)  echo "" ;;
  esac
}
want="$(word_for "$n_axc")"

checks=$((checks + 1))
if [[ -z "$want" ]]; then
  echo "FAIL: $n_axc gates call gate_build_axc, and this check has no word for it."
  echo "      Add it to word_for above, then update the six sites below."
  failed=$((failed + 1))
else
  echo "ok   $n_axc gates call gate_build_axc - the prose must say \"$want\""
fi

# The six places that state it. Named rather than discovered: a sweep
# cannot find a document it was never told about, and the failure this
# closes was a site nothing swept.
count_sites=(
  scripts/lib/gate.sh
  scripts/build-shared-axc.sh
  scripts/check-gate-lib.sh
  .github/workflows/ci.yml
  CONTRIBUTING.md
  CHANGELOG.md
)

for site in "${count_sites[@]}"; do
  checks=$((checks + 1))
  if [[ ! -f "$repo_root/$site" ]]; then
    echo "FAIL: $site is named here and does not exist"
    failed=$((failed + 1))
    continue
  fi
  # Both spellings the prose actually uses: "<word> gates" and
  # "<Word> of the gates below". Spelled with a placeholder rather than
  # an example, because an example here is a literal this check would
  # then find in its own source and refuse - which it did, the first
  # time the count moved.
  if grep -qiE "\b$want (of the )?gates" "$repo_root/$site"; then
    echo "ok   $site states \"$want\""
  else
    echo "FAIL: $site does not state \"$want gates\" anywhere."
    echo "      $n_axc scripts call gate_build_axc; that file says otherwise or"
    echo "      no longer says anything, and the safety argument is stated there."
    failed=$((failed + 1))
  fi
done

# And the other direction, which is the one that actually went wrong:
# a site may not state a DIFFERENT number. Without this, a file that
# states the right count in one paragraph and a stale one in the next
# passes the check above while still being wrong - which is exactly how
# `scripts/lib/gate.sh` and `check-gate-lib.sh` came to disagree with
# `build-shared-axc.sh` and `ci.yml` in the first place.
#
# This arm found its first drift while being written: a draft of the
# comment you are reading spelled a stale count out as an example, and
# the check refused the file it lives in. A gate that catches its own
# author is a gate that can fail.
for site in "${count_sites[@]}" scripts/bootstrap-from-seed.sh; do
  [[ -f "$repo_root/$site" ]] || continue
  for w in fifteen sixteen seventeen eighteen nineteen twenty; do
    [[ "$w" == "$want" ]] && continue
    checks=$((checks + 1))
    if grep -qiE "\b$w (of the )?gates" "$repo_root/$site"; then
      echo "FAIL: $site says \"$w gates\", and $n_axc gates call gate_build_axc."
      grep -niE "\b$w (of the )?gates" "$repo_root/$site" | sed 's/^/       /'
      failed=$((failed + 1))
    fi
  done
done
echo "ok   no site states a different number"

echo
if (( failed > 0 )); then
  echo "check-gate-lib: $failed of $checks checks failed"
  exit 1
fi
echo "check-gate-lib: $checks checks - the shared artifact is used only when it"
echo "                was built from the tree as it stands, so twenty gates"
echo "                still see an ablation of self_host/, and a path that names"
echo "                no build product is refused rather than ignored"
