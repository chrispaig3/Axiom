#!/usr/bin/env bash
# Assert that `gate_build_axc`'s cache cannot hide a change to the tree.
#
# WHY THIS GATE EXISTS AT ALL. `scripts/lib/gate.sh` is not a gate; it
# is the preamble seventeen gates share, and `gate_build_axc` is the
# line in it that makes those seventeen test the compiler in the
# WORKING TREE rather than whatever binary happens to be on disk. Its
# own comment says so: building from `self_host/` "is also what makes
# an ablation of `self_host/` visible to that gate rather than
# invisible."
#
# Then a cache was added to it, because seventeen rebuilds of the same
# 60,881 lines is ~28 minutes per matrix leg and ~85 across three, for a
# byte-identical artifact every time. An environment variable naming a
# prebuilt compiler is EXACTLY the shape that deletes the property
# above, silently, in every one of those seventeen gates at once - and
# the failure would look like green CI, which is the worst way for a
# gate to be wrong.
#
# So the cache is content-addressed: `$AXIOM_AXC` is used only when
# `$AXIOM_AXC.stamp` equals `gate_source_stamp` for the tree as it is
# right now. This file is the probe that the addressing works, and it
# is written the only way that proves anything - by planting a builder
# that CANNOT BUILD. If the cache is used, `gate_build_axc` succeeds
# and the bytes are the planted ones. If it is not, the stub runs and
# the call fails. There is no third outcome, so each probe below reads
# the cache decision directly rather than inferring it from a timing or
# a log line.
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

# run_probe <want: reuse|rebuild> <label>
#
# Calls `gate_build_axc` in a subshell - it exits on a build failure,
# which here is the expected outcome half the time - with `repo_root`
# and `axiom` pointed at the sandbox and the stub.
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
  else
    echo "FAIL $label: neither outcome - exit $rc, and the log is:"
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
#    takes, and the one that must never be trusted.
stamp_of_sandbox > "$planted.stamp"
rm -f "$planted.stamp"
AXIOM_AXC="$planted" run_probe rebuild "an unstamped artifact is ignored"

# 5. A stamp that is merely present and wrong.
echo "0000000000000000000000000000000000000000000000000000000000000000" > "$planted.stamp"
AXIOM_AXC="$planted" run_probe rebuild "a wrong stamp is ignored"

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
if (( failed > 0 )); then
  echo "check-gate-lib: $failed of $checks checks failed"
  exit 1
fi
echo "check-gate-lib: $checks checks - the shared artifact is used only when it"
echo "                was built from the tree as it stands, so seventeen gates"
echo "                still see an ablation of self_host/"
