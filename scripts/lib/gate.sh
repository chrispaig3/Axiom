# ---------------------------------------------------------------------
# The preamble every gate had its own copy of.
#
# Twenty-four of the scripts beside this one opened with the same
# fifteen lines: find the repository root from `$BASH_SOURCE`, cd
# there, resolve `$AXIOM` or build one from the committed seed, export
# `AXIOM_STDLIB`, make a work directory and arm the trap that removes
# it. Eighteen went on to build the compiler under test from
# `self_host/` with the same seven.
#
# Copies drift, and these had:
#
#   - `check-doc-drift.sh` never grew the seed-bootstrap block, so on a
#     checkout with no `.axiom-bin/` it failed with "no compiler at ..."
#     while its twenty-three peers built one and carried on.
#   - the same failure ran under two spellings, "could not bootstrap a
#     compiler" and "... a compiler from bootstrap/", nine ways and
#     fourteen.
#   - the build-the-subject block wrote its log to `$work/build.log` in
#     most scripts and `$work/s1build.log` or `$work/s1.log` in others,
#     spelled the output `-o` here and `--output` there, and reported
#     the first 8 lines of the log on failure, or 20, or none at all -
#     and a gate that swallows the log is a gate whose failure mode is
#     "FAIL: could not build", with no way to see why.
#
# None of that is a difference anyone chose, so it lives here once. A
# gate now opens with:
#
#     source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
#     gate_init
#     gate_build_axc axc
#
# after which `$repo_root`, `$axiom`, `$work` and `$axc` mean in every
# gate what they meant in the twenty-four that spelled them out.
#
# What this file deliberately does NOT hold: anything that runs the
# compiler, counts cases or reports results. Those differ per gate for
# real reasons, and a helper that unified them would be a framework a
# reader had to learn before they could read a single gate. The rule is
# the one this repository applies to its own sources - share what is
# identical, leave what differs where the reader will find it.
# ---------------------------------------------------------------------

# gate_init [--no-stdlib]
#
# Sets, in the calling script:
#   repo_root  the repository root, and cd's there
#   axiom      the compiler that BUILDS the subject - `$AXIOM` when
#              set, otherwise `.axiom-bin/axiom`, bootstrapped from
#              `bootstrap/` when it is not there yet
#   work       a fresh temporary directory, removed on exit
# and exports AXIOM_STDLIB, so a compiler invoked from anywhere
# resolves THIS checkout's stdlib rather than one beside some other
# binary.
#
# --no-stdlib suppresses that export, for the three gates that point
# the compiler at a stdlib of their own: `check-fmt.sh` and
# `check-frontend-parity.sh` run against a copy of the tree, and a
# repo-rooted export would quietly test the original instead; and
# `check-doc-drift.sh` resolves its probe imports through the working
# directory it compiles from.
gate_init() {
  local want_stdlib=1
  [[ "${1:-}" == "--no-stdlib" ]] && want_stdlib=0

  repo_root="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
  cd "$repo_root" || { echo "FAIL: no repository root at $repo_root" >&2; exit 1; }
  axiom="${AXIOM:-$repo_root/.axiom-bin/axiom}"

  if [[ ! -x "$axiom" ]]; then
    echo "no compiler at $axiom - building one from the committed seed" >&2
    "$repo_root/scripts/bootstrap-from-seed.sh" --install "$repo_root/.axiom-bin" >&2 \
      || { echo "FAIL: could not bootstrap a compiler from bootstrap/" >&2; exit 1; }
  fi
  (( want_stdlib )) && export AXIOM_STDLIB="$repo_root/stdlib"

  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
}

# gate_build_axc <varname> [output-path]
#
# Builds the compiler under test from the CURRENT `self_host/` sources
# and assigns its path to <varname>, defaulting to `$work/<varname>`.
#
# `$axiom` supplies *a* compiler, not *the* compiler: it may be an
# older seed-descended binary that predates the change being tested, so
# every gate whose subject is the compiler builds one from the tree
# first - which is also what makes an ablation of `self_host/` visible
# to that gate rather than invisible.
#
# The build log is kept at `$work/<varname>.build.log` and its first
# twenty lines are printed on failure.
gate_build_axc() {
  local var="$1" out="${2:-$work/$1}" log="$work/$1.build.log"
  echo "== building the compiler under test from self_host/ =="
  if ! "$axiom" build --input self_host/main.ax --output "$out" >"$log" 2>&1; then
    echo "FAIL: could not build the compiler under test from self_host/" >&2
    sed 's/^/    /' "$log" | head -20 >&2
    exit 1
  fi
  printf -v "$var" '%s' "$out"
}
