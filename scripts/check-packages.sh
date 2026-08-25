#!/usr/bin/env bash
# `axiom.pkg`: a project says what it depends on, and two dependencies
# may not provide one module.
#
# WHAT A DEPENDENCY WAS BEFORE THIS. A directory on `$AXIOM_PATH`. That
# is a real mechanism and it stays, but nothing recorded what a program
# depended on: the list lived in whoever's shell was running the
# compiler, it did not travel with the source, and two directories
# providing a module of the same name resolved first-wins by
# environment order - silently, with the loser's modules compiled
# against declarations from a package they had never named. That is the
# value-namespace twin of the type collision `AX3044` closed on
# 2026-08-24, and it had the same failure mode: a wrong answer at exit
# 0.
#
# EVERY PROJECT HERE IS BUILT BY THIS SCRIPT, in `$work`, rather than
# checked in under `tests/`. A package fixture is a directory TREE -
# a manifest, two or three module directories, an entry file - and the
# thing a reader needs is the shape, which is legible here and would be
# spread over eight files there. It also keeps `tests/` free of `.ax`
# files that exist to be found by a search path rather than compiled by
# a sweep.
#
# HOW EACH POSITIVE CASE IS READ. Every module answers a distinct
# number and the program exits with it, so the EXIT STATUS says which
# file the resolver chose. A gate that only asserted "it built" would
# pass on the wrong module being found, which is the entire failure
# this exists to catch.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# A module answering `n`, in `dir`, called `name`.
mod() {  # <dir> <name> <n>
  mkdir -p "$1"
  cat > "$1/$2.ax" <<EOF
(pub :: answer Int)

(pub fn (answer) $3)
EOF
}

# An entry file importing `name` and exiting with its answer.
app() {  # <path> <name>
  cat > "$1" <<EOF
(import $2)

(:: main Int)

(fn (main) answer)
EOF
}

run_app() {  # <cwd> <entry> -> prints exit status
  local d="$1" f="$2" rc
  set +e
  ( cd "$d" && "$axc" run "$f" ) >/dev/null 2>&1
  rc=$?
  set -e
  printf '%s' "$rc"
}

# --------------------------------------------------------------------
echo "== a declared dependency is found, and the manifest is what finds it =="
# --------------------------------------------------------------------
p="$work/p1"
mkdir -p "$p"
mod "$p/vendor/lib" Widget 11
app "$p/app.ax" Widget
cat > "$p/axiom.pkg" <<'EOF'
# a project that depends on one directory of modules
name     probe
version  0.1.0

depend   vendor/lib
EOF
got="$(run_app "$p" app.ax)"
[[ "$got" == 11 ]] && ok "the dependency's module answered ($got)" \
                   || bad "expected 11 from vendor/lib/Widget.ax, got $got"

# THE NEGATIVE PROBE for the whole mechanism: with the manifest gone
# and nothing else changed, the same program must fail to resolve. If
# it still built, something other than `axiom.pkg` was finding the
# module and every assertion above is measuring that instead.
mv "$p/axiom.pkg" "$p/axiom.pkg.off"
got="$(run_app "$p" app.ax)"
[[ "$got" != 11 ]] && ok "without the manifest the same program fails ($got)" \
                   || bad "the program still answered 11 with no manifest - the manifest is not what resolved it"
mv "$p/axiom.pkg.off" "$p/axiom.pkg"

# --------------------------------------------------------------------
echo
echo "== the entry file's own directory still wins =="
# --------------------------------------------------------------------
# A project must be able to shadow a dependency's module with its own,
# which is the rule the standard library has always had and the reason
# `depend` sits AFTER the entry directory in the search order.
mod "$p" Widget 22
got="$(run_app "$p" app.ax)"
[[ "$got" == 22 ]] && ok "a sibling module shadows the dependency ($got)" \
                   || bad "expected 22 from the entry directory, got $got"
rm -f "$p/Widget.ax"

# --------------------------------------------------------------------
echo
echo "== a declared dependency outranks \$AXIOM_PATH =="
# --------------------------------------------------------------------
# The manifest travels with the source; the variable travels with the
# shell. When both can answer, the one the project wrote down wins.
mod "$work/loose" Widget 33
set +e
( cd "$p" && AXIOM_PATH="$work/loose" "$axc" run app.ax ) >/dev/null 2>&1
got=$?
set -e
[[ "$got" == 11 ]] && ok "the manifest's dependency beat \$AXIOM_PATH ($got)" \
                   || bad "expected 11 from the declared dependency, got $got"

# --------------------------------------------------------------------
echo
echo "== the manifest is found from a parent directory =="
# --------------------------------------------------------------------
p2="$work/p2"
mkdir -p "$p2/src"
mod "$p2/vendor/lib" Widget 44
app "$p2/src/app.ax" Widget
cat > "$p2/axiom.pkg" <<'EOF'
name    nested
depend  vendor/lib
EOF
got="$(run_app "$p2" src/app.ax)"
[[ "$got" == 44 ]] && ok "a manifest one directory up was found ($got)" \
                   || bad "expected 44 with the manifest at the project root, got $got"

# --------------------------------------------------------------------
echo
echo "== two dependencies providing one module are refused =="
# --------------------------------------------------------------------
# The headline property. Before this, whichever directory came first
# won and nothing said the other existed.
p3="$work/p3"
mkdir -p "$p3"
mod "$p3/a" Widget 55
mod "$p3/b" Widget 66
app "$p3/app.ax" Widget
cat > "$p3/axiom.pkg" <<'EOF'
name    clashing
depend  a
depend  b
EOF
set +e
out="$( cd "$p3" && "$axc" run app.ax 2>&1 )"
got=$?
set -e
if (( got == 3 )) \
   && printf '%s' "$out" | grep -q 'two dependencies' \
   && printf '%s' "$out" | grep -q 'a/Widget.ax' \
   && printf '%s' "$out" | grep -q 'b/Widget.ax' \
   && printf '%s' "$out" | grep -q 'axiom.pkg'; then
  ok "refused at exit 3, naming both files and the manifest"
else
  bad "the clash was not refused as expected (exit $got)"
  printf '%s\n' "$out" | sed 's/^/     /' | head -8
fi
# It must be refused by `check` too, not only by `run`: a project that
# type-checks and cannot be built is a project whose editor says it is
# fine.
set +e
( cd "$p3" && "$axc" check app.ax ) >/dev/null 2>&1
got=$?
set -e
[[ "$got" == 3 ]] && ok "\`check\` refuses it too ($got)" \
                  || bad "\`check\` exited $got, expected 3"
# ...and with one of the two removed it builds, so the refusal is about
# the CLASH and not about the manifest having two `depend` lines.
rm -f "$p3/b/Widget.ax"
mod "$p3/b" Gadget 77
got="$(run_app "$p3" app.ax)"
[[ "$got" == 55 ]] && ok "with the clash removed the same project builds ($got)" \
                   || bad "expected 55 once the clash was gone, got $got"

# --------------------------------------------------------------------
echo
echo "== a dependency directory that is not there is refused =="
# --------------------------------------------------------------------
p4="$work/p4"
mkdir -p "$p4"
app "$p4/app.ax" Widget
cat > "$p4/axiom.pkg" <<'EOF'
name    missing
depend  vendor/nowhere
EOF
set +e
out="$( cd "$p4" && "$axc" check app.ax 2>&1 )"
got=$?
set -e
if (( got == 3 )) && printf '%s' "$out" | grep -q 'vendor/nowhere'; then
  ok "a missing dependency directory is refused at exit 3, by name"
else
  bad "a missing dependency directory exited $got"
  printf '%s\n' "$out" | sed 's/^/     /' | head -6
fi

# --------------------------------------------------------------------
echo
echo "== the manifest's syntax: comments, blanks, and a key that is not a key =="
# --------------------------------------------------------------------
p5="$work/p5"
mkdir -p "$p5"
mod "$p5/vendor/lib" Widget 88
mod "$p5/other" Widget 99
app "$p5/app.ax" Widget
cat > "$p5/axiom.pkg" <<'EOF'
# a comment

name       syntax     # trailing comments too

# `dependency` is not `depend`, and must not be read as one - if it
# were, `other/` would join the search path and this project would
# have a clash rather than an answer.
dependency other

depend     vendor/lib
EOF
got="$(run_app "$p5" app.ax)"
[[ "$got" == 88 ]] && ok "comments and blanks ignored, \`dependency\` is not \`depend\` ($got)" \
                   || bad "expected 88, got $got"

# --------------------------------------------------------------------
echo
echo "== a project with no manifest is unaffected =="
# --------------------------------------------------------------------
# Every gate in this repository compiles without one, so this is the
# case that must not have changed. It is asserted rather than assumed
# because the manifest walk runs on every module lookup.
p6="$work/p6"
mkdir -p "$p6"
mod "$p6" Widget 7
app "$p6/app.ax" Widget
got="$(run_app "$p6" app.ax)"
[[ "$got" == 7 ]] && ok "no manifest, sibling module, still resolves ($got)" \
                  || bad "expected 7 with no manifest at all, got $got"

echo
if (( failed > 0 )); then
  echo "check-packages: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-packages: $checks checks - a project declares its dependencies,"
echo "                its own directory still wins, and two dependencies"
echo "                providing one module are refused rather than ordered"
