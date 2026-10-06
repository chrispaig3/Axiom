# ---------------------------------------------------------------------
# The preamble every gate shares. A gate opens with:
#
#     source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
#     gate_init
#     gate_build_axc axc
#
# after which `$repo_root`, `$axiom`, `$work` and `$axc` mean the same
# thing in every gate. Hand-written copies of this preamble drift in
# their bootstrap step, error wording, log paths and how much of a
# failed build log they print, so it lives here once.
#
# This file holds nothing that runs the compiler, counts cases or
# reports results. Those differ per gate for real reasons, and keeping
# them in the gate keeps each gate readable on its own.
# ---------------------------------------------------------------------

# gate_init [--no-stdlib]
#
# Sets, in the calling script:
#   repo_root   the repository root, and cd's there
#   axiom       the compiler that builds the subject. It is printed, and
#               resolved in this order:
#                 1. `$AXIOM`, when set, even to a broken path. A caller
#                    who names a compiler gets that compiler.
#                 2. otherwise `$AXIOM_AXC`, when it is set and
#                    executable: the compiler under test, which
#                    `gate_build_axc`'s cache already trusts. Without
#                    this arm, a gate that never calls `gate_build_axc`
#                    (such as `check-fmt.sh`) would silently test the
#                    installed binary instead.
#                 3. otherwise `.axiom-bin/axiom`, bootstrapped from
#                    `bootstrap/` when it is not there yet.
#   link_entry  see `gate_link_entry`
#   work        a fresh temporary directory, removed on exit
# and exports AXIOM_STDLIB, so a compiler invoked from anywhere
# resolves this checkout's stdlib rather than one beside some other
# binary.
#
# --no-stdlib suppresses that export, for gates that must not resolve
# this checkout's stdlib through it. `check-fmt.sh` and
# `check-frontend-parity.sh` run against a copy of the tree, and a
# repo-rooted export would test the original instead.
# `check-doc-drift.sh` resolves its probe imports through the working
# directory it compiles from, and `check-seed-lineage.sh` compiles
# sources from other trees.
#
# The resolved compiler is run once here and must answer, because `-x`
# is not proof of life. On macOS, a binary overwritten in place (a `cp`
# onto an existing file, which keeps the inode) still passes
# `codesign -v`, but the kernel SIGKILLs every exec of it (exit 137, no
# output) until the inode is replaced. A gate that loops a dead
# compiler over a corpus would report every file as failing with an
# empty message. One refusal here, naming the path, the status and the
# likely cause, replaces hundreds of empty ones downstream.
# `scripts/bootstrap-from-seed.sh` installs by rename for this reason.
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
# `$link_entry`, which the link lines pass unquoted so that it splits
# into two arguments on Darwin and into none elsewhere.
#
# On Mach-O, `-e _main` is ld64's default and harmless. Elsewhere there
# is no `_main`. GNU ld warns and starts at `.text`, which happens to be
# crt1's `_start`. FreeBSD's `/usr/bin/ld` is lld, which links
# successfully with an entry point of 0 (here, a freebsd-x86_64 object
# of `tests/stdlib/010-hello.ax`):
#
#     ld.lld -e _main hello.o -o a.out
#     ld.lld: warning: cannot find entry symbol _main; not setting start address
#     exit 0;  llvm-readobj -h: Entry: 0x0
#
# That binary dies before `main` with no link error to explain it, so
# the flag is Darwin's alone. Darwin keeps it so that its link line
# stays byte for byte the same.
gate_link_entry() {
  case "$(uname -s)" in
    Darwin) echo "-e _main" ;;
    *)      echo "" ;;
  esac
}

# gate_source_stamp
#
# A hash of everything the compiler under test is built from: every
# `.ax` the build reads (`self_host/` and the stdlib), the builder
# binary, the toolchain and the environment the compiler reads. It is
# cheap next to a build.
#
# `gate_build_axc`'s cache is keyed on it, so it must stay a superset
# of the build's real inputs. A file the build reads and this does not
# hash is a file whose ablation the cache would hide.
gate_source_stamp() {
  {
    printf '%s\n' 'gate-cache-v3: native build, default optimization'
    gate_seed_source_stamp "$repo_root"
    gate_sha "$axiom"
    gate_toolchain_stamp
    gate_config_stamp
  } | gate_sha
}

# The environment the compiler reads while it builds: the `sysEnv`
# reads in `self_host/` and `stdlib/` that can change what a build of
# `self_host/main.ax` produces. AXIOM_STDLIB and AXIOM_PATH choose which
# module files an import resolves to, AXIOM_LINK_SEARCH what the link
# line finds, and AXIOM_MIR_EMIT / AXIOM_VERIFY_SCOPES switch extra work
# on. The rest (HOME, XDG_CONFIG_HOME, TMPDIR, AXIOM_REPL_HISTORY) are
# read only by the REPL and the package commands, and PATH is covered
# by the toolchain stamp's resolved tools. A new build-affecting
# `sysEnv` read belongs here.
#
# The stdlib is recorded as the directory a build would read, resolved
# physically, with `gate_init`'s default when unset. The source stamp
# hashes `$repo_root/stdlib`'s bytes, so a build pointed at a different
# stdlib must not match a binary built against this one. A caller that
# computes a stamp without `gate_init` (`run-gates.sh`) exports the
# same default first, or every consumer would miss.
gate_config_stamp() {
  local lib="${AXIOM_STDLIB:-$repo_root/stdlib}"
  [[ -d "$lib" ]] && lib="$(cd -P "$lib" && pwd -P)"
  printf '%s\n' "stdlib=$lib" \
    "AXIOM_PATH=${AXIOM_PATH:-}" \
    "AXIOM_LINK_SEARCH=${AXIOM_LINK_SEARCH:-}" \
    "AXIOM_MIR_EMIT=${AXIOM_MIR_EMIT:-}" \
    "AXIOM_VERIFY_SCOPES=${AXIOM_VERIFY_SCOPES:-}"
}

# Build inputs outside the Axiom source tree. Keep this separate from
# gate_seed_source_stamp: seed provenance describes sources, not a host.
gate_toolchain_stamp() {
  local tool path
  uname -srm
  printf '%s\n' "SDKROOT=${SDKROOT:-}" \
    "MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-}" \
    "DEVELOPER_DIR=${DEVELOPER_DIR:-}"
  for tool in opt llc cc; do
    path="$(command -v "$tool" || true)"
    printf '%s\n' "$tool=$path"
    if [[ -n "$path" && -f "$path" ]]; then
      gate_sha "$path"
      "$path" --version 2>&1 || return 1
    fi
  done
}

# gate_seed_source_stamp <root>
#
# The source part of that hash, without the builder: a function of the
# paths and bytes of every `.ax` under `<root>/self_host` and
# `<root>/stdlib`.
#
# It takes a root because `check-seed-provenance.sh` also computes it
# over a tree extracted from git at another commit. "Which sources is
# this?" is a question about a tree alone. Folding in the builder would
# make the seed's recorded provenance depend on whichever compiler was
# on the machine.
gate_seed_source_stamp() {
  local root="$1" list f
  # The path list first, then every byte. Contents alone would miss a
  # file added empty or renamed; paths alone would miss an edit.
  #
  # `find` rather than a glob: a glob matching nothing makes `cat` fail,
  # and under `set -euo pipefail` that silently ends the whole gate.
  #
  # Relative paths and `LC_ALL=C sort` keep the stamp independent of the
  # checkout path and the runner's locale.
  list="$( cd "$root" && find self_host stdlib -name '*.ax' -type f 2>/dev/null \
             | LC_ALL=C sort )"
  {
    printf '%s\n' "$list"
    while IFS= read -r f; do
      [[ -n "$f" ]] && cat "$root/$f"
    done <<< "$list"
  } | gate_sha
}

# `sha256sum` on Linux, `shasum -a 256` on macOS: each runner ships
# only one of them.
gate_sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@" | cut -d' ' -f1
  else
    shasum -a 256 "$@" | cut -d' ' -f1
  fi
}

# gate_axdl_unknown_kind <file>: refuse an AXDL line kind no filter knows.
#
# Every `axdl_only`-shaped filter in the battery keeps `^[EWNH] ` lines
# and drops the rest. The corpus emits `E` and `W`; `N` and `H` are
# reserved. A diagnostic-shaped line (`X AX3001 ...`) with any other
# letter would slip past every gate that filters before it compares
# (docs/compiler-guide.md §5). This prints such lines and returns
# nonzero when there are any, so call sites check beside the filters
# rather than through them.
gate_axdl_unknown_kind() {
  local f="$1" bad
  bad="$(grep -E '^[A-Z] AX[0-9]{4} ' "$f" 2>/dev/null | grep -vE '^[EWNH] ' || true)"
  if [[ -n "$bad" ]]; then
    printf '%s\n' "$bad" | sed 's/^/    /'
    return 1
  fi
  return 0
}

# gate_build_axc <varname> [output-path]
#
# Builds the compiler under test from the current `self_host/` sources
# and assigns its path to <varname>, defaulting to `$work/<varname>`.
#
# `$axiom` may be an older seed-descended binary that predates the
# change being tested. A gate whose subject is the compiler builds one
# from the tree first, which is what makes an ablation of `self_host/`
# visible to it.
#
# Ninety-five gates call this, so `$AXIOM_AXC` lets one CI step build
# the compiler once (`scripts/build-shared-axc.sh`). That cache is
# content-addressed: the binary is used only when `$AXIOM_AXC.stamp`
# equals `gate_source_stamp` for the tree as it is now. Change a byte
# the build reads and the stamp moves, so an ablation of `self_host/`
# stays visible with nothing to invalidate by hand.
#
# A stale stamp and an absent one mean different things:
#
#   stamp present and equal     -> reuse. The binary was built from
#                                  this tree by this builder.
#   stamp present and different -> build. The tree moved. `check-fmt.sh`
#                                  reaches this on every run, since it
#                                  runs its inner gates on a copy.
#   no stamp, no binary, or a
#   non-executable binary       -> refuse. A path that names no stamped
#                                  build product is a caller mistake,
#                                  and ignoring it would let a seed
#                                  compiler stand in, silently green.
#
# `scripts/check-gate-lib.sh` is the negative probe: it plants a
# builder that cannot build and asserts the cache is used when the
# stamp matches, not used when it differs, and refused when it is absent.
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
      local artifact_sha
      artifact_sha="$(gate_sha "$AXIOM_AXC")"
      cp "$AXIOM_AXC" "$out"
      # A producer may publish a new generation while this gate copies.
      # Check the private snapshot and inputs again before accepting it.
      if [[ "$(gate_sha "$out")" == "$artifact_sha" &&
            "$(gate_source_stamp)" == "$stamp" &&
            "$(cat "${AXIOM_AXC}.stamp")" == "$stamp" ]]; then
        echo "== reusing the compiler under test (source stamp ${stamp:0:12}) =="
        printf -v "$var" '%s' "$out"
        return 0
      fi
      rm -f "$out"
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

# gate_build_tree <builder> <root> <stdlib> <out> [build flag ...]
#
# Builds `<root>/self_host/main.ax` with <builder> into <out>, reading
# the standard library at <stdlib>: the compiler of an ablated tree,
# which is how most negative controls in this battery prove their gate
# can fail. The stdlib is an argument because call sites differ: some
# ablate a module in the copy and must read it, others build the copied
# `self_host/` against the gate's `$AXIOM_STDLIB`. <out> must be
# absolute.
#
# Results are cached, since the battery repeats many of these builds
# with unchanged inputs. The key hashes everything the result depends
# on: every `.ax` under `<root>/self_host` and in <stdlib> (paths and
# bytes, `gate_ax_tree_stamp`), the builder binary, the toolchain, the
# compiler-read environment and the flags. The tree's own directory is
# not an input: compilers built from two copies of one tree at
# different paths are byte-identical and name neither path. A one-byte
# ablation is a different key and a fresh build.
#
# Entries live in `$AXIOM_GATE_CACHE` (default
# `$repo_root/.axiom-shared/cache`). A completed build is published by
# `mv`, so no entry is ever visible half-written, and two gates racing
# on one key write identical bytes. Every hit is re-hashed against the
# digest stored beside it, so a damaged entry is rebuilt rather than
# trusted. `AXIOM_GATE_CACHE=off` disables the cache. `check-gate-lib.sh`
# tests the hit, the miss on a changed byte, builder or flags, and the
# damaged-entry rebuild.
gate_build_tree() {
  local builder="$1" root="$2" lib="$3" out="$4"; shift 4
  local cache key entry tmp rc=0
  cache="${AXIOM_GATE_CACHE:-$repo_root/.axiom-shared/cache}"
  if [[ "$cache" != off ]]; then
    key="$( {
      printf '%s\n' 'gate-tree-v1' "flags=$*"
      gate_ax_tree_stamp "$root" self_host
      gate_ax_tree_stamp "$lib" .
      gate_sha "$builder"
      gate_toolchain_stamp
      printf '%s\n' "AXIOM_PATH=${AXIOM_PATH:-}" \
        "AXIOM_LINK_SEARCH=${AXIOM_LINK_SEARCH:-}" \
        "AXIOM_MIR_EMIT=${AXIOM_MIR_EMIT:-}" \
        "AXIOM_VERIFY_SCOPES=${AXIOM_VERIFY_SCOPES:-}"
    } | gate_sha )"
    entry="$cache/tree-$key"
    if [[ -x "$entry" && -f "$entry.sha" ]]; then
      rm -f "$out"
      cp "$entry" "$out" && chmod +x "$out"
      if [[ "$(gate_sha "$out")" == "$(cat "$entry.sha")" ]]; then
        touch "$entry" 2>/dev/null || true   # recency, for run-gates.sh's pruning
        echo "== reusing the compiler of $root (tree key ${key:0:12}) =="
        return 0
      fi
      echo "== cached compiler tree-${key:0:12} does not match its digest; rebuilding =="
      rm -f "$out" "$entry" "$entry.sha"
    fi
  fi
  ( cd "$root" && AXIOM_STDLIB="$lib" "$builder" build --input self_host/main.ax --output "$out" "$@" ) || rc=$?
  (( rc == 0 )) || return "$rc"
  if [[ "$cache" != off ]] && mkdir -p "$cache" 2>/dev/null; then
    tmp="$(mktemp "$cache/.tmp.XXXXXX")" || return 0
    if cp "$out" "$tmp" && chmod +x "$tmp" && gate_sha "$tmp" > "$tmp.sha"; then
      mv -f "$tmp.sha" "$entry.sha" && mv -f "$tmp" "$entry"
    fi
    rm -f "$tmp" "$tmp.sha"
  fi
  return 0
}

# gate_timeout <seconds> <command ...>: run a command under a deadline,
# answering its own status, or 124 when the deadline killed it (GNU
# `timeout`'s contract). macOS ships no `timeout`, and Homebrew's
# `gtimeout` is not always installed. Calling `timeout` there fails with
# 127, which a gate would read as the program's own answer. The
# fallback is perl, which every runner and macOS install carries. A
# command killed by a signal answers 128+signal, as with `timeout`.
#
# Like GNU `timeout`, the fallback signals the whole process group. A
# program whose `parallel` bindings are forked children would otherwise
# leave them running after the kill, holding the `$(...)` pipe open, so
# the gate would hang instead of failing at its deadline. The child is
# made a group leader on both sides of the fork, so no signal can race
# it. The deadline sends TERM to the group and KILL a second later. An
# INT or TERM to this wrapper is passed on to the group, since the
# group is no longer the terminal's.
gate_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    perl -MPOSIX -e '
      my $t = shift; my $p = fork;
      die "fork: $!" unless defined $p;
      if ($p == 0) { POSIX::setpgid(0, 0); exec @ARGV; exit 127 }
      POSIX::setpgid($p, $p);
      $SIG{INT}  = sub { kill "INT",  -$p };
      $SIG{TERM} = sub { kill "TERM", -$p };
      $SIG{ALRM} = sub {
        kill "TERM", -$p; sleep 1; kill "KILL", -$p;
        waitpid($p, 0); exit 124
      };
      alarm $t; waitpid($p, 0);
      exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);
    ' "$secs" "$@"
  fi
}

# max_rss_kb <command ...>: the peak resident set of one run, in KiB.
#
# - `ru_maxrss` is bytes on Darwin and kilobytes on every other kernel,
#   FreeBSD included. FreeBSD's `time` also takes `-l`, so the divisor
#   is keyed on the kernel, never on which flag works.
# - Fail rather than skip when neither `time` answers, as
#   `measure-memory-baseline.sh` does. A measurement that silently
#   measures nothing hides a regression.
max_rss_kb() {
  local div=1
  [[ "$(uname -s)" == Darwin ]] && div=1024
  if /usr/bin/time -l true >/dev/null 2>&1; then
    /usr/bin/time -l "$@" 2>&1 >/dev/null \
      | awk -v div="$div" '/maximum resident set size/ {print int($1/div)}'
  elif /usr/bin/time -v true >/dev/null 2>&1; then
    /usr/bin/time -v "$@" 2>&1 >/dev/null \
      | awk -F: '/Maximum resident set size/ {print int($2)}'
  else
    echo "FAIL: no usable time(1) for RSS measurement" >&2
    return 1
  fi
}

# gate_ax_tree_stamp <dir> <subdir>: paths then bytes of every `.ax`
# under <dir>/<subdir>, relative to <dir>. It is
# `gate_seed_source_stamp`'s recipe for one directory, so a renamed or
# added-empty file moves it.
gate_ax_tree_stamp() {
  local list f
  list="$( cd "$1" && find "$2" -name '*.ax' -type f 2>/dev/null | LC_ALL=C sort )"
  {
    printf '%s\n' "$list"
    while IFS= read -r f; do
      [[ -n "$f" ]] && cat "$1/$f"
    done <<< "$list"
  } | gate_sha
}

# The prose documents that carry Axiom code and cite fixtures.
#
# Every prose sweep (`check-doc-drift.sh`, `check-tree-sitter.sh`,
# `check-tools-selfhost.sh` and others) reads this one list, so no
# document is swept by some gates and missed by others. It is
# hand-written, since a sweep cannot discover a document it was never
# told about. `check-doc-drift.sh` checks it in both directions: every
# name here exists, and every document under `docs/` is named here.
#
# `gate_prose_docs` prints them repo-relative. `gate_prose_docs_abs`
# fills the array `prose_docs` with `$repo_root` prefixed. It is a
# function rather than `mapfile` because the macOS runner ships bash
# 3.2, which has no `mapfile`.
#
# `gate_prose_docs_abs` checks every name before returning it. Its
# callers hand the list to Python, which opens what it is given, so a
# missing file would surface as a traceback and read as a broken gate.
# Here it is a one-line refusal naming this list.
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

# Why some entries are here:
#
# `docs/stdlib-api.md` is generated, and `check-stdlib-api.sh`
# regenerates and diffs the whole page. The sweeps add the two things a
# regeneration cannot see, because the generator would reproduce them
# faithfully: a link to a document that no longer exists, and a fixture
# path that no longer resolves.
#
# `CHANGELOG.md` becomes the release notes (`release.yml` passes it to
# `gh release create --notes-file`), so it is the first document a
# stranger reads.
#
# `bootstrap/README.md` and `bootstrap/THREATS.md` carry the tree's
# provenance claims. `check-seed-provenance.sh`, `check-seed-lineage.sh`
# and `check-seed-supply-chain.sh` gate the seed itself, and the last
# holds THREATS.md's rows to real gates. The sweeps hold both files'
# links, fixture paths and numerals.
gate_prose_docs() {
  cat <<'DOCS'
bootstrap/README.md
bootstrap/THREATS.md
README.md
CONTRIBUTING.md
CHANGELOG.md
SECURITY.md
docs/README.md
docs/reference.md
docs/stdlib.md
docs/diagnostics.md
docs/error-model.md
docs/ffi.md
docs/macro-system.md
docs/memory-model.md
docs/agent-harness.md
docs/compatibility.md
docs/lsp.md
docs/stdlib-api.md
docs/compiler-guide.md
docs/status.md
docs/embedded-guide.md
docs/restricted-profile.md
docs/assurance.md
docs/crypto.md
docs/obfuscation.md
docs/chrono.md
docs/axqlite.md
docs/axql.md
docs/axqlite-format.md
DOCS
}
