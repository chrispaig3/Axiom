#!/usr/bin/env bash
# Run the gate battery on Linux, from a Mac, before CI does.
#
# The local battery runs on Darwin, so a gate can pass there while
# encoding a Darwin-only assumption. Linux differs in ways Darwin hides:
# `nm -u` lists weak crt hooks for a program that spawns no thread, and
# peak RSS on a shared runner can fall as well as rise. This runs the
# same scripts on Linux before the push.
#
# The tree is mounted read-only at /src and copied to /work inside the
# container. `gate_init` bootstraps a compiler into
# `$repo_root/.axiom-bin` when it finds none, so a read-write mount
# would leave a Linux binary there for the next Darwin gate to run.
#
# It asserts nothing, and `run-gates.sh` does not call it. It does not
# replace CI, whose runners have their own toolchain versions, and it
# does not cover the FreeBSD or Windows legs, which need a VM and a
# Windows runner (see `ci.yml`).
#
# Usage:
#   scripts/run-gates-linux.sh                 # whole battery, native arch
#   scripts/run-gates-linux.sh fmt lsp         # only gates matching these
#   scripts/run-gates-linux.sh --arch amd64    # linux-x86_64, emulated
#   scripts/run-gates-linux.sh --shell         # a prompt in the image
#   scripts/run-gates-linux.sh --build         # build the image and stop
#
# Environment:
#   AXIOM_CONTAINER   docker | podman, to override detection
#   AXIOM_LINUX_IMAGE the image tag to build and use
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "run-gates-linux: $*" >&2; exit 1; }

# ---- arguments ------------------------------------------------------
arch=""
mode="gates"
filters=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      [[ $# -ge 2 ]] || die "--arch needs a value: amd64 or arm64"
      arch="$2"; shift 2 ;;
    --shell)  mode="shell"; shift ;;
    --build)  mode="build"; shift ;;
    -h|--help)
      sed -n '/^# Usage:/,/^#   AXIOM_LINUX_IMAGE/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --*) die "unknown option '$1' (see --help)" ;;
    *) filters+=("$1"); shift ;;
  esac
done

case "${arch:-}" in
  ""|amd64|arm64) ;;
  x86_64) arch=amd64 ;;
  aarch64) arch=arm64 ;;
  *) die "--arch must be amd64 or arm64, not '$arch'" ;;
esac

# The default leg is the host's architecture, which runs natively: on
# Apple Silicon that is arm64 (`linux-aarch64`). `--arch amd64`
# (`linux-x86_64`) runs emulated and much slower, and the script warns
# before it starts.
host_arch="$(uname -m)"
case "$host_arch" in
  arm64|aarch64) native=arm64 ;;
  x86_64|amd64)  native=amd64 ;;
  *) die "unsupported host architecture '$host_arch'" ;;
esac
arch="${arch:-$native}"

# ---- the container runtime -----------------------------------------
# A missing runtime is an error with install hints. A silent skip would
# look like a run that found nothing.
#
# Also look off `PATH`: Podman Desktop installs its client in
# `/opt/podman/bin`, which a login shell need not export.
engine="${AXIOM_CONTAINER:-}"
if [[ -z "$engine" ]]; then
  for c in docker podman; do
    command -v "$c" >/dev/null 2>&1 && { engine="$c"; break; }
  done
fi
if [[ -z "$engine" ]]; then
  for p in /opt/podman/bin/podman /opt/homebrew/bin/podman /usr/local/bin/podman \
           /opt/homebrew/bin/docker /usr/local/bin/docker /Applications/Docker.app/Contents/Resources/bin/docker; do
    if [[ -x "$p" ]]; then
      engine="$p"
      echo "note: using $p (not on PATH)"
      break
    fi
  done
fi
[[ -n "$engine" ]] || cat >&2 <<'NOTE'
run-gates-linux: no container runtime found (looked for docker, podman).

  This script runs the gate battery on Linux so a Darwin-only
  assumption is caught before CI sees it. It needs one of:

    brew install podman && podman machine init && podman machine start
    brew install colima docker && colima start

  Set AXIOM_CONTAINER to override the choice.

NOTE
[[ -n "$engine" ]] || exit 1
command -v "$engine" >/dev/null 2>&1 || die "AXIOM_CONTAINER='$engine' is not on PATH"

"$engine" info >/dev/null 2>&1 || die \
  "'$engine' is installed but its daemon is not reachable - start it first (e.g. 'colima start' or 'podman machine start')"

# ---- the image ------------------------------------------------------
# Ubuntu, because `ci.yml`'s Linux legs run it. The packages are the
# provision action's plus what the gates shell out to: `python3`,
# `curl` and `file` (install, ffi), `git` (build-id), `xxd` where a
# gate reads bytes, and `npm` for the tree-sitter CLI.
#
# `llvm` brings `llc` and `opt`; `clang` is the linker driver the
# emitter calls as `cc`. `libclang-rt-dev` holds clang's sanitizer
# runtimes, which `check-race.sh` links and `--no-install-recommends`
# would leave out. `nm` comes from binutils and reads ELF, as on CI.
read -r -d '' dockerfile <<'DOCKER'
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      llvm clang lld libclang-rt-dev binutils \
      bash coreutils findutils diffutils grep sed gawk \
      python3 curl ca-certificates git file xxd time make \
      nodejs npm \
 && rm -rf /var/lib/apt/lists/*
# `cc` is what the emitter invokes; Ubuntu ships clang without it.
RUN ln -sf /usr/bin/clang /usr/local/bin/cc
WORKDIR /work
DOCKER

# Tagged by a hash of the recipe, so editing the Dockerfile above
# rebuilds the image and an unchanged recipe reuses it.
recipe_hash="$(printf '%s' "$dockerfile" | (shasum -a 256 2>/dev/null || sha256sum) | cut -c1-12)"
image="${AXIOM_LINUX_IMAGE:-axiom-gates:$recipe_hash-$arch}"

if ! "$engine" image inspect "$image" >/dev/null 2>&1; then
  echo "== building $image (linux/$arch) =="
  printf '%s\n' "$dockerfile" | "$engine" build --platform "linux/$arch" -t "$image" -f - "$repo_root" \
    || die "could not build the image"
else
  echo "== reusing $image =="
fi

[[ "$mode" == "build" ]] && { echo "ok   image ready: $image"; exit 0; }

# ---- what runs inside ----------------------------------------------
# A copy of the tree, for the reason in the header. It leaves out
# `.axiom-bin`, whose Darwin compiler must not run on Linux, other host
# build output and nested worktrees.
read -r -d '' inner <<'INNER'
set -uo pipefail
mkdir -p /work
# `.git` comes along: the git-consuming gates fail without it, and a
# failure the harness causes teaches readers to skim the FAILED list.
#
# The top-level and `tree-sitter-axiom` `node_modules` stay behind. The
# nested one needs its own exclude, because `./node_modules` matches
# only the top level. The host's `tree-sitter-cli` is a Mach-O binary,
# and Linux runs it as a script and reports
# `Syntax error: newline unexpected`.
tar -C /src --exclude=./.axiom-bin --exclude='./node_modules' \
    --exclude='./tree-sitter-axiom/node_modules' \
    --exclude=./rust/target --exclude=./.claude/worktrees \
    --exclude=./.muse/worktrees -cf - . \
  | tar -C /work -xf -
cd /work
# In a worktree, `/work/.git` is a pointer to a host path. Replace it
# with a copy of the mounted object store and point HEAD at the
# worktree's checkout, so git answers as it would on the host.
if [[ -f /work/.git ]]; then
  if [[ -d /srcgit ]]; then
    head_ref="${AXIOM_WORKTREE_HEAD:-}"
    rm -f /work/.git
    cp -a /srcgit /work/.git
    rm -f /work/.git/index /work/.git/HEAD.lock 2>/dev/null || true
    # A symbolic HEAD reads `ref: refs/heads/x`. A bare `refs/heads/x`
    # makes git reject the whole directory as `not a git repository`.
    # `$AXIOM_WORKTREE_HEAD` is the host's `git symbolic-ref HEAD` on a
    # branch and `git rev-parse HEAD` when detached; handle both.
    if [[ -n "$head_ref" ]]; then
      case "$head_ref" in
        refs/*) printf 'ref: %s\n' "$head_ref" > /work/.git/HEAD ;;
        *)      printf '%s\n'      "$head_ref" > /work/.git/HEAD ;;
      esac
    fi
    # Check that git accepts the result: the right files in the right
    # places can still fail to be a repository.
    if ! git -C /work rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo "== the rebuilt /work/.git is NOT a usable repository - the five" >&2
      echo "   git-consuming gates will fail for this harness's reason and" >&2
      echo "   not the tree's. HEAD is [$(cat /work/.git/HEAD 2>&1)] =="  >&2
      exit 1
    fi
    # Rebuild the index too. A worktree's index is
    # `.git/worktrees/<name>/index`, not the `.git/index` git reads here.
    # Without a fresh one, `git diff` calls every file the tar touched
    # modified, and `check-compat` reports its regenerated baseline as
    # changed.
    git -C /work reset -q 2>/dev/null || true
    echo "== worktree .git rebuilt from the mounted object store, at $(git -C /work rev-parse --short HEAD) =="
  else
    echo "== /work/.git is a worktree pointer and no object store was mounted;"
    echo "   git-consuming gates will fail for that reason and not the tree's. =="
  fi
fi
# The copy is owned by whoever ran the tar, not by the container user,
# and git refuses a repository it thinks belongs to someone else.
git config --global --add safe.directory /work 2>/dev/null || true
# The tree-sitter CLI is native, so install a Linux copy here. If npm
# cannot, `check-tree-sitter.sh` skips itself through
# `AXIOM_TREE_SITTER_OPTIONAL=1`, and the skip is printed so it is not
# mistaken for a pass.
if npm install --no-audit --no-fund --prefix tree-sitter-axiom tree-sitter-cli >/tmp/npm.log 2>&1; then
  echo "== tree-sitter CLI installed for this run =="
else
  export AXIOM_TREE_SITTER_OPTIONAL=1
  echo "== NOT RUN HERE (1): check-tree-sitter.sh - its CLI is a native"
  echo "   binary, the host's cannot be reused on Linux, and npm could not"
  echo "   install one (no network?). Skipped by its own documented opt-out"
  echo "   rather than failed, and named rather than silent. =="
  sed 's/^/   npm: /' /tmp/npm.log | tail -3
fi
echo "== $(uname -m) $(. /etc/os-release && echo "$PRETTY_NAME") =="
llc --version | sed -n '2,3p'
exec ./scripts/run-gates.sh "$@"
INNER

if [[ "$mode" == "shell" ]]; then
  exec "$engine" run --rm -it --platform "linux/$arch" \
    -v "$repo_root:/src:ro" "$image" bash -lc \
    'mkdir -p /work && tar -C /src --exclude=./.axiom-bin -cf - . | tar -C /work -xf - && cd /work && git config --global --add safe.directory /work 2>/dev/null; exec bash'
fi

if [[ "$arch" != "$native" ]]; then
  echo "note: linux/$arch is emulated on this $host_arch host - expect it to be"
  echo "      several times slower than the native leg. This is the arch whose"
  echo "      legs found both Darwin-only gate defects, so it is the one worth"
  echo "      the wait before a push that touches a gate."
fi

# In a `git worktree`, `.git` is a small file reading
# `gitdir: /abs/host/path`, and that path is not mounted. Every git
# command inside would exit 128, and the five git-consuming gates
# (`check-seed-lineage`, `check-seed-provenance`, `check-restrictions`,
# `check-compat` and `check-doc-drift`'s paths section) would fail for
# the harness's reason. So mount the real object store read-only at
# /srcgit, and the inner script rebuilds `.git` from it.
gitmount=()
gitcommon=""
if [[ -f "$repo_root/.git" ]]; then
  gitcommon="$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -n "$gitcommon" && -d "$gitcommon" ]]; then
    gitmount=(-v "$gitcommon:/srcgit:ro")
    # Read HEAD here, where the worktree's own gitdir is reachable. The
    # mounted store's HEAD is the main checkout's.
    wt_head="$(git -C "$repo_root" symbolic-ref HEAD 2>/dev/null || git -C "$repo_root" rev-parse HEAD)"
    echo "== worktree detected: mounting its object store from $gitcommon =="
  else
    echo "== worktree detected and its object store could not be resolved;" >&2
    echo "   the five git-consuming gates will report content failures that" >&2
    echo "   are this harness's fault. Run from the main checkout instead. =="  >&2
  fi
fi

exec "$engine" run --rm --platform "linux/$arch" \
  -v "$repo_root:/src:ro" \
  ${gitmount[@]+"${gitmount[@]}"} \
  -e AXIOM_GATE_JOBS="${AXIOM_GATE_JOBS:-}" \
  -e AXIOM_WORKTREE_HEAD="${wt_head:-}" \
  "$image" bash -c "$inner" -- "${filters[@]+"${filters[@]}"}"
