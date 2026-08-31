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
#   axiom      the compiler that BUILDS the subject, resolved in this
#              order and PRINTED either way, so the choice is never
#              invisible:
#                1. `$AXIOM`, when set - unconditionally, even to a
#                   path that turns out to be broken. A caller who
#                   names a compiler gets that compiler; gate_init does
#                   not second-guess it.
#                2. otherwise `$AXIOM_AXC`, when it is set AND
#                   executable - the compiler UNDER TEST that
#                   `gate_build_axc`'s content-addressed cache already
#                   trusts. Without this arm, a gate that never calls
#                   `gate_build_axc` ignores `$AXIOM_AXC` entirely and
#                   falls through to arm 3 - `check-fmt.sh` is the one
#                   that bit us: `AXIOM_AXC=/path/to/new
#                   ./scripts/check-fmt.sh` built and tested
#                   `.axiom-bin/axiom`, the stale INSTALLED binary,
#                   and said nothing about it.
#                3. otherwise `.axiom-bin/axiom`, bootstrapped from
#                   `bootstrap/` when it is not there yet.
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
#
# THE RESOLVED COMPILER IS RUN ONCE, HERE, AND MUST ANSWER, because
# `-x` is not proof of life. Overwriting `.axiom-bin/axiom` IN PLACE -
# a `cp` onto an existing file, which truncates and rewrites the same
# inode, rather than a `mv` over it - leaves a binary that `codesign -v`
# still calls valid while macOS SIGKILLs every exec of it (exit 137, no
# output) until the inode is replaced. `scripts/bootstrap-from-seed.sh`
# hit this for real on 2026-08-28, installing by rename because of it.
# Reproduced again 2026-08-31 to confirm before writing this: racing a
# `cp` of a second binary against a tight loop of `axiom --version`
# turned most of the loop's remaining exits to 137 with empty output,
# and the exec run immediately AFTER the race had also stopped - the
# poisoning outlives the write that caused it, on this machine for at
# least several seconds, and `rm`-then-copy (a fresh inode) cleared it
# immediately where overwriting again did not.
#
# That is exactly the shape `check-fmt.sh` hit live: `FAIL <file>` with
# an EMPTY message, 559 times, before anyone realised the compiler
# itself was dead rather than 559 files. A gate that loops the compiler
# over a corpus has no way to tell "the file is bad" from "the compiler
# is dead" from inside the loop - both print nothing - so the check
# belongs here, once, before any loop starts: one clear refusal, naming
# the path, the exit status, and the SIGKILL cause when the status says
# so, instead of hundreds of empty ones downstream.
gate_init() {
  local want_stdlib=1
  [[ "${1:-}" == "--no-stdlib" ]] && want_stdlib=0

  repo_root="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
  cd "$repo_root" || { echo "FAIL: no repository root at $repo_root" >&2; exit 1; }

  if [[ -n "${AXIOM:-}" ]]; then
    axiom="$AXIOM"
    echo "gate: compiler is \$AXIOM = $axiom" >&2
    [[ -n "${AXIOM_AXC:-}" ]] \
      && echo "gate: \$AXIOM_AXC = $AXIOM_AXC is set too, but \$AXIOM wins - ignoring it" >&2
  elif [[ -n "${AXIOM_AXC:-}" && -x "${AXIOM_AXC}" ]]; then
    axiom="$AXIOM_AXC"
    echo "gate: \$AXIOM is unset; compiler is \$AXIOM_AXC = $axiom (the compiler under test)" >&2
  else
    [[ -n "${AXIOM_AXC:-}" ]] \
      && echo "gate: \$AXIOM_AXC = $AXIOM_AXC is not an executable file - ignoring it" >&2
    axiom="$repo_root/.axiom-bin/axiom"
    echo "gate: compiler is the installed $axiom (neither \$AXIOM nor \$AXIOM_AXC names one)" >&2
  fi

  if [[ ! -x "$axiom" ]]; then
    echo "no compiler at $axiom - building one from the committed seed" >&2
    "$repo_root/scripts/bootstrap-from-seed.sh" --install "$repo_root/.axiom-bin" >&2 \
      || { echo "FAIL: could not bootstrap a compiler from bootstrap/" >&2; exit 1; }
  fi

  local probe rc=0
  probe="$("$axiom" --version 2>&1)" || rc=$?
  if (( rc != 0 )); then
    echo "FAIL: $axiom did not run (exit $rc)." >&2
    echo "      output: ${probe:-<none>}" >&2
    if (( rc == 137 )); then
      echo "      exit 137 is SIGKILL. On macOS the likely cause is a stale code-" >&2
      echo "      signature cache: this file was overwritten IN PLACE (same inode -" >&2
      echo "      e.g. \`cp\` onto an existing file) after being executed once." >&2
      echo "      \`codesign -v\` will still call it valid; the kernel kills it anyway," >&2
      echo "      on every exec, until the inode is replaced. Fix: remove the file and" >&2
      echo "      copy the replacement in, or \`mv\` a freshly-built one over it - do" >&2
      echo "      not overwrite it in place. See the install step in" >&2
      echo "      scripts/bootstrap-from-seed.sh, which does this for exactly this" >&2
      echo "      reason." >&2
    fi
    exit 1
  fi

  (( want_stdlib )) && export AXIOM_STDLIB="$repo_root/stdlib"
  link_entry="$(gate_link_entry)"

  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
}

# gate_link_entry
#
# What a gate adds to `cc` when it links a compiler or a test program:
# `-e _main` on Darwin, nothing anywhere else. `gate_init` puts it in
# `$link_entry`, which the link lines pass UNQUOTED so that it
# word-splits into two arguments on Darwin and into none elsewhere.
#
# Eight link lines passed `-e _main` unconditionally until 2026-08-29,
# and nothing said why. On Mach-O it is ld64's default, so it was
# never load-bearing. On Linux, GNU ld warns "cannot find entry symbol
# _main; defaulting to <address>" and starts at the beginning of
# `.text`, which is crt1's `_start` - green by luck, on every Linux
# run this repository has had. FreeBSD's `/usr/bin/ld` is lld, and
# lld's answer is different. Measured 2026-08-29 with LLD 23.1 on a
# freebsd-x86_64 object of `tests/stdlib/010-hello.ax`:
#
#     ld.lld -e _main hello.o -o a.out
#     ld.lld: warning: cannot find entry symbol _main; not setting start address
#     exit 0;  llvm-readobj -h: Entry: 0x0
#
# with `main` in `.text` at 0x206090 and `-e main` landing there. So
# under lld an unresolved `-e` is a link that SUCCEEDS and a binary
# whose first instruction is at address 0: the seed would have linked
# on the FreeBSD leg and died before `main`, and "could not link the
# seed" would never have fired, because the link did not fail. The
# flag is therefore Darwin's alone, and kept there rather than deleted
# so that Darwin's link line is byte for byte what it has been.
gate_link_entry() {
  case "$(uname -s)" in
    Darwin) echo "-e _main" ;;
    *)      echo "" ;;
  esac
}

# gate_source_stamp
#
# A hash of everything the compiler-under-test is built FROM: every
# `.ax` the build reads - `self_host/` and the stdlib modules it
# imports, 43 files and 2.5 MB today - plus the builder binary itself.
# 0.04s to compute, against ~100s to build.
#
# This exists so `gate_build_axc`'s cache can be content-addressed. It
# is the whole safety argument, so it must stay a SUPERSET of the
# build's real inputs: a file the build reads and this does not hash is
# a file whose ablation the cache would hide.
gate_source_stamp() {
  {
    gate_seed_source_stamp "$repo_root"
    gate_sha "$axiom"
  } | gate_sha
}

# gate_seed_source_stamp <root>
#
# The same hash WITHOUT the builder: a pure function of the `.ax` bytes
# under `<root>/self_host` and `<root>/stdlib`, and of their paths.
#
# It takes a root rather than reading `$repo_root` because its second
# caller is `check-seed-provenance.sh`, which computes it over a tree
# extracted from git at another commit and compares the two. That is
# the whole point of splitting it out: "which sources is this?" is a
# question about a tree, and "which compiler would this cache serve?"
# is a question about a tree AND the binary that built it. Answering
# the first with the second would make the seed's recorded provenance
# depend on whichever compiler happened to be on the machine.
gate_seed_source_stamp() {
  local root="$1" list f
  # The PATH LIST first, then every byte. Contents alone would miss a
  # file added empty or renamed; paths alone would miss an edit.
  #
  # `find` rather than a glob, because a glob matching nothing is a
  # `cat` failure and under `set -euo pipefail` that ends the GATE
  # rather than the stamp - measured while writing this, and it
  # presented as a gate that printed its first heading and stopped.
  #
  # Relative paths and `LC_ALL=C sort`: the stamp is a property of the
  # tree, not of where it was checked out or of the runner's locale.
  list="$( cd "$root" && find self_host stdlib -name '*.ax' -type f 2>/dev/null \
             | LC_ALL=C sort )"
  {
    printf '%s\n' "$list"
    while IFS= read -r f; do
      [[ -n "$f" ]] && cat "$root/$f"
    done <<< "$list"
  } | gate_sha
}

# `sha256sum` on Linux, `shasum -a 256` on macOS - the same fallback
# `bootstrap-from-seed.sh` already carries, because the runner ships
# one or the other and not both.
gate_sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@" | cut -d' ' -f1
  else
    shasum -a 256 "$@" | cut -d' ' -f1
  fi
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
# THE CACHE, AND WHY IT DOES NOT COST THAT PROPERTY. Forty-seven gates
# call this, each rebuilding the same 60,881 lines. Measured on the
# three CI legs on 2026-08-24: the `test` job took 17m38s / 18m54s /
# 10m01s before the cache and 10m48s / 11m51s / 7m46s after it, so the
# duplicated builds were about sixteen minutes of every run.
# `$AXIOM_AXC` lets one CI step build it once.
#
# An env var naming a prebuilt compiler is exactly how this function's
# own reason for existing gets deleted, so the cache is CONTENT-
# ADDRESSED rather than trusted: the artifact is used only when
# `$AXIOM_AXC.stamp` equals `gate_source_stamp` for the tree as it is
# right now. Change a byte anywhere the build reads and the stamp
# moves, the cache misses, and a fresh compiler is built - so an
# ablation of `self_host/` is visible BY CONSTRUCTION, not by anyone
# remembering to invalidate anything.
#
# A STALE STAMP AND AN ABSENT ONE ARE NOT THE SAME EVENT, and until
# 2026-08-24 this function treated them as one. Both fell through to
# "build it yourself", which is correct for the first and a silent
# failure for the second: `AXIOM_AXC=.axiom-bin/axiom` - a seed
# compiler, no stamp beside it - was ignored and every gate went
# GREEN, having quietly paid the build the variable was set to avoid.
# The roadmap that asked for this cache also asked that pointing it at
# the seed go red, and it did not.
#
# So they are now separated by what the stamp SAYS rather than by what
# the caller meant:
#
#   stamp present and equal   -> reuse. The artifact was built from
#                                this tree by this builder.
#   stamp present and different -> build. The tree moved; that is the
#                                whole point of the content address,
#                                and `check-fmt.sh` reaches it on every
#                                run by design (it runs its inner gates
#                                against a COPY of the tree).
#   no stamp, no artifact, or a
#   non-executable artifact   -> REFUSE. Nothing was built here. A
#                                path that does not name a stamped
#                                build product is a mistake in the
#                                caller, not a cache miss, and it must
#                                be as loud as one.
#
# `scripts/check-gate-lib.sh` is the negative probe: it plants a
# builder that cannot build and asserts the cache is used when the
# stamp matches, NOT used when it does not, and refused when there is
# no stamp at all.
#
# The build log is kept at `$work/<varname>.build.log` and its first
# twenty lines are printed on failure.
gate_build_axc() {
  local var="$1" out="${2:-$work/$1}" log="$work/$1.build.log"
  local stamp; stamp="$(gate_source_stamp)"

  if [[ -n "${AXIOM_AXC:-}" ]]; then
    if [[ ! -x "$AXIOM_AXC" ]]; then
      echo "FAIL: AXIOM_AXC names $AXIOM_AXC, which is not an executable file." >&2
      echo "      Set it to the output of scripts/build-shared-axc.sh, or unset it." >&2
      exit 1
    fi
    if [[ ! -f "${AXIOM_AXC}.stamp" ]]; then
      echo "FAIL: AXIOM_AXC names $AXIOM_AXC, which has no .stamp beside it." >&2
      echo "      Only scripts/build-shared-axc.sh writes that stamp, and without" >&2
      echo "      it there is nothing to say which tree the binary was built from," >&2
      echo "      so it cannot be the compiler under test. Ignoring it here would" >&2
      echo "      let a seed compiler stand in for the working tree and report a" >&2
      echo "      green gate for a build that never happened." >&2
      exit 1
    fi
    if [[ "$(cat "${AXIOM_AXC}.stamp")" == "$stamp" ]]; then
      echo "== reusing the compiler under test (source stamp ${stamp:0:12}) =="
      cp "$AXIOM_AXC" "$out"
      printf -v "$var" '%s' "$out"
      return 0
    fi
  fi

  echo "== building the compiler under test from self_host/ =="
  if ! "$axiom" build --input self_host/main.ax --output "$out" >"$log" 2>&1; then
    echo "FAIL: could not build the compiler under test from self_host/" >&2
    sed 's/^/    /' "$log" | head -20 >&2
    exit 1
  fi
  printf '%s\n' "$stamp" > "$out.stamp"
  printf -v "$var" '%s' "$out"
}

# The prose documents that carry Axiom code and cite fixtures.
#
# Three gates swept this list and each kept its own hand-written copy -
# `check-tree-sitter.sh`, `check-tools-selfhost.sh` and, in a Python
# heredoc, `check-doc-drift.sh`. They had already diverged: two of them
# named a retired spelling of the macro document and the third named
# that plus two more, so `docs/ffi.md` and `docs/diagnostics.md` were
# swept by none of them. A document outside a sweep's list is invisible
# to it, which is the sentence `check-tree-sitter.sh` already carried
# about a list that was missing two entries.
#
# The list is hand-written on purpose - a sweep cannot discover a
# document it was never told about - but a hand-written list drifts in
# BOTH directions, and both are now checked by `check-doc-drift.sh`:
# a name here that is not in the tree, and a document in the tree that
# is not named here. The first direction is why that check exists. On
# 2026-08-23 two documents were deleted and left in this list, and the
# three gates that sweep it did not report drift - they died on a
# Python traceback before reaching their own first assertion, in 11
# seconds of CI, because a list entry is opened before it is checked.
#
# `gate_prose_docs` prints them repo-relative;
# `gate_prose_docs_abs` fills the array `prose_docs` with `$repo_root`
# prefixed - a function rather than `mapfile`, because the macOS runner
# ships bash 3.2 and has no `mapfile`.
# The list is checked here rather than by each caller, because the
# caller is a Python heredoc that opens what it is given: a name with no
# file behind it surfaces as a traceback from inside the sweep, which
# reads as a broken gate and not as the drift it is. Three gates failed
# that way on 2026-08-23 and the first of them took 11 seconds to say
# nothing useful. A missing document is a one-line refusal now, from the
# gate that noticed, naming the list it came from.
gate_prose_docs_abs() {
  local d missing=0
  prose_docs=()
  while IFS= read -r d; do
    if [[ ! -f "$repo_root/$d" ]]; then
      echo "gate: \`gate_prose_docs\` names $d, which does not exist." >&2
      echo "gate: a document was deleted without being removed from the list" >&2
      echo "gate: in scripts/lib/gate.sh, which every prose sweep reads." >&2
      missing=$((missing + 1))
      continue
    fi
    prose_docs+=("$repo_root/$d")
  done < <(gate_prose_docs)
  (( missing == 0 )) || exit 1
}

# `docs/stdlib-api.md` is here because it is a document under `docs/`
# and `check-doc-drift.sh` fails one that is in no sweep's list - a
# rule worth keeping even for a GENERATED file. Its own gate,
# `check-stdlib-api.sh`, is stronger than any prose sweep: it
# regenerates the whole document and diffs it. What the sweeps add is
# the two things a regeneration cannot see, because the generator
# would reproduce them faithfully - a link to a document that no
# longer exists, and a fixture path that no longer resolves.
#
# `CHANGELOG.md` is here because `release.yml` passes it to
# `gh release create --notes-file`: it is the first document a stranger
# reads, and it was the ONE prose file in the tree that no sweep
# opened - while opening with the claim that every claim in it carries
# the gate that establishes it.
gate_prose_docs() {
  cat <<'DOCS'
README.md
CONTRIBUTING.md
CHANGELOG.md
SECURITY.md
docs/reference.md
docs/diagnostics.md
docs/error-model.md
docs/ffi.md
docs/macro-system.md
docs/memory-model.md
docs/memory-model-v2-proposal.md
docs/memory-model-v2-design.md
docs/agent-harness.md
docs/compatibility.md
docs/lsp.md
docs/stdlib-api.md
docs/checked-arithmetic-design.md
DOCS
}
