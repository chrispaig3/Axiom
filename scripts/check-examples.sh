#!/usr/bin/env bash
# Assert that examples/ holds sources and nothing built, that every
# program in it is named in examples/README.md and README.md points
# there, and that this script could tell if any of that stopped being
# true.
#
# WHAT THIS FILE WAS. Until 2026-09-04 it was `check-web.sh`: it built
# `examples/web/server.ax` - a templated server on `stdlib/Html.ax` and
# `stdlib/Http.ax` - served its pages and compared every response byte
# for byte against one written by hand, ran the same binary with the
# escaper bypassed and required the raw `<script>` back in both
# positions, built it against a library with the path check compiled
# out and required the planted file served, and held worker RSS flat
# across ten thousand page requests against the same binary unscoped
# (measured 106x, floor 20x). That day `stdlib/Html.ax` was deleted: a
# 938-line DSL of 118 public names that the compiler did not use and
# no other module imported, and `examples/web` was its one program. The
# web half of this gate went with them. `check-net.sh` still measures
# MM-ALLOC-22 - the request handler as an arena scope - over
# `tests/net/echo-server.ax`, and `tests/stdlib/430`-`432` exercise
# `Http.ax`'s parser, writer and router; what no gate measures any more
# is a page rendered per request and a traversal refused end to end
# over a socket. `git log -- scripts/check-web.sh` has the whole gate.
#
# WHAT SURVIVES is the half that was never about the web: the sweep of
# `examples/` itself, which `check-web.sh` carried only because it was
# the one thing CI pointed at that directory. That reason is gone and
# the sweep has a gate of its own, which is this file. It runs no Axiom
# program and builds no compiler - the precedent is
# `check-ci-coverage.sh`, which finds `$repo_root` itself for the same
# reason - so it is NOT among the gates that call `gate_build_axc`, and
# the count those gates state moved from sixty-six to sixty-five when
# it stopped being one.
#
# EVERY ASSERTION HERE HAS ITS ABLATION, and they are the point: a
# planted build artefact, an `.ax` tracked 100755, an empty file list,
# a program the table does not name, and a table row naming a program
# that is gone must each turn one arm red - one ablation per arm,
# because two arms sharing one ablation is one arm and a decoration.
# The ablations feed synthetic rows to the same functions the real
# checks call, rather than writing into the repository: a gate that
# plants a file in the tree it is checking can leave one behind when it
# is interrupted.

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || { echo "FAIL: no repository root at $repo_root" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

status=0

# ---------------------------------------------------------------
# examples/ HOLDS SOURCES, NOT BUILD OUTPUT.
#
# `axiom run` builds into the WORKING DIRECTORY - self_host/main.ax
# names the scratch executable `axiom_temp_output.<pid>` - and the
# `sysUnlink` that removes it is reached only after the child RETURNS.
# Reproduced 2026-09-03 against the web example this directory then
# held, the one program here that did not return on its own: `axiom
# run examples/web/server.ax 8961 1 1` from a scratch directory, then
# a SIGTERM to the runner, left `axiom_temp_output.99072`, mode 755, a
# 113,880-byte arm64 Mach-O. Only the executable - `buildToExecutable`
# removes its own `.ll`, `.o` and `.opt.ll`. That is the same shape as
# `examples/web/axiom_temp_output.92420`, a 156 KB arm64 Mach-O
# committed in d1e4a71, which sat in the tree until 2026-09-03 with
# every gate green - because no gate read the file LIST. They all read
# file CONTENTS, and a file nothing imports has no contents anyone
# reads. .gitignore names the pattern; this is what notices a build
# artefact committed past it, by any name.
#
# THE ALLOWED LIST IS DELIBERATELY IN ONE DIRECTION, and it is
# RE-DERIVED rather than inherited. It read `ax js css md` while
# `examples/web/static/` held a stylesheet and a script; with that
# example gone nothing under examples/ is a `.js` or a `.css`, and an
# allowance nothing uses is the permissive rot the next paragraph warns
# of. Adding a legitimate asset type - a .png for a page, a .json
# fixture - is a visible edit to `ex_allowed` below and to the table in
# examples/README.md, which is the property check-stdlib-api.sh's
# module list is written for: a list that rots silently in the
# permissive direction is worse than no list.
#
# TWO ARMS, and each has its own ablation because each catches a
# different thing. The extension arm catches a file with no extension
# or a foreign one (a stray executable, a core dump, a .o); the mode
# arm catches a file whose NAME is innocent and whose bit is not - an
# `axdoc.ax` chmod +x, which the extension arm would wave through.
# ---------------------------------------------------------------
ex_allowed="ax md"

# Reads `<mode> <path>` rows on stdin, one per tracked file, and
# answers 0 only if every one is a source or a static asset that is
# not executable. $1 is what to call the population in a message.
examples_hygiene() {
  local what="$1" bad=0 n=0 nax=0 mode path ext ok a
  while read -r mode path; do
    [[ -n "$path" ]] || continue
    n=$((n + 1))
    ext="${path##*.}"
    [[ "$ext" == "$path" ]] && ext=""
    case "$path" in *.ax) nax=$((nax + 1)) ;; esac
    ok=0
    for a in $ex_allowed; do [[ "$ext" == "$a" ]] && ok=1; done
    if (( ok == 0 )); then
      echo "     $what: $path is neither a source nor a static asset (allowed: $ex_allowed)"
      bad=$((bad + 1))
      continue
    fi
    if [[ "$mode" != "100644" ]]; then
      echo "     $what: $path is tracked with mode $mode - an example's sources are not executables"
      bad=$((bad + 1))
    fi
  done
  # The population floor. Without it this function answers 0 for an
  # empty stream, which is what it would read if the file list were
  # ever produced from the wrong path - a check that passes because
  # it looked at nothing.
  #
  # SET AT THE MEASURED VALUE, with the date: 3 tracked files and 2
  # programs on 2026-09-04, after the web example's three files left.
  # It read `n < 4 || nax < 3` against six files and three programs,
  # so a deleted example moves this line in the same commit - which is
  # what "re-derive rather than relax" means, and the direction the
  # floor is meant to be wrong in.
  if (( n < 3 || nax < 2 )); then
    echo "     $what: read $n tracked files and $nax programs, which is fewer than examples/ has"
    bad=$((bad + 1))
  fi
  return $(( bad > 0 ? 1 : 0 ))
}

echo "== examples/ holds sources and static assets, and no build output =="
ex_rows="$work/examples.rows"
# `$4` is the path, so a path containing a space arrives truncated. That
# fails LOUD rather than quiet - the truncated name has the wrong
# extension and the arm above refuses it - which is the direction this
# gate wants to be wrong in.
git ls-files -s examples/ | awk '{print $1, $4}' > "$ex_rows"
ex_n="$(wc -l < "$ex_rows" | tr -d ' ')"
if examples_hygiene "examples/" < "$ex_rows"; then
  echo "ok   $ex_n tracked files under examples/, all sources or static assets, none executable"
else
  echo "FAIL: examples/ holds a file that is not part of an example's source."
  echo '      `axiom run` writes axiom_temp_output.<pid> into the working directory;'
  echo "      if that is what this is, delete it - .gitignore names the pattern."
  status=1
fi

echo "== ablation: the sweep must go red on a planted artefact and on a set bit =="
# The planted artefact keeps the name of the one that was really
# committed, under the directory it was committed to; the directory
# is gone and the row is synthetic, so that costs nothing and keeps the
# record.
{ cat "$ex_rows"; echo "100755 examples/web/axiom_temp_output.92420"; } > "$work/examples.abl1"
{ cat "$ex_rows"; echo "100755 examples/axdoc/axdoc-copy.ax"; } > "$work/examples.abl2"
if examples_hygiene "abl-extension" < "$work/examples.abl1" >/dev/null 2>&1; then
  echo "FAIL negative probe: the sweep accepted a committed axiom_temp_output.<pid>,"
  echo "     so its green above is green about nothing"
  status=1
else
  echo "ok   negative probe: a committed build artefact is refused by the extension arm"
fi
if examples_hygiene "abl-mode" < "$work/examples.abl2" >/dev/null 2>&1; then
  echo "FAIL negative probe: the sweep accepted an executable .ax, so the mode arm"
  echo "     is being carried by the extension arm and catches nothing of its own"
  status=1
else
  echo "ok   negative probe: an .ax tracked 100755 is refused by the mode arm"
fi
if examples_hygiene "abl-empty" < /dev/null >/dev/null 2>&1; then
  echo "FAIL negative probe: the sweep passed on an empty population, so a"
  echo "     mistyped path would read nothing and answer green"
  status=1
else
  echo "ok   negative probe: an empty file list is refused, so the green arm read something"
fi

# ---------------------------------------------------------------
# AND EVERY PROGRAM IS DOCUMENTED. A directory of examples nobody can
# find is a directory of dead files: before 2026-09-03 there was no
# examples/README.md and README.md contained no occurrence of the
# string `examples`, so the programs here were reachable only by `ls`.
# Two directions, because a table checked one way rots the other - the
# same rule the module list in check-stdlib-api.sh carries:
#
#   - every `.ax` tracked under examples/ is named in
#     examples/README.md, so a new program cannot land undocumented;
#   - every `examples/…​.ax` path the table names is in the tree, so a
#     deleted program cannot leave a row pointing at nothing.
#
# The top-level README.md must link to it, which is the whole reason
# any of this is discoverable.
#
# The ablation for each direction is a synthetic pair fed to the same
# function: a program absent from the table, and a table row naming a
# program that does not exist.
# ---------------------------------------------------------------

# $1 what to call the population; $2 a file of `.ax` paths; $3 the
# document that must name each of them.
examples_documented() {
  local what="$1" progs="$2" doc="$3" bad=0 n=0 p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    n=$((n + 1))
    grep -qF -- "$p" "$doc" || {
      echo "     $what: $p is not named in $doc"
      bad=$((bad + 1))
    }
  done < "$progs"
  # Back the other way: a row naming a program that is gone.
  while IFS= read -r p; do
    [[ -e "$repo_root/$p" ]] || {
      echo "     $what: $doc names $p, which is not in the tree"
      bad=$((bad + 1))
    }
  done < <(grep -oE 'examples/[A-Za-z0-9_./-]+\.ax' "$doc" | LC_ALL=C sort -u)
  # The population floor, at the measured value with the date: 2
  # programs on 2026-09-04 (it read `n < 3` against three).
  if (( n < 2 )); then
    echo "     $what: read $n programs, which is fewer than examples/ has"
    bad=$((bad + 1))
  fi
  return $(( bad > 0 ? 1 : 0 ))
}

echo "== every example is named in examples/README.md, and README.md points there =="
ex_progs="$work/examples.progs"
awk '$2 ~ /\.ax$/ {print $2}' "$ex_rows" > "$ex_progs"
if [[ ! -f "$repo_root/examples/README.md" ]]; then
  echo "FAIL: examples/README.md does not exist - the programs are reachable only by ls"
  status=1
elif examples_documented "examples/" "$ex_progs" "$repo_root/examples/README.md"; then
  echo "ok   $(wc -l < "$ex_progs" | tr -d ' ') programs, each named in examples/README.md, and no row names a program that is gone"
else
  echo "FAIL: examples/README.md and examples/ have drifted apart"
  status=1
fi
if grep -q 'examples/README.md' "$repo_root/README.md"; then
  echo "ok   README.md links to examples/README.md"
else
  echo "FAIL: README.md does not mention examples/ - it did not, for the whole of"
  echo "      this project's history before 2026-09-03, and that is how the"
  echo "      directory came to hold a committed build artefact nobody saw"
  status=1
fi

echo "== ablation: the documentation check must go red both ways =="
{ cat "$ex_progs"; echo "examples/undocumented/undocumented.ax"; } > "$work/examples.abl3"
{ cat "$repo_root/examples/README.md"; echo "see examples/gone/gone.ax"; } > "$work/examples.abl4"
if examples_documented "abl-undocumented" "$work/examples.abl3" "$repo_root/examples/README.md" >/dev/null 2>&1; then
  echo "FAIL negative probe: an example missing from the table was accepted"
  status=1
else
  echo "ok   negative probe: a program the table does not name is refused"
fi
if examples_documented "abl-dangling" "$ex_progs" "$work/examples.abl4" >/dev/null 2>&1; then
  echo "FAIL negative probe: a table row naming a program that does not exist was accepted"
  status=1
else
  echo "ok   negative probe: a row naming a program that is gone is refused"
fi

if (( status == 0 )); then
  echo
  echo "check-examples: examples/ holds sources and nothing built, every"
  echo "                program in it is named in examples/README.md and"
  echo "                README.md points there, and every one of those"
  echo "                claims has an ablation that goes red"
fi
exit "$status"
