#!/usr/bin/env bash
# RUN THE GATE BATTERY ON LINUX, FROM A MAC, BEFORE CI DOES.
#
# WHY THIS EXISTS, and it is not "for completeness". The local battery
# is darwin-only, so a gate can be written, validated and landed by a
# developer whose machine never exercises the assumption it encodes.
# Twice in two days that is exactly what shipped, and neither time was
# the TARGET at fault:
#
#   check-thread-local.sh   required `nm -u` to be EMPTY for a program
#                           that spawns no thread. True on Darwin, false
#                           by construction on Linux, where the same
#                           program imports six symbols - four weak crt
#                           hooks and two real ones. Both Linux legs went
#                           red on a program behaving exactly as intended.
#
#   check-steady-state.sh   compared |b - a| against a 256 KiB band, so a
#                           run whose peak RSS FELL failed like one that
#                           grew. Darwin's numbers are stable to 16 KiB,
#                           so the fall path was never reached here; a
#                           shared Linux runner reached it at 264.
#
# Both went green on the machine that wrote them and red on a leg that
# had never seen them. That is a feedback-loop defect, and this closes
# it: the same battery, the same scripts, on Linux, before the push.
#
# IT COPIES THE TREE, IT DOES NOT MOUNT IT READ-WRITE, and that is the
# one design decision worth reading. `gate_init` bootstraps a compiler
# into `$repo_root/.axiom-bin` when it does not find one, so a
# read-write bind mount would leave a LINUX binary in your checkout -
# and the next darwin gate to reuse `.axiom-bin/axiom` would run it and
# fail in a way that has nothing to do with the change under test. The
# repo is mounted READ-ONLY at /src and copied to /work inside the
# container, so nothing this script does can touch the host tree.
#
# WHAT IT IS NOT. It is not a gate: it asserts nothing about the tree
# and `run-gates.sh` does not call it. It is not a substitute for CI -
# CI runs on real Linux runners with their own toolchain versions, and
# this runs one image. And it is not the FreeBSD or Windows leg; those
# need a VM and a Windows runner respectively (see `ci.yml`).
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

# The host's own architecture, so the default leg is the one that runs
# NATIVELY. On Apple Silicon that is arm64 - which is `linux-aarch64`,
# a target this project both supports and ships - and it runs at full
# speed. `--arch amd64` is `linux-x86_64` and is EMULATED here; it is
# the leg that has produced both defects above, so it is worth running,
# and it is slow enough that saying so is part of the interface.
host_arch="$(uname -m)"
case "$host_arch" in
  arm64|aarch64) native=arm64 ;;
  x86_64|amd64)  native=amd64 ;;
  *) die "unsupported host architecture '$host_arch'" ;;
esac
arch="${arch:-$native}"

# ---- the container runtime -----------------------------------------
# Named rather than guessed, and a missing one is an ERROR with a way
# out rather than a silent skip: a script that quietly does nothing
# when its tool is absent is indistinguishable from one that ran and
# found nothing, which is the failure mode this whole file is about.
#
# LOOKED FOR OFF `PATH` AS WELL, because the first machine this script
# met had podman installed and not on it: Podman Desktop puts its
# client in `/opt/podman/bin`, which a login shell need not export.
# `command -v podman` answered nothing and this script said "no
# container runtime found" to a machine that had one - a false
# negative that reads exactly like the true one, on the script whose
# whole subject is a check that goes quiet when its tool is missing.
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
# Ubuntu because that is what `ci.yml`'s Linux legs run, and the point
# is to reproduce THAT environment rather than a tidier one. The
# package list is the provision action's, plus what the gates shell
# out to: `python3` (several gates), `curl` and `file` (install, ffi),
# `git` (build-id), `bsdmainutils`/`xxd` where a gate reads bytes.
#
# `llvm` brings `llc` and `opt`; `clang` is the linker driver the
# emitter calls as `cc`. `nm` comes from binutils and is the ELF one -
# which is the whole point, since the Mach-O/ELF difference is what
# `check-thread-local.sh` got wrong.
read -r -d '' dockerfile <<'DOCKER'
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      llvm clang lld binutils \
      bash coreutils findutils diffutils grep sed gawk \
      python3 curl ca-certificates git file xxd time make \
      nodejs npm \
 && rm -rf /var/lib/apt/lists/*
# `cc` is what the emitter invokes; Ubuntu ships clang without it.
RUN ln -sf /usr/bin/clang /usr/local/bin/cc
WORKDIR /work
DOCKER

# Tagged by a hash of the recipe, so editing the Dockerfile above
# rebuilds and leaving it alone does not. Without this the choice is
# between rebuilding every run (slow) and a fixed tag that silently
# serves a stale image after the recipe changes (worse).
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
# `cp -a` rather than a bind mount, for the reason in the header. `.git`
# is excluded because it is the largest thing in the tree and no gate
# reads it except `check-build-id.sh`, which falls back when it is
# absent; `.axiom-bin` is excluded because a DARWIN binary in there is
# exactly what must not be reused on Linux.
read -r -d '' inner <<'INNER'
set -uo pipefail
mkdir -p /work
# `.git` TRAVELS, and it is 30 MB well spent. Four gates ask git a
# question and cannot be answered without it - `check-seed-lineage`
# and `check-seed-provenance` walk the history for commits touching
# `bootstrap/*.ll`, `check-restrictions`'s manifest section shells out
# to it, and `check-compat` asks `git diff --quiet` whether a
# regenerated baseline is dirty. Excluded, all four FAILED, and every
# one of those failures was this script's fault rather than the tree's.
#
# That is the worse outcome, not a lesser one: `run-gates.sh`'s own
# header says a gate whose failure means nothing teaches its reader to
# skim the FAILED list instead of reading it. A harness that
# manufactures four such failures is a harness that makes the battery
# useless the first time it is trusted.
#
# EVERY `node_modules`, AT EVERY DEPTH, and this one is not tidiness.
# `tree-sitter-axiom/node_modules` is nested, so a top-level exclude
# missed it, and the host's `tree-sitter-cli` binary - a Mach-O
# executable built for darwin-arm64 - travelled into a Linux container
# and was executed. It failed as `Syntax error: newline unexpected`,
# which is a shell trying to read a macOS binary as a script and is a
# long way from anything a reader would connect to the cause. A
# harness whose whole purpose is to run this tree on Linux must not
# carry host-built artifacts into it.
tar -C /src --exclude=./.axiom-bin --exclude='./node_modules' \
    --exclude='./tree-sitter-axiom/node_modules' \
    --exclude=./rust/target --exclude=./.claude/worktrees -cf - . \
  | tar -C /work -xf -
cd /work
# The worktree case: `/work/.git` arrived as a pointer to a host path.
# Replace it with a real repository copied out of the mounted object
# store, then re-point HEAD at what the worktree had checked out. A
# `git log`/`git ls-files` answered from this is the same answer the
# host would give, which is all five consumers need.
if [[ -f /work/.git ]]; then
  if [[ -d /srcgit ]]; then
    head_ref="${AXIOM_WORKTREE_HEAD:-}"
    rm -f /work/.git
    cp -a /srcgit /work/.git
    rm -f /work/.git/index /work/.git/HEAD.lock 2>/dev/null || true
    [[ -n "$head_ref" ]] && printf '%s\n' "$head_ref" > /work/.git/HEAD
    # AND THE INDEX MUST BE REBUILT, not merely deleted. A worktree's
    # index lives in `.git/worktrees/<name>/index`, not in the shared
    # store copied above, so the copy arrives with either no index or
    # the MAIN checkout's. Without one, `git diff` re-stats a tree
    # whose mtimes the tar just changed and calls every file modified -
    # which reaches `check-compat` as "a baseline regenerated by the
    # run is modified", a content failure over a plumbing cause, and
    # exactly the class this whole block exists to stop manufacturing.
    git -C /work reset -q 2>/dev/null || true
    echo "== worktree .git rebuilt from the mounted object store =="
  else
    echo "== /work/.git is a worktree pointer and no object store was mounted;"
    echo "   git-consuming gates will fail for that reason and not the tree's. =="
  fi
fi
# The copy is owned by whoever ran the tar, not by the container user,
# and git refuses a repository it thinks belongs to someone else.
git config --global --add safe.directory /work 2>/dev/null || true
# The tree-sitter CLI is a native binary, so the host's copy cannot be
# reused and this one is installed here or the gate does not run. Which
# of those happened is PRINTED: `check-tree-sitter.sh` offers
# `AXIOM_TREE_SITTER_OPTIONAL=1` to skip itself, and a skip nobody
# mentions is indistinguishable from a pass.
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

# A WORKTREE'S `.git` IS A POINTER, AND COPYING IT COPIES A DANGLING ONE.
# In an ordinary checkout `.git` is a directory and the tar below carries
# it whole. In a `git worktree`, `.git` is a ~67-byte FILE reading
# `gitdir: /abs/host/path`, and that path is not mounted - so every git
# command inside exits 128 and the five git-consuming gates
# (`check-seed-lineage`, `check-seed-provenance`, `check-restrictions`,
# `check-compat`, and `check-doc-drift`'s paths section) fail for a
# reason that has nothing to do with the tree.
#
# That is the failure mode this script's own header calls the worse
# outcome - a harness manufacturing failures teaches its reader to skim
# the FAILED list - and it was WORSE here than a missing `.git`, because
# `.git` EXISTS and is unusable, so nothing reports it as absent. Found
# 2026-09-01 by two independent runs losing time to it.
#
# The fix mounts the real object store read-only at a fixed path and
# rewrites the pointer inside the container to name it.
gitmount=()
gitcommon=""
if [[ -f "$repo_root/.git" ]]; then
  gitcommon="$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -n "$gitcommon" && -d "$gitcommon" ]]; then
    gitmount=(-v "$gitcommon:/srcgit:ro")
    # HEAD is read HERE, where the worktree's own gitdir is reachable;
    # the object store mounted above is the SHARED one and its HEAD is
    # the main checkout's, which is a different commit.
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
