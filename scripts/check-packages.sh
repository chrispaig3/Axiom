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
#
# THE SECOND HALF, added 2026-08-31: a manifest line that means nothing
# is refused, and `name` is read. Measured on the 0.6.1 binary before
# either landed, three different mistakes produced one identical
# output - `error[AX5001]: cannot resolve import `Widget``, exit 1:
#
#     dependd vendor/lib          a misspelled key
#     depend                      a key with no value
#     depend<TAB>vendor/lib       a tab where the parser wanted a space
#
# In all three the manifest that caused it was never named, and in the
# third the file was not even wrong. Each now has a case below that
# asserts the LINE NUMBER as well as the text, because "somewhere in
# this file" is the diagnostic these replace. `name`, over the same
# binary, was parsed and read by nothing: `axiom build app.ax` in a
# project called `myapp` wrote `output`, like every other project on
# the machine. The two checks that pin its replacement are a pair on
# purpose - `myapp` exists AND `output` does not - because a build that
# wrote both would satisfy the first and have changed nothing.
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
echo "== the manifest's syntax: comments, blanks, and tabs =="
# --------------------------------------------------------------------
p5="$work/p5"
mkdir -p "$p5"
mod "$p5/vendor/lib" Widget 88
mod "$p5/other" Widget 99
app "$p5/app.ax" Widget
cat > "$p5/axiom.pkg" <<'EOF'
# a comment

name       syntax     # trailing comments too

depend     vendor/lib
EOF
got="$(run_app "$p5" app.ax)"
[[ "$got" == 88 ]] && ok "comments and blanks ignored ($got)" \
                   || bad "expected 88, got $got"

# A TAB between the key and its value. The split used to be
# `strStartsWith line "depend "` - one literal space - so this manifest
# declared nothing and the program reported `AX5001: cannot resolve
# import Widget` at exit 1, naming every directory it had searched and
# never the file that was meant to have added one. `printf` rather than
# a heredoc because the tab is the whole point and must be visible in
# the source of this gate.
printf 'name\tsyntax\ndepend\tvendor/lib\n' > "$p5/axiom.pkg"
got="$(run_app "$p5" app.ax)"
[[ "$got" == 88 ]] && ok "a TAB between key and value is a key and a value ($got)" \
                   || bad "expected 88 from a tab-separated manifest, got $got"

# --------------------------------------------------------------------
echo
echo "== a manifest line that means nothing is refused, at its line number =="
# --------------------------------------------------------------------
# The class this closes: three different mistakes all used to be read as
# silence, and all three reported as the SAME thing - the modules the
# line would have provided going missing, one at a time, against the
# import rather than against the manifest.
#
# Each case below asserts the LINE NUMBER as well as the text, because
# "somewhere in this file" is the diagnostic these replace.

# `dependency` is not `depend` and must not be read as one: if it were,
# `other/` would join the search path and this project would report a
# CLASH. So the refusal must name the unknown key and must not be the
# overlap message - that pair is what pins the prefix rule now that an
# unknown key is loud.
cat > "$p5/axiom.pkg" <<'EOF'
name       syntax

dependency other
depend     vendor/lib
EOF
set +e
out="$( cd "$p5" && "$axc" check app.ax 2>&1 )"
got=$?
set -e
if (( got == 3 )) \
   && printf '%s' "$out" | grep -q 'axiom.pkg:3: unknown key `dependency`' \
   && ! printf '%s' "$out" | grep -q 'two dependencies'; then
  ok "an unknown key is refused at exit 3, at its line, and is not read as \`depend\`"
else
  bad "the unknown key was not refused as expected (exit $got)"
  printf '%s\n' "$out" | sed 's/^/     /' | head -6
fi

# A key with no value. `depend` alone used to contribute nothing.
cat > "$p5/axiom.pkg" <<'EOF'
name       syntax
depend
depend     vendor/lib
EOF
set +e
out="$( cd "$p5" && "$axc" check app.ax 2>&1 )"
got=$?
set -e
if (( got == 3 )) && printf '%s' "$out" | grep -q 'axiom.pkg:2: `depend` has no value'; then
  ok "a key with no value is refused at exit 3, at its line"
else
  bad "a valueless key was not refused as expected (exit $got)"
  printf '%s\n' "$out" | sed 's/^/     /' | head -6
fi

# A second `name`. `pkgValue` answers the FIRST, so the second is a line
# the file contains and the compiler ignores - and now that `name` picks
# the executable's file name, silently ignoring one is silently writing
# to the other one's path.
cat > "$p5/axiom.pkg" <<'EOF'
name       one
name       two
depend     vendor/lib
EOF
set +e
out="$( cd "$p5" && "$axc" check app.ax 2>&1 )"
got=$?
set -e
if (( got == 3 )) && printf '%s' "$out" | grep -q 'axiom.pkg:2: `name` is given twice'; then
  ok "a second \`name\` is refused at exit 3, at its line"
else
  bad "a repeated \`name\` was not refused as expected (exit $got)"
  printf '%s\n' "$out" | sed 's/^/     /' | head -6
fi

# `version` too - a separate arm in `pkgCheckLines` with its own
# counter, so a gate that only checked `name` would leave half the rule
# unexercised.
cat > "$p5/axiom.pkg" <<'EOF'
name       syntax
version    0.1.0
version    0.2.0
depend     vendor/lib
EOF
set +e
out="$( cd "$p5" && "$axc" check app.ax 2>&1 )"
got=$?
set -e
if (( got == 3 )) && printf '%s' "$out" | grep -q 'axiom.pkg:3: `version` is given twice'; then
  ok "a second \`version\` is refused at exit 3, at its line"
else
  bad "a repeated \`version\` was not refused as expected (exit $got)"
  printf '%s\n' "$out" | sed 's/^/     /' | head -6
fi

# ...and `depend` is NOT one of those keys: repeating it is how a
# project declares two dependencies, so the check above must be about
# `name` and `version` and not about repetition.
cat > "$p5/axiom.pkg" <<'EOF'
name       two-deps
depend     vendor/lib
depend     other
EOF
rm -f "$p5/other/Widget.ax"
mod "$p5/other" Gadget 99
got="$(run_app "$p5" app.ax)"
[[ "$got" == 88 ]] && ok "two \`depend\` lines are still two dependencies ($got)" \
                   || bad "expected 88 with two depend lines, got $got"

# A `name` that is not a file name. It is spent as one by `build`
# below, so `../escaped` would write the executable to a path the
# command line never mentioned.
cat > "$p5/axiom.pkg" <<'EOF'
name       ../escaped
depend     vendor/lib
EOF
set +e
out="$( cd "$p5" && "$axc" check app.ax 2>&1 )"
got=$?
set -e
if (( got == 3 )) \
   && printf '%s' "$out" | grep -q 'axiom.pkg:1: `name` is not a package name' \
   && printf '%s' "$out" | grep -q '\.\./escaped'; then
  ok "a \`name\` that is a path is refused at exit 3, quoting it"
else
  bad "a path-shaped \`name\` was not refused as expected (exit $got)"
  printf '%s\n' "$out" | sed 's/^/     /' | head -6
fi

# --------------------------------------------------------------------
echo
echo "== \`name\` is what \`build\` writes when the command line is silent =="
# --------------------------------------------------------------------
# `name` was parsed, recorded and read by nothing, which made it
# indistinguishable from a key the compiler had never heard of - and
# made every project on the machine build to a file called `output`.
p7="$work/p7"
mkdir -p "$p7"
mod "$p7/vendor/lib" Widget 11
app "$p7/app.ax" Widget
cat > "$p7/axiom.pkg" <<'EOF'
name     myapp
version  0.1.0
depend   vendor/lib
EOF
set +e
out="$( cd "$p7" && "$axc" build app.ax 2>&1 )"
got=$?
set -e
if (( got == 0 )) && [[ -x "$p7/myapp" ]]; then
  ok "\`build\` with no --output wrote \`myapp\`, the manifest's name"
else
  bad "\`build\` did not write \`myapp\` (exit $got)"
  printf '%s\n' "$out" | sed 's/^/     /' | head -6
fi
# The negative half, and the reason this is two checks rather than one:
# a `build` that wrote BOTH files would satisfy the assertion above and
# have changed nothing.
[[ ! -e "$p7/output" ]] && ok "and did not write \`output\`" \
                        || bad "\`output\` was written too - the default did not move"
# The executable must be the PROGRAM, not merely a file of the right
# name: it exits with the dependency's answer.
set +e
( cd "$p7" && ./myapp ); got=$?
set -e
[[ "$got" == 11 ]] && ok "and running it answers 11, the dependency's module" \
                   || bad "./myapp exited $got, expected 11"

# The command line still wins, both spellings.
rm -f "$p7/myapp"
set +e
( cd "$p7" && "$axc" build app.ax --output chosen ) >/dev/null 2>&1
set -e
[[ -x "$p7/chosen" && ! -e "$p7/myapp" ]] \
  && ok "--output still wins over the manifest's name" \
  || bad "--output did not win over the manifest's name"
set +e
( cd "$p7" && "$axc" build app.ax -o shortform ) >/dev/null 2>&1
set -e
[[ -x "$p7/shortform" && ! -e "$p7/myapp" ]] \
  && ok "-o still wins over the manifest's name" \
  || bad "-o did not win over the manifest's name"

# The name is a FILE name in the WORKING DIRECTORY, not a path beside
# the manifest - the one sentence in the reference that a reader is
# most likely to assume the other way round. Built from the project
# root with the entry file in `src/`, the executable lands at the root
# beside `axiom.pkg`; built from inside `src/`, it lands in `src/`.
p9="$work/p9"
mkdir -p "$p9/src"
mod "$p9/vendor/lib" Widget 44
app "$p9/src/app.ax" Widget
cat > "$p9/axiom.pkg" <<'EOF'
name    nestedapp
depend  vendor/lib
EOF
set +e
( cd "$p9" && "$axc" build src/app.ax ) >/dev/null 2>&1
set -e
[[ -x "$p9/nestedapp" && ! -e "$p9/src/nestedapp" ]] \
  && ok "a parent manifest's name is written to the working directory" \
  || bad "expected \$p9/nestedapp from the project root and nothing in src/"
set +e
( cd "$p9/src" && "$axc" build app.ax ) >/dev/null 2>&1
set -e
[[ -x "$p9/src/nestedapp" ]] \
  && ok "...and to the working directory when that is \`src\`, not beside the manifest" \
  || bad "expected \$p9/src/nestedapp when built from src/"

# And a tree with no manifest is unchanged: `output`, as it always was.
# This is the check that stops the feature from being "every build is
# now named after something".
p8="$work/p8"
mkdir -p "$p8"
mod "$p8" Widget 7
app "$p8/app.ax" Widget
set +e
( cd "$p8" && "$axc" build app.ax ) >/dev/null 2>&1
got=$?
set -e
[[ "$got" == 0 && -x "$p8/output" ]] \
  && ok "with no manifest, \`build\` still writes \`output\`" \
  || bad "a manifest-less build did not write \`output\` (exit $got)"

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
echo "                its own directory still wins, two dependencies providing"
echo "                one module are refused rather than ordered, a line that"
echo "                means nothing is refused at its line number rather than"
echo "                ignored, and \`name\` is the file \`build\` writes"
