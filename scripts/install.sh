#!/usr/bin/env bash
# Install a released Axiom without cloning the repository.
#
# Until this file the only documented way to get a compiler was to clone
# the whole repository and run a four-stage bootstrap - four full
# compiler builds, and `cargo` and Node for anyone who then wanted to
# run the gates. That is the right path for a contributor and the wrong
# one for someone who wants to try the language.
#
# WHAT IT WILL NOT DO. It will not install a binary for a platform this
# project has never executed. `darwin-x86_64` is assembled and
# byte-compared by `check-cross-targets.sh` and run by no runner
# anywhere, so there is no release artifact for it and this script says
# so rather than handing over something untested. Building from the seed
# still works there, and that is what it points at.
#
# It also verifies the SHA-256 the release publishes beside each
# archive. A download that is checked only by "the server said 200" is
# not checked.
#
# THE VERIFICATION IS THE POINT, AND IT USED TO BE VACUOUS. The first
# version of this file ended by compiling `(fn (main) 42)` - a program
# that imports NOTHING - and reported success when it exited 42. That
# check cannot fail for the two ways an install is actually broken:
# an archive that shipped no `stdlib/`, and a `stdlib/` the compiler
# cannot locate. Both were reproduced against a real archive: with
# `stdlib/` deleted outright the 42-program still built and still
# exited 42. So the probe below imports a standard-library module, and
# it runs the compiler the way the line above it tells the user to -
# by its bare name, found on PATH - because that was the invocation
# form that did not work.

set -euo pipefail

REPO="${AXIOM_REPO:-chrispaig3/axiom}"
PREFIX="${AXIOM_PREFIX:-$HOME/.axiom}"
VERSION="${AXIOM_VERSION:-latest}"

usage() {
  cat <<'USAGE'
usage: install.sh [--version X.Y.Z] [--prefix DIR]

  --version   release to install (default: latest)
  --prefix    where to install    (default: ~/.axiom)

Environment: AXIOM_VERSION, AXIOM_PREFIX, AXIOM_REPO, AXIOM_BASE_URL.
Piping this script into bash gives it no arguments, so over
`curl ... | bash` the environment variables are the way to set these:

  curl -fsSL <url> | AXIOM_PREFIX=/opt/axiom bash

Installs <prefix>/bin/axiom and <prefix>/stdlib. Add <prefix>/bin to
PATH; the compiler finds its standard library relative to the directory
it was found in, so keep the two together.
USAGE
}

die() { echo "install.sh: $*" >&2; exit 1; }

# `--version` and `--prefix` each REQUIRE a value. Written as
# `VERSION="${2:-}"; shift 2` this silently did the wrong thing twice
# over: with no value left, `${2:-}` set the variable EMPTY and then
# `shift 2` failed against a one-element argument list, which under
# `set -e` ended the script at that line with no message and status 1.
# A user who typed `--version` and forgot the number got no output at
# all. Both halves are checked here instead.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || die "--version needs a value, e.g. --version 0.2.0"
      VERSION="$2"; shift 2 ;;
    --prefix)
      [[ $# -ge 2 ]] || die "--prefix needs a directory, e.g. --prefix ~/.axiom"
      PREFIX="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install.sh: unknown option '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$PREFIX" ]] || die "--prefix was given an empty directory"

# ---- platform -------------------------------------------------------
os="$(uname -s)"; arch="$(uname -m)"
case "$os" in
  Darwin)  os_name=darwin ;;
  Linux)   os_name=linux ;;
  FreeBSD) os_name=freebsd ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    die "no Axiom release runs on Windows yet. The compiler EMITS for windows-x86_64 (a Linux or macOS build links a .exe with --target=windows-x86_64), but hosting the compiler itself on Windows is a later phase of the Windows track: there is no Windows seed in bootstrap/ and nothing to install. README's Targets section says what is true today" ;;
  *) die "unsupported OS '$os'. Axiom targets darwin, linux and freebsd; build from source with scripts/bootstrap-from-seed.sh" ;;
esac
case "$arch" in
  arm64|aarch64) arch_name=aarch64 ;;
  x86_64|amd64)  arch_name=x86_64 ;;
  *) die "unsupported architecture '$arch'" ;;
esac
target="$os_name-$arch_name"

# THE TARGETS WITH NO ARTIFACT, and there are two KINDS of them. Saying
# which kind plainly is the point; shipping one quietly, or telling a
# user their platform is unsupported when it is not, are both defects.
#
# NOT SUPPORTED. darwin-x86_64 has no runner anywhere, so it has never
# been executed. The two FreeBSD targets (2026-08-29) have seeds and a
# CI leg that runs the compiler's output on FreeBSD 14; that leg is
# advisory until it is green. For these, no artifact exists AND the
# platform carries no promise.
#
# SUPPORTED, NOT SHIPPED. linux-x86_64 and freebsd-x86_64 (both
# 2026-08-30) are a different case and get a different message. Each
# has a blocking CI leg that runs what the compiler emits there, and
# will keep having one; what they have no archive for is a
# distribution decision, not a doubt. linux-x86_64's leg was the
# slowest and flakiest part of cutting a release; FreeBSD never had a
# release job at all. A user on either is not on unsupported ground -
# they just have to run one command.
#
# freebsd-AARCH64 stays in the not-supported arm below, and the split
# inside one operating system is the point: same seed, same syscall
# table, and no leg that runs either.
#
# `scripts/check-release-targets.sh` holds these two lists and
# `release.yml`'s build matrix to each other, so a target cannot end up
# in both or neither.
build_it() {  # <target> <why>
  cat >&2 <<NOTE
install.sh: there is no release binary for $1.

  $2

  To build it yourself, which is supported and takes one command:

    git clone https://github.com/chrispaig3/axiom && cd axiom
    ./scripts/bootstrap-from-seed.sh --install .axiom-bin

NOTE
  exit 1
}

case "$target" in
  linux-x86_64)
    build_it "$target" \
"It is fully supported and tested - CI runs the whole gate battery on
  linux-x86_64 on every change - but no prebuilt archive is published
  for it. Building from the committed seed is the supported path here." ;;
  freebsd-x86_64)
    build_it "$target" \
"It is a supported target - CI boots FreeBSD 14.4 in a VM on every
  change, bootstraps from the committed seed and runs the standard
  library there - but no release archive is built for it. Building from
  that same seed is the supported path here, and is what CI does." ;;
  darwin-x86_64|freebsd-aarch64)
    build_it "$target" \
"It is assembled and byte-compared in CI, but no release is built for
  it, so no artifact is published. Publishing one would imply a support
  level that does not exist." ;;
esac

# ---- the prefix this is allowed to overwrite ------------------------
#
# Further down, the old `bin/` and `stdlib/` are removed before the new
# ones are moved into place, and `rm -rf` over a path this script did
# not create is the most damaging thing in the file. `--prefix
# /usr/local` is a completely ordinary thing to type and it would have
# taken /usr/local/bin with it - every locally installed binary on the
# machine. `--prefix /` would have taken /bin.
#
# So the prefix must be absolute, must not be a filesystem root or a
# shared system directory, and must not be a directory that is already
# something else: a git checkout is refused by name, because the author
# of this file has the Axiom repository at ~/.axiom, which is also this
# script's DEFAULT prefix - the no-argument one-liner in the README
# would have deleted the repository's own stdlib/.
#
# THE COMPARISON IS OF PHYSICAL DIRECTORIES, NOT OF SPELLINGS. Until
# 2026-09-26 it stripped one trailing slash and compared the string, so
# `--prefix "$HOME"` was refused and `--prefix "$HOME/."` - the same
# directory - was accepted, and the install then deleted `$HOME/bin`
# and `$HOME/docs`. Reproduced by an audit in a scratch HOME with two
# sentinel files, both of which the second spelling destroyed. `..`,
# a doubled slash and a symlink to a protected directory were the same
# hole under other names. So the prefix is resolved first - every `.`
# and `..` taken out, every symlink in the part that exists followed
# (`physical_path` below) - and every protected directory is resolved
# the same way before the two are compared. On macOS that matters for
# the list itself: `/etc` and `/var` are symlinks into `/private`.
#
# The list is the first line of defence, not the only one. A directory
# nobody listed can hold things too, which is what the ownership check
# after the download is for.

# `physical_path <absolute path>`: the directory the path names once the
# kernel has resolved it, printed. Components that exist are resolved
# with `cd -P`, so a symlink anywhere in them is followed; once one does
# not exist, the rest cannot be symlinks and is resolved lexically - a
# `..` there undoes the component before it, which is what `mkdir -p`
# will do with the same spelling. Fails (status 1) when an existing
# component is not a directory, including a dangling symlink: nothing
# can be installed beneath it.
#
# Written for bash 3.2, because that is `/bin/bash` on macOS and this
# script is piped into whatever `bash` the user has.
#
# Every join is `${out%/}/<name>`, never `$out/<name>`: from the root
# the second spells `//var`, and POSIX lets a leading `//` mean
# something else, so bash's `pwd -P` keeps it - measured, `/var` then
# resolved to `//private/var` and the same directory had two answers.
physical_path() {
  local out="/" comp exists=1
  local -a comps
  IFS=/ read -r -a comps <<< "$1"
  for comp in "${comps[@]+"${comps[@]}"}"; do
    case "$comp" in
      ""|.) ;;
      ..)
        if (( exists )); then
          out="$(cd -P "${out%/}/.." 2>/dev/null && pwd -P)" || return 1
        else
          out="$(dirname "$out")"
          if [[ -d "$out" ]]; then
            exists=1
            out="$(cd -P "$out" 2>/dev/null && pwd -P)" || return 1
          fi
        fi ;;
      *)
        if (( exists )) && [[ -d "${out%/}/$comp" ]]; then
          out="$(cd -P "${out%/}/$comp" 2>/dev/null && pwd -P)" || return 1
        elif (( exists )) && { [[ -e "${out%/}/$comp" ]] || [[ -L "${out%/}/$comp" ]]; }; then
          return 1
        else
          exists=0
          out="${out%/}/$comp"
        fi ;;
    esac
  done
  printf '%s\n' "$out"
}

case "$PREFIX" in
  /*) ;;
  *)  die "--prefix must be an absolute path (got '$PREFIX')" ;;
esac
case "$PREFIX" in
  *$'\n'*) die "--prefix may not contain a newline" ;;
esac
given_prefix="$PREFIX"
PREFIX="$(physical_path "$given_prefix")" \
  || die "--prefix '$given_prefix' passes through something that is not a directory"
[[ "$PREFIX" != "/" ]] || die "--prefix may not be the filesystem root (got '$given_prefix')"

# Every directory refused outright, each resolved as the prefix was. A
# directory that does not exist on this machine cannot hold anything,
# and resolving it would fail, so it is skipped rather than compared.
for protected in /usr /usr/local /usr/bin /usr/sbin /usr/lib /bin /sbin /etc /var \
                 /opt /opt/homebrew /Library /System /Applications /private "$HOME"; do
  [[ -n "$protected" && -d "$protected" ]] || continue
  if [[ "$(physical_path "$protected")" == "$PREFIX" ]]; then
    die "refusing to install into '$given_prefix', which is $protected: this script
            replaces \$prefix/bin, \$prefix/stdlib and \$prefix/docs, and $protected
            holds files it did not put there. Choose a directory of its own,
            e.g. --prefix $HOME/.axiom"
  fi
done
if [[ -e "$PREFIX/.git" ]]; then
  die "refusing to install into '$given_prefix': it is a git checkout, and this script
            replaces \$prefix/stdlib. Choose a directory of its own."
fi

for tool in curl tar; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required and is not on PATH"
done

# `llc` and a C compiler are not needed to DOWNLOAD a compiler; they are
# needed for it to compile anything, including the probe at the end of
# this script. Checked here rather than discovered there, because the
# failure at the end reads as "the compiler you just installed is
# broken" when the truth is that a prerequisite is missing.
missing=""
command -v llc >/dev/null 2>&1 || missing="llc"
if ! command -v cc >/dev/null 2>&1 \
  && ! command -v clang >/dev/null 2>&1 \
  && ! command -v gcc >/dev/null 2>&1; then
  missing="${missing:+$missing and }a C compiler (cc, clang or gcc)"
fi
if [[ -n "$missing" ]]; then
  cat >&2 <<NOTE
install.sh: $missing is not on PATH.

  Axiom emits LLVM IR and links with a C compiler, so it needs both to
  build a program. Install them first:

    macOS         brew install llvm && export PATH="\$(brew --prefix llvm)/bin:\$PATH"
    Ubuntu/Debian sudo apt install llvm clang

NOTE
  exit 1
fi

sha_cmd=""
if command -v sha256sum >/dev/null 2>&1; then
  sha_cmd="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  sha_cmd="shasum -a 256"
else
  die "neither sha256sum nor shasum is on PATH, and the download must be verified"
fi
sha() { $sha_cmd "$@"; }

# ---- resolve --------------------------------------------------------
# `AXIOM_BASE_URL` names the directory the two files are fetched from,
# and exists so `scripts/check-install.sh` can serve a release it built
# itself. It is not a back door: setting it takes the same access as
# setting `PATH`, and anyone with that can replace `curl`. What it must
# NOT do is weaken a real install, so it is honoured only when it is
# set, and it changes WHERE the archive comes from and nothing about
# what is then required of it - the checksum file is still mandatory,
# the comparison still happens, and the installed compiler still has to
# build and run a program that imports the standard library.
# The protocol restriction travels with the base. A real install is
# `--proto '=https'` and stays that way; a base the caller named is
# allowed the two schemes a local test server can speak, and NOTHING
# else - so this cannot be talked into `scp://` or `dict://`.
fetch_proto="=https"
if [[ -n "${AXIOM_BASE_URL:-}" ]]; then
  base="$AXIOM_BASE_URL"
  fetch_proto="=http,https,file"
  [[ "$VERSION" != "latest" ]] \
    || die "AXIOM_BASE_URL needs an explicit --version: there is no release API to ask"
elif [[ "$VERSION" == "latest" ]]; then
  base="https://github.com/$REPO/releases/latest/download"
  echo "==> resolving the latest release of $REPO"
  # The two failure modes here are DIFFERENT and used to report the
  # same thing. `curl | grep | grep | head` exits with the status of
  # `head`, which is 0 whenever it wrote anything - so `|| die "could
  # not reach the GitHub release API"` fired for an unreachable API and
  # for a repository with no releases alike, and the second case is the
  # one this repository was in until its first tag existed. Capture the
  # curl separately so the two can be told apart.
  api="$(curl -fsSL --proto '=https' --tlsv1.2 \
      "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null)" \
    || die "could not reach the GitHub release API for $REPO"
  VERSION="$(printf '%s' "$api" \
    | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[0-9]+\.[0-9]+\.[0-9]+"' \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  [[ -n "$VERSION" ]] || die "$REPO has published no release yet; build from source with
            git clone https://github.com/$REPO && cd axiom &&
            ./scripts/bootstrap-from-seed.sh --install .axiom-bin"
else
  base="https://github.com/$REPO/releases/download/v$VERSION"
fi

# The version reaches a URL and a filesystem path below. It comes from
# a flag or an environment variable, so it is checked rather than
# trusted - the same rule `check-version.sh` applies to `VERSION`.
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "version '$VERSION' is not MAJOR.MINOR.PATCH"

name="axiom-$VERSION-$target"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

echo "==> downloading $name"
curl -fsSL --proto "$fetch_proto" --tlsv1.2 -o "$work/$name.tar.gz" "$base/$name.tar.gz" \
  || die "no archive at $base/$name.tar.gz"
curl -fsSL --proto "$fetch_proto" --tlsv1.2 -o "$work/$name.tar.gz.sha256" "$base/$name.tar.gz.sha256" \
  || die "the archive published no checksum; refusing to install it unverified"

echo "==> verifying"
want="$(awk '{print $1}' "$work/$name.tar.gz.sha256")"
got="$(sha "$work/$name.tar.gz" | awk '{print $1}')"
[[ -n "$want" ]] || die "the published checksum file is empty"
[[ "$want" == "$got" ]] || die "checksum mismatch: expected $want, got $got"
echo "    ok $got"

# Unpack BEFORE removing anything: a corrupt archive should not have
# already deleted the installation it was going to replace.
tar -xzf "$work/$name.tar.gz" -C "$work"
[[ -x "$work/$name/bin/axiom" ]] || die "the archive holds no bin/axiom"
[[ -d "$work/$name/stdlib" ]]    || die "the archive holds no stdlib/; refusing to install a
            compiler with no standard library"

# ---- what this script may replace ----------------------------------
#
# The names an installation consists of. `docs/` is OPTIONAL in an
# archive and REQUIRED of the archive builder, which is not an
# inconsistency: this script is fetched fresh and may be pointed at a
# release that predates docs/ shipping, and refusing to install 0.5.0
# because it lacks a directory 0.6.0 introduced would be this script
# breaking older releases as it improved. `check-install.sh` asserts
# the current tree's archive carries it.
managed="bin stdlib docs LICENSE README.md CHANGELOG.md"

# THE OWNERSHIP RECORD. A path resolving to no protected directory can
# still hold things this script did not put there - `--prefix ~/tools`
# with a `bin/` of the user's own - and replacing `$prefix/bin` would
# delete them exactly as the `$HOME/.` spelling did. So an install
# writes `.axiom-install`: a header, then one `file <path>` line per
# file it placed. Before anything is replaced, every file under every
# managed name that already exists must be one the record lists; one
# that is not is named and the install is refused, with nothing
# touched. Names the prefix does not have are simply created, and
# entries that are not managed names are never read or moved.
marker="$PREFIX/.axiom-install"
marker_head="axiom-install 1"

# Files (not directories) at or under `$PREFIX/<name>`, prefix-relative.
files_under() {
  ( cd "$PREFIX" && find "$1" \( -type f -o -type l \) -print ) | LC_ALL=C sort
}

# INSTALLS FROM BEFORE THE RECORD EXISTED have none, and refusing every
# one of them would strand every user on the version they have. They
# are recognised by SHAPE, and the shape is narrow on purpose: `bin/`
# holding exactly `bin/axiom`, `stdlib/` holding only `.ax` files,
# `docs/` holding only `.md` files - every earlier archive, and nothing
# a user's own directory is likely to be. The three prose files count
# as ours only beside such a `bin/axiom`. Anything else is unrelated
# and refused.
legacy_owns() {  # <name>
  case "$1" in
    bin)    [[ "$(files_under bin)" == "bin/axiom" ]] ;;
    stdlib) [[ -z "$(files_under stdlib | grep -v '\.ax$')" ]] ;;
    docs)   [[ -z "$(files_under docs | grep -v '\.md$')" ]] ;;
    *)      [[ "$(files_under bin 2>/dev/null)" == "bin/axiom" ]] ;;
  esac
}

if [[ -f "$marker" ]] && [[ "$(head -1 "$marker")" != "$marker_head" ]]; then
  die "refusing to install into '$given_prefix': its .axiom-install is not a record
            this script wrote (first line '$(head -1 "$marker")')"
fi
for m in $managed; do
  [[ -e "$PREFIX/$m" || -L "$PREFIX/$m" ]] || continue
  if [[ -f "$marker" ]]; then
    # No `head` on this pipe: under `pipefail` a reader that stops early
    # turns the writer's SIGPIPE into the pipeline's status, and an
    # assignment under `set -e` then ends the script with no message.
    sed -n 's/^file //p' "$marker" | LC_ALL=C sort > "$work/recorded"
    strangers="$(files_under "$m" | LC_ALL=C comm -23 - "$work/recorded")"
    stranger="${strangers%%$'\n'*}"
    [[ -z "$stranger" ]] && continue
    die "refusing to install into '$given_prefix': $PREFIX/$stranger was not put there
            by an earlier install (it is not in $marker), and this script
            replaces \$prefix/$m whole. Move it out of $m/, or choose a directory
            of its own."
  elif ! legacy_owns "$m"; then
    die "refusing to install into '$given_prefix': it already has $m, and nothing records
            that an earlier install put it there. This script replaces \$prefix/$m
            whole; choose a directory of its own, e.g. --prefix $HOME/.axiom"
  fi
done

# ---- stage, verify, then switch -------------------------------------
#
# THE NEW INSTALLATION IS PROVED BEFORE THE OLD ONE IS TOUCHED. This
# used to delete the old `bin/`, `stdlib/` and `docs/`, move the new
# ones in, and only then run the probe below - so an archive whose
# compiler could not build a program left the user with no working
# compiler at all. Now the archive is assembled in a staging directory
# INSIDE the prefix (same filesystem, so the switch is renames), the
# probe runs against the staged compiler, and only a staged compiler
# that passed is moved into place. The old tree is renamed aside first
# and removed last; a rename that fails puts it back.
mkdir -p "$PREFIX"
stage="$PREFIX/.axiom-stage.$$"
aside="$PREFIX/.axiom-old.$$"
cleanup() {
  rm -rf "$work"
  [[ -n "${stage:-}" ]] && rm -rf "$stage"
  return 0
}
trap cleanup EXIT
mkdir "$stage"
for m in $managed; do
  if [[ -e "$work/$name/$m" ]]; then mv "$work/$name/$m" "$stage/$m"; fi
done

# ---- an install that does not run is not an install -----------------
#
# The probe IMPORTS a standard-library module, so an archive with no
# `stdlib/` - or a `stdlib/` the compiler cannot locate - fails here
# rather than passing. And it runs from a directory of its own, so the
# module cannot be resolved through the compiler's working-directory
# fallback and report success for the wrong reason.
echo "==> checking the new compiler before installing it"
probe="$work/probe"
mkdir -p "$probe"
cat >"$probe/probe.ax" <<'AX'
(import IO (writeStr))

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (writeStr 1 "the standard library travelled with the compiler\n")
    42
  }
)
AX

# By BARE NAME on PATH, which is the invocation the line printed at the
# end of this script tells the user to adopt. `AXIOM_STDLIB` is unset
# for the probe on purpose: if it were set, this would pass without
# saying anything about the installation. The staged tree has the
# installed shape - `bin/` beside `stdlib/` - so what resolves here
# resolves after the renames below. Answers 0, or 1 with the reason on
# stderr.
verify_compiler() {  # <tree holding bin/ and stdlib/>
  if ! (
    cd "$probe"
    unset AXIOM_STDLIB AXIOM_PATH
    PATH="$1/bin:$PATH" axiom build --input probe.ax --output probe >/dev/null
  ); then
    echo "install.sh: the new compiler could not build a program that imports the
            standard library, invoked as \`axiom\` on PATH from $probe." >&2
    return 1
  fi
  local rc
  set +e; "$probe/probe" >/dev/null; rc=$?; set -e
  if [[ $rc -ne 42 ]]; then
    echo "install.sh: the new compiler built a program that exited $rc, wanted 42." >&2
    return 1
  fi
}
verify_compiler "$stage" || die "Nothing was installed; $given_prefix is as it was."

echo "==> installing to $PREFIX"
mkdir "$aside"
moved=""
restore() {
  local m
  for m in $moved; do rm -rf "$PREFIX/$m"; done
  for m in $managed; do
    if [[ -e "$aside/$m" ]]; then mv "$aside/$m" "$PREFIX/$m"; fi
  done
  rmdir "$aside" 2>/dev/null || true
}
for m in $managed; do
  if [[ -e "$PREFIX/$m" || -L "$PREFIX/$m" ]]; then
    mv "$PREFIX/$m" "$aside/$m" || { restore; die "could not move $PREFIX/$m aside; nothing was replaced"; }
  fi
done
for m in $managed; do
  if [[ -e "$stage/$m" ]]; then
    mv "$stage/$m" "$PREFIX/$m" || { restore; die "could not move the new $m into place; the old installation was restored"; }
    moved="$moved $m"
  fi
done
{
  echo "$marker_head"
  echo "version $VERSION"
  echo "target $target"
  for m in $managed; do
    if [[ -e "$PREFIX/$m" ]]; then files_under "$m" | sed 's/^/file /'; fi
  done
} > "$marker.tmp.$$" && mv "$marker.tmp.$$" "$marker"
rm -rf "$aside"
"$PREFIX/bin/axiom" --version >/dev/null 2>&1 \
  || die "$PREFIX/bin/axiom does not run after the move, although the staged copy did"

echo
echo "Axiom $VERSION ($target) installed."
echo "  $PREFIX/bin/axiom"
echo
echo "Add it to PATH:"
echo "  export PATH=\"$PREFIX/bin:\$PATH\""
echo
echo "The compiler finds its standard library relative to the directory it"
echo "was found in, so keep bin/ and stdlib/ together, or set AXIOM_STDLIB."
