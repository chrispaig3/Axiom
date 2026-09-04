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
#
# EVERY TEXT ASSERTION IS `grep -q PATTERN <<<"$out"`, never
# `printf '%s' "$out" | grep -q PATTERN`, and the difference is a real
# flake rather than a style: `grep -q` exits the moment it matches, so
# `printf` on the other end of the pipe takes SIGPIPE and answers 141,
# and `set -o pipefail` above makes 141 the PIPELINE's status - so a
# refusal that was correct reports as a failure, and only once the
# message is long enough for printf to still be writing. Measured
# 2026-09-03: the crate/depend clash below failed with
# `printf: write error: Broken pipe` printed above a FAIL whose own
# output, quoted underneath it, contained every string the greps were
# looking for. A here-string has no second process and cannot do this.
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

# A CRATE directory, as `crate` defines one: a `Cargo.toml` beside an
# `axiom/` holding the generated binding module.
#
# NO `src/`, NO ARCHIVE AND NO CARGO. Everything this gate asserts
# about `crate` other than the one ablation at the end is true of a
# crate that has never been built, which is what keeps `check-packages`
# in the parallel, cargo-free set - `check-ffi.sh` owns the half where
# a real archive is linked.
crate_dir() {  # <dir> <cargo-name> <module> <n>
  mkdir -p "$1/axiom"
  cat > "$1/Cargo.toml" <<EOF
[package]
name = "$2"
version = "0.1.0"
EOF
  mod "$1/axiom" "$3" "$4"
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
   && grep -q 'two dependencies' <<<"$out" \
   && grep -q 'a/Widget.ax' <<<"$out" \
   && grep -q 'b/Widget.ax' <<<"$out" \
   && grep -q 'axiom.pkg' <<<"$out"; then
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
if (( got == 3 )) && grep -q 'vendor/nowhere' <<<"$out"; then
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
   && grep -q 'axiom.pkg:3: unknown key `dependency`' <<<"$out" \
   && ! grep -q 'two dependencies' <<<"$out"; then
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
if (( got == 3 )) && grep -q 'axiom.pkg:2: `depend` has no value' <<<"$out"; then
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
if (( got == 3 )) && grep -q 'axiom.pkg:2: `name` is given twice' <<<"$out"; then
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
if (( got == 3 )) && grep -q 'axiom.pkg:3: `version` is given twice' <<<"$out"; then
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
   && grep -q 'axiom.pkg:1: `name` is not a package name' <<<"$out" \
   && grep -q '\.\./escaped' <<<"$out"; then
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
echo "== \`crate\` declares a NATIVE dependency, and the manifest is what finds it =="
# --------------------------------------------------------------------
# THE GAP THIS CLOSES, measured on 0.7.3 before it did. One source
# tree, one `libaxiom_greeter.a` already on disk, two ways of saying
# so: `AXIOM_PATH=vendor/greeter/axiom axiom build app.ax` exited 0 and
# the program ran; `depend vendor/greeter/axiom` in `axiom.pkg` exited
# 4 with `error[AX4004]: no archive is linked`. The environment could
# describe the project and the project could not, which is the exact
# inversion of what a manifest is for.
#
# The module half is checked HERE, with no cargo and no archive,
# because a crate's `axiom/` module joining the search path is the
# property that has to hold on every machine. `check-ffi.sh` owns the
# archive half.
pc="$work/pc"
mkdir -p "$pc"
crate_dir "$pc/vendor/greeter" axiom-greeter Greeter 42
app "$pc/app.ax" Greeter
cat > "$pc/axiom.pkg" <<'EOF'
name   native
crate  vendor/greeter
EOF
got="$(run_app "$pc" app.ax)"
[[ "$got" == 42 ]] && ok "the crate's generated module answered ($got)" \
                   || bad "expected 42 from vendor/greeter/axiom/Greeter.ax, got $got"

# THE NEGATIVE PROBE, the same shape as the one the whole mechanism
# has at the top: with the manifest gone and nothing else changed, the
# module must stop resolving. Without it this section would pass if
# anything at all - a stray `AXIOM_PATH`, the entry directory - were
# what found `Greeter`.
mv "$pc/axiom.pkg" "$pc/axiom.pkg.off"
got="$(run_app "$pc" app.ax)"
[[ "$got" != 42 ]] && ok "without the manifest the crate's module is not found ($got)" \
                   || bad "the program still answered 42 with no manifest - \`crate\` is not what resolved it"
mv "$pc/axiom.pkg.off" "$pc/axiom.pkg"

# --------------------------------------------------------------------
echo
echo "== a \`crate\` that is not a crate is refused =="
# --------------------------------------------------------------------
# Three refusals, and the middle one is what makes `crate` mean crate
# rather than be a second spelling of `depend`.
crate_case() {  # <manifest-value> <needle> <what>
  cat > "$pc/axiom.pkg" <<EOF
name   native
crate  $1
EOF
  set +e
  local out rc
  out="$( cd "$pc" && "$axc" check app.ax 2>&1 )"
  rc=$?
  set -e
  if (( rc == 3 )) && grep -q "$2" <<<"$out"; then
    ok "$3 is refused at exit 3, naming it"
  else
    bad "$3 was not refused as expected (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/     /' | head -6
  fi
}
crate_case vendor/nowhere 'vendor/nowhere' "a crate directory that is not there"

# A directory of modules with no `Cargo.toml`. If `crate` accepted it,
# `crate` and `depend` would be two names for one key and the manifest
# would have stopped saying which kind of dependency this is.
mkdir -p "$pc/vendor/plain/axiom"
crate_case vendor/plain 'Cargo.toml' "a crate directory with no Cargo.toml"

# `DIR/axiom/` is written by `axiom-bindgen`, and a manifest `crate`
# does not run it - so the refusal has to say what to run.
mkdir -p "$pc/vendor/nobind"
printf '[package]\nname = "axiom-nobind"\n' > "$pc/vendor/nobind/Cargo.toml"
crate_case vendor/nobind 'axiom/' "a crate with no generated module directory"

# --------------------------------------------------------------------
echo
echo "== a crate and a \`depend\` may not provide one module =="
# --------------------------------------------------------------------
# The headline property is about the SEARCH PATH, not about which key
# put a directory on it: both land in one list and the loser's modules
# would compile against a package they never named either way.
mod "$pc/local" Greeter 77
cat > "$pc/axiom.pkg" <<'EOF'
name   native
depend local
crate  vendor/greeter
EOF
set +e
out="$( cd "$pc" && "$axc" check app.ax 2>&1 )"
got=$?
set -e
if (( got == 3 )) \
   && grep -q 'two dependencies' <<<"$out" \
   && grep -q 'local/Greeter.ax' <<<"$out" \
   && grep -q 'vendor/greeter/axiom/Greeter.ax' <<<"$out"; then
  ok "a crate clashing with a \`depend\` is refused at exit 3, naming both"
else
  bad "the crate/depend clash was not refused as expected (exit $got)"
  printf '%s\n' "$out" | sed 's/^/     /' | head -8
fi
# ...and with the clash gone it builds, so this is about the CLASH.
rm -f "$pc/local/Greeter.ax"
mod "$pc/local" Gadget 88
got="$(run_app "$pc" app.ax)"
[[ "$got" == 42 ]] && ok "with the clash removed the crate's module answers again ($got)" \
                   || bad "expected 42 once the clash was gone, got $got"

# --------------------------------------------------------------------
echo
echo "== a dependency may not provide a standard-library module =="
# --------------------------------------------------------------------
# MEASURED ON 0.7.3, and it is the reason this section exists rather
# than a hazard someone imagined: a `depend` directory holding a copy
# of `stdlib/Fmt.ax` whose `fmtInt` answered `"HIJACKED"` made the
# program print HIJACKED, at exit 0, with no diagnostic. `depend` sits
# ABOVE the library in the search order, so the replacement was for the
# WHOLE program - every module that imports `Fmt`, not only the one
# that wanted the dependency. A package manager that ships that is a
# supply-chain surface wearing a search path.
ps="$work/ps"
mkdir -p "$ps"
mod "$ps/vendor/lib" Fmt 91
app "$ps/app.ax" Fmt
cat > "$ps/axiom.pkg" <<'EOF'
name   shadowing
depend vendor/lib
EOF
set +e
out="$( cd "$ps" && "$axc" check app.ax 2>&1 )"
got=$?
set -e
if (( got == 3 )) \
   && grep -q "standard library's module \`Fmt\`" <<<"$out" \
   && grep -q 'vendor/lib/Fmt.ax' <<<"$out" \
   && grep -q 'stdlib/Fmt.ax' <<<"$out"; then
  ok "a dependency's \`Fmt.ax\` is refused at exit 3, naming both files"
else
  bad "the standard-library shadow was not refused as expected (exit $got)"
  printf '%s\n' "$out" | sed 's/^/     /' | head -8
fi

# THE ABLATION, and it is the one that matters: the SAME file in the
# ENTRY FILE's own directory must still build and still shadow.
# docs/reference.md documents that as intended - it is how a project
# overrides a library module - and a refusal that caught both would be
# a refusal that broke a feature rather than closed a hole.
rm -rf "$ps/vendor" "$ps/axiom.pkg"
mod "$ps" Fmt 91
got="$(run_app "$ps" app.ax)"
[[ "$got" == 91 ]] && ok "the same module in the ENTRY directory still shadows the library ($got)" \
                   || bad "an entry-directory Fmt.ax stopped working - the refusal caught the wrong thing (got $got)"

# --------------------------------------------------------------------
echo
echo "== two dependencies may not provide one NESTED module =="
# --------------------------------------------------------------------
# THE HEADLINE PROPERTY WAS TOP-LEVEL ONLY, measured on 0.7.3: two
# `depend` directories each holding `Sub/Widget.ax` - the file
# `(import Sub.Widget)` resolves to - built and exited 55, first-wins
# and silent. `pkgFirstShared` did one `sysReadDir` and never
# descended, and this gate could not see it either, because the `mod`
# helper above only ever wrote TOP-LEVEL modules. A fixture that cannot
# express the failure is a gate that cannot fail.
pn="$work/pn"
mkdir -p "$pn"
mod "$pn/a/Sub" Widget 55
mod "$pn/b/Sub" Widget 66
app "$pn/app.ax" Sub.Widget
cat > "$pn/axiom.pkg" <<'EOF'
name   nestedclash
depend a
depend b
EOF
set +e
out="$( cd "$pn" && "$axc" run app.ax 2>&1 )"
got=$?
set -e
if (( got == 3 )) \
   && grep -q 'provide the module `Sub.Widget`' <<<"$out" \
   && grep -q 'a/Sub/Widget.ax' <<<"$out" \
   && grep -q 'b/Sub/Widget.ax' <<<"$out"; then
  ok "a nested clash is refused at exit 3, by the DOTTED name an import spells"
else
  bad "the nested clash was not refused as expected (exit $got)"
  printf '%s\n' "$out" | sed 's/^/     /' | head -8
fi
# ABLATION: with one of the two gone the project builds and exits with
# the survivor's number - so the refusal is about the CLASH and not
# about nesting, which is what it did before and must keep doing.
rm -f "$pn/b/Sub/Widget.ax"
got="$(run_app "$pn" app.ax)"
[[ "$got" == 55 ]] && ok "with one removed the nested module resolves normally ($got)" \
                   || bad "expected 55 from the surviving nested module, got $got"

# --------------------------------------------------------------------
echo
echo "== a manifest \`crate\` NEVER runs cargo =="
# --------------------------------------------------------------------
# THE LOAD-BEARING ABLATION for the one decision this key is built
# around. `--crate DIR` on the command line DOES spawn cargo - measured
# on 0.7.3 against a crate with no `target/`: `axiom build app.ax
# --crate mycrate` printed `axiom: building crate ... with cargo (no
# archive found)`, cargo ran, and `mycrate/target/` appeared. A command
# line is a person asking. `axiom.pkg` is a checked-in file that
# arrives with a clone, and docs/reference.md says the compiler
# executes no code from a source file - so the manifest must not.
#
# The check is a PAIR, and neither half means anything alone: the
# manifest build must leave `target/` absent, AND the identical
# directory passed as `--crate` must create it. Without the second
# half, a fixture cargo could never have built would pass.
if ! command -v cargo > /dev/null 2>&1; then
  echo "skip: cargo not on PATH - the no-execution ablation needs it for its"
  echo "      POSITIVE control (\`--crate\` must create target/). The half that"
  echo "      matters is unchecked here on this machine."
else
  pf="$work/pf"
  mkdir -p "$pf/fresh/src" "$pf/fresh/axiom"
  cat > "$pf/fresh/Cargo.toml" <<'EOF'
[package]
name = "axiom-fresh"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["staticlib"]

[workspace]
EOF
  cat > "$pf/fresh/src/lib.rs" <<'EOF'
#[no_mangle]
pub extern "C" fn axffi_fresh_answer(bump: i64) -> i64 { 41 + bump }
EOF
  mod "$pf/fresh/axiom" Fresh 1
  cat > "$pf/app.ax" <<'EOF'
(pub extern "axiom_fresh"
  (freshAnswer :: (-> Int Int) (symbol "axffi_fresh_answer")))

;@axiom:effect(io)
(:: main Int)

(fn (main) (freshAnswer 1))
EOF
  cat > "$pf/axiom.pkg" <<'EOF'
name  fresh
crate fresh
EOF
  set +e
  out="$( cd "$pf" && "$axc" build app.ax --output prog 2>&1 )"
  got=$?
  set -e
  if (( got != 0 )) && grep -q 'AX4004' <<<"$out" && [[ ! -e "$pf/prog" ]]; then
    ok "an unbuilt manifest crate is AX4004 and writes no executable (exit $got)"
  else
    bad "an unbuilt manifest crate did not refuse as expected (exit $got)"
    printf '%s\n' "$out" | sed 's/^/     /' | head -6
  fi
  [[ ! -e "$pf/fresh/target" ]] \
    && ok "...and fresh/target does not exist: the manifest ran no build system" \
    || bad "fresh/target was created from a MANIFEST line - the compiler executed another project's build system"

  # THE POSITIVE CONTROL. Same directory, same compiler, one flag.
  set +e
  ( cd "$pf" && "$axc" build app.ax --output prog2 --crate fresh ) >"$work/pf.log" 2>&1
  got=$?
  set -e
  if (( got == 0 )) && [[ -d "$pf/fresh/target" ]]; then
    ok "\`--crate\` on the SAME directory does run cargo and creates fresh/target"
  else
    bad "--crate did not build the crate (exit $got) - the ablation above proves nothing"
    sed 's/^/     /' "$work/pf.log" | head -6
  fi
  set +e
  ( cd "$pf" && ./prog2 ); got=$?
  set -e
  [[ "$got" == 42 ]] && ok "and the program it built answers 42 through the archive" \
                     || bad "./prog2 exited $got, expected 42"

  # ...and NOW the manifest alone is enough, because the archive is
  # there. This is the sentence the design owes its users: you build
  # the crate once, and the manifest carries it from then on.
  set +e
  ( cd "$pf" && "$axc" build app.ax --output prog3 ) >"$work/pf3.log" 2>&1
  got=$?
  set -e
  if (( got == 0 )); then
    set +e
    ( cd "$pf" && ./prog3 ); got=$?
    set -e
    [[ "$got" == 42 ]] && ok "with the archive built, the manifest alone links and runs it (42)" \
                       || bad "./prog3 exited $got, expected 42"
  else
    bad "the manifest alone did not build once the archive existed (exit $got)"
    sed 's/^/     /' "$work/pf3.log" | head -6
  fi
fi

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
echo "                including a native one with \`crate\`; its own directory"
echo "                still wins; two dependencies providing one module are"
echo "                refused rather than ordered, nested ones included, and so"
echo "                is one that would displace a standard-library module; a"
echo "                line that means nothing is refused at its line number"
echo "                rather than ignored; \`name\` is the file \`build\` writes;"
echo "                and a manifest \`crate\` runs no build system, where the"
echo "                command-line \`--crate\` beside it does"
