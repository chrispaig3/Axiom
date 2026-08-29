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
  Darwin) os_name=darwin ;;
  Linux)  os_name=linux ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    die "no Axiom release runs on Windows yet. The compiler EMITS for windows-x86_64 (a Linux or macOS build links a .exe with --target=windows-x86_64), but hosting the compiler itself on Windows is a later phase of the Windows track: there is no Windows seed in bootstrap/ and nothing to install. README's Targets section says what is true today" ;;
  *) die "unsupported OS '$os'. Axiom targets darwin and linux; build from source with scripts/bootstrap-from-seed.sh" ;;
esac
case "$arch" in
  arm64|aarch64) arch_name=aarch64 ;;
  x86_64|amd64)  arch_name=x86_64 ;;
  *) die "unsupported architecture '$arch'" ;;
esac
target="$os_name-$arch_name"

# The one combination that is built but never run. Saying this plainly
# is the point; shipping it quietly would be the defect.
if [[ "$target" == "darwin-x86_64" ]]; then
  cat >&2 <<'NOTE'
install.sh: there is no release binary for darwin-x86_64.

  It is assembled and byte-compared in CI, but no runner for it exists,
  so it has never been executed and no artifact is published for it.
  Publishing one would imply a support level that does not exist.

  To build it yourself, which is supported:

    git clone https://github.com/chrispaig3/axiom && cd axiom
    ./scripts/bootstrap-from-seed.sh --install .axiom-bin

NOTE
  exit 1
fi

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
case "$PREFIX" in
  /*) ;;
  *)  die "--prefix must be an absolute path (got '$PREFIX')" ;;
esac
PREFIX="${PREFIX%/}"
[[ -n "$PREFIX" ]] || die "--prefix may not be the filesystem root"
case "$PREFIX" in
  /usr|/usr/local|/usr/bin|/bin|/sbin|/etc|/var|/opt|/opt/homebrew|"$HOME")
    die "refusing to install into '$PREFIX': this script removes \$prefix/bin and
            \$prefix/stdlib before installing, and '$PREFIX' holds files it did
            not put there. Choose a directory of its own, e.g. --prefix $HOME/.axiom" ;;
esac
if [[ -e "$PREFIX/.git" ]]; then
  die "refusing to install into '$PREFIX': it is a git checkout, and this script
            removes \$prefix/stdlib. Choose a directory of its own."
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

echo "==> installing to $PREFIX"
mkdir -p "$PREFIX"
rm -rf "$PREFIX/bin" "$PREFIX/stdlib"
mv "$work/$name/bin" "$PREFIX/bin"
mv "$work/$name/stdlib" "$PREFIX/stdlib"
for f in LICENSE README.md CHANGELOG.md; do
  if [[ -f "$work/$name/$f" ]]; then mv "$work/$name/$f" "$PREFIX/$f"; fi
done

# ---- an install that does not run is not an install -----------------
#
# The probe IMPORTS a standard-library module, so an archive with no
# `stdlib/` - or a `stdlib/` the compiler cannot locate - fails here
# rather than passing. And it runs from a directory of its own, so the
# module cannot be resolved through the compiler's working-directory
# fallback and report success for the wrong reason.
echo "==> checking the installed compiler"
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
# saying anything about the installation.
(
  cd "$probe"
  unset AXIOM_STDLIB AXIOM_PATH
  PATH="$PREFIX/bin:$PATH" axiom build --input probe.ax --output probe >/dev/null
) || die "the installed compiler could not build a program that imports the standard
            library, invoked as \`axiom\` on PATH from $probe.
            The archive unpacked to $PREFIX; \`$PREFIX/bin/axiom\` and
            \`$PREFIX/stdlib\` should be siblings."
set +e; "$probe/probe" >/dev/null; rc=$?; set -e
[[ $rc -eq 42 ]] || die "the installed compiler built a program that exited $rc, wanted 42"

echo
echo "Axiom $VERSION ($target) installed."
echo "  $PREFIX/bin/axiom"
echo
echo "Add it to PATH:"
echo "  export PATH=\"$PREFIX/bin:\$PATH\""
echo
echo "The compiler finds its standard library relative to the directory it"
echo "was found in, so keep bin/ and stdlib/ together, or set AXIOM_STDLIB."
