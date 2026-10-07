#!/usr/bin/env bash
# Install a released Axiom without cloning the repository.
#
# This is the path for trying the language. Contributors clone the
# repository and bootstrap from the seed instead.
#
# It installs only targets whose test battery runs in CI. A source-only
# target such as `darwin-x86_64` has no release archive, so the script
# says so and points at building from the seed, which works there.
#
# It verifies the SHA-256 the release publishes beside each archive.
#
# Before replacing anything, it builds and runs a probe that imports a
# standard-library module, invoking the compiler by its bare name on
# PATH as the user will. A program that imports nothing would still pass
# with no `stdlib/`, or with one the compiler cannot find.

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

# `--version` and `--prefix` each require a value, checked before the
# shift: under `set -e`, `shift 2` with one argument left ends the script
# with status 1 and no message.
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
    die "no Axiom release runs on Windows yet. The compiler EMITS for windows-x86_64 and windows-aarch64 (a Linux or macOS build links a .exe with --target=windows-x86_64 or --target=windows-aarch64), but hosting the compiler itself on Windows is a later phase of the Windows track: there is no Windows seed in bootstrap/ and nothing to install. README's Targets section says what is true today" ;;
  *) die "unsupported OS '$os'. Axiom targets darwin, linux and freebsd; build from source with scripts/bootstrap-from-seed.sh" ;;
esac
case "$arch" in
  arm64|aarch64) arch_name=aarch64 ;;
  x86_64|amd64)  arch_name=x86_64 ;;
  *) die "unsupported architecture '$arch'" ;;
esac
target="$os_name-$arch_name"

# The targets with no release archive are README's source-only targets:
# darwin-x86_64, freebsd-aarch64, freebsd-x86_64 and linux-x86_64 here.
# A Windows host has already stopped at `uname -s` above. No CI leg runs
# the test battery on these, so they carry no support promise and the
# seed is the way to install. CI does build from the seed on
# linux-x86_64 and freebsd-x86_64; the message does not claim that for
# the other two.
#
# `scripts/check-release-targets.sh` holds this list and
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
  linux-x86_64|freebsd-x86_64|darwin-x86_64|freebsd-aarch64)
    build_it "$target" \
"It is a source-only target: no CI job runs the test battery on
  $target, and no prebuilt archive is published for it. Building from
  the committed seed is the way to install it here." ;;
esac

# ---- the prefix this is allowed to overwrite ------------------------
#
# The install replaces `$prefix/bin`, `$prefix/stdlib` and
# `$prefix/docs`, so an ordinary `--prefix /usr/local` would take every
# locally installed binary with it. The prefix must be absolute, must not
# be a filesystem root or a shared system directory, and must not be a
# git checkout: the default `~/.axiom` may already be a clone of this
# repository.
#
# The comparison is of physical directories, not spellings. `$HOME/.`,
# `..`, a doubled slash and a symlink can all name a protected directory.
# So the prefix is resolved first (`physical_path` below), and each
# protected directory is resolved the same way. On macOS that matters for
# the list itself: `/etc` and `/var` are symlinks into `/private`.
#
# The list is the first line of defence. The ownership record after the
# download covers directories nobody listed.

# `physical_path <absolute path>`: the directory the path names once the
# kernel has resolved it, printed. Existing components are resolved with
# `cd -P`, so a symlink anywhere in them is followed. Past the first
# missing one, the rest cannot be symlinks and is resolved lexically: a
# `..` undoes the component before it, as `mkdir -p` would. Fails
# (status 1) when an existing component is not a directory, including a
# dangling symlink.
#
# Written for bash 3.2, which is `/bin/bash` on macOS, because this
# script is piped into whatever `bash` the user has.
#
# Every join is `${out%/}/<name>`, never `$out/<name>`: from the root the
# second spells `//var`, and POSIX lets a leading `//` mean something
# else. `pwd -P` keeps it, so one directory would have two answers.
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
# directory missing on this machine holds nothing and would fail to
# resolve, so it is skipped.
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

# `llc` and a C compiler aren't needed to download a compiler, but the
# probe needs them to build anything. Checking here keeps a missing
# prerequisite from reading as "the compiler you installed is broken".
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
# so `scripts/check-install.sh` can serve a release it built itself.
# Setting it takes the same access as setting `PATH`, which could
# replace `curl` outright, so it opens nothing new. It changes only
# where the archive comes from: the checksum file is still mandatory and
# the probe still runs. A real install stays `--proto '=https'`. A base
# the caller named also allows the http and file schemes a local test
# server needs, and nothing else, so it cannot reach `scp://` or `dict://`.
fetch_proto="=https"
if [[ -n "${AXIOM_BASE_URL:-}" ]]; then
  base="$AXIOM_BASE_URL"
  fetch_proto="=http,https,file"
  [[ "$VERSION" != "latest" ]] \
    || die "AXIOM_BASE_URL needs an explicit --version: there is no release API to ask"
elif [[ "$VERSION" == "latest" ]]; then
  base="https://github.com/$REPO/releases/latest/download"
  echo "==> resolving the latest release of $REPO"
  # The curl runs on its own so an unreachable API and a repository with
  # no releases give different messages. In one pipeline ending in
  # `head`, a single `|| die` cannot tell them apart.
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
# a flag or an environment variable, so it is checked, as
# `check-version.sh` checks `VERSION`.
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

# Unpack before removing anything: a corrupt archive should not have
# already deleted the installation it was going to replace.
tar -xzf "$work/$name.tar.gz" -C "$work"
[[ -x "$work/$name/bin/axiom" ]] || die "the archive holds no bin/axiom"
[[ -d "$work/$name/stdlib" ]]    || die "the archive holds no stdlib/; refusing to install a
            compiler with no standard library"

# ---- what this script may replace ----------------------------------
#
# The names an installation consists of. `docs/` is optional here, so
# this script, fetched fresh, can still install a release that predates
# it. `check-install.sh` requires the current tree's archive to carry it.
managed="bin stdlib docs LICENSE README.md CHANGELOG.md"

# The ownership record. A prefix that is no protected directory can still
# hold files this script did not put there, such as `--prefix ~/tools`
# with a `bin/` of the user's own. So an install writes `.axiom-install`:
# a header, then one `file <path>` line per file it placed. Before
# anything is replaced, every existing file under a managed name must be
# in the record; otherwise the install names it and stops, touching
# nothing. Missing names are created, and other entries are never read
# or moved.
marker="$PREFIX/.axiom-install"
marker_head="axiom-install 1"

# Files (not directories) at or under `$PREFIX/<name>`, prefix-relative.
files_under() {
  ( cd "$PREFIX" && find "$1" \( -type f -o -type l \) -print ) | LC_ALL=C sort
}

# Installs that predate the record have none, and refusing them would
# strand their users. They are recognised by a narrow shape that every
# earlier archive has and a user's own directory is unlikely to: `bin/`
# holding exactly `bin/axiom`, `stdlib/` only `.ax` files and `docs/`
# only `.md` files. The three prose files count as ours only beside such
# a `bin/axiom`. Anything else is refused.
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
# The new installation is proved before the old one is touched, so a
# broken archive never leaves the user without a working compiler. The
# archive is assembled in a staging directory inside the prefix (same
# filesystem, so the switch is renames), and the probe runs against the
# staged compiler. Only a compiler that passed is moved into place. The
# old tree is renamed aside first and removed last; a failed rename puts
# it back.
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

# ---- probe the staged compiler --------------------------------------
#
# The probe imports a standard-library module, so an archive with no
# `stdlib/`, or one the compiler cannot locate, fails here. It runs from
# a directory of its own, so the compiler's working-directory fallback
# cannot resolve the module for it.
echo "==> checking the new compiler before installing it"
probe="$work/probe"
mkdir -p "$probe"
cat >"$probe/probe.ax" <<'AX'
(import IO (writeStr))

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (writeStr stdout "the standard library travelled with the compiler\n")
    42
  }
)
AX

# By bare name on PATH, as the message at the end tells the user to run
# it. `AXIOM_STDLIB` and `AXIOM_PATH` are unset, or the probe would pass
# without saying anything about the installation. The staged tree has
# the installed shape, `bin/` beside `stdlib/`, so what resolves here
# resolves after the renames. Answers 0, or 1 with the reason on stderr.
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
