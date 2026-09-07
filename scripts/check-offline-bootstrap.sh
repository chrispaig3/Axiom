#!/usr/bin/env bash
# The build-from-source path works with no maintainer on the other end,
# and here is the check that keeps it that way.
#
# WHAT THIS IS FOR. `SECURITY.md` states the bus factor out loud: one
# maintainer, and procurement prices an unsupported dependency. Code
# cannot fix that, but one of its three mitigations is code-adjacent: a
# documented build-from-source path that does not depend on the
# maintainer being reachable. `CONTRIBUTING.md`'s Quick Start promises
# exactly that - after the clone, the checkout plus the host's `llc`
# and `cc` are sufficient - and this gate is what stops that sentence
# going stale. (`scripts/install.sh` is the other path and is excluded
# on purpose: it downloads a prebuilt release archive, so it needs the
# maintainer to have cut one. The two paths differ in whom they trust,
# and the document says so.)
#
# WHAT IT ASSERTS, over the bootstrap closure - `bootstrap-from-seed.sh`
# plus every file it sources:
#
#   1. the closure is exactly two files. The script may source
#      `scripts/lib/seed-sums.sh` and nothing else; a new `source`
#      line fails here until the closure is extended deliberately.
#   2. no member invokes a network tool: curl, wget, ssh/scp/sftp,
#      git, gh, cargo/rustc, npm, ftp/telnet, or any `https?://` URL.
#      Comments are stripped before the search, so a documented
#      "Not cargo, not rustc" does not trip it - and the ablation
#      plants a real invocation to prove the search is not looking at
#      nothing.
#
# WHAT IT DOES NOT DO. It does not rebuild the compiler offline: that
# measurement exists and is recorded below, but CI runners have network
# and taking it away needs privileges no portable gate can assume, so a
# dynamic arm here would be a skip on some machines and a failure on
# others rather than a check. The static property above is what every
# run holds; the dynamic run is what makes the static property mean
# something, and it is re-run by hand whenever the closure moves.
#
# THE DYNAMIC MEASUREMENT, 2026-09-07: the bootstrap ran to a verified
# compiler (seed -> stage1 -> stage2 == stage3, plus the running hello
# program) inside a container with networking disabled
# (`podman run --network=none`, `curl` to github.com confirmed dead
# before the build). Toolchain in the container: LLVM 18 `llc`, `cc`,
# python3 and git for the checkout itself - nothing fetched during the
# build, because there is nothing to fetch with.
#
# COST: no compiler, no `llc`, no network. Shell over two files, about
# a second. It is `gate_init`-free for that reason.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failed=0
probe_mode=0
probe_failed=0
probe_first=""
fail() {
  if (( probe_mode )); then
    probe_failed=$((probe_failed + 1))
    [[ -n "$probe_first" ]] || probe_first="$*"
  else
    echo "FAIL: $*"
    failed=$((failed + 1))
  fi
}
ok() { (( probe_mode )) || echo "ok   $*"; }

BOOTSTRAP="scripts/bootstrap-from-seed.sh"
SEED_SUMS="scripts/lib/seed-sums.sh"

# closure_sources <bootstrap-file>: every path it sources, repo-relative,
# one per line. Only the `source "$repo_root/..."` spelling is
# understood - a relative or computed source line is refused by the
# closure check below rather than resolved.
closure_sources() {
  grep -E '^[[:space:]]*source ' "$1" \
    | sed -E 's/^[[:space:]]*source "\$repo_root\///; s/"$//' \
    | LC_ALL=C sort -u
}

# stripped <file>: the file with `#` comments removed. A `#` inside a
# quoted string over-strips, but stripping can only HIDE text and this
# gate forbids patterns: over-stripping risks a false pass, which the
# ablation below (a real invocation, no comment near it) guards.
stripped() { sed 's/#.*//' "$1"; }

# NET_TOOLS is one alternation so the ablation plants one line and the
# error names the tool it found.
NET_PAT='\b(curl|wget|ssh|scp|sftp|ftp|telnet|nc|ncat|git|gh|cargo|rustc|npm|yarn|pnpm|pip|brew|apt-get|apt|dnf|pacman|apk)\b|https?://'

# check_closure <bootstrap-file> <sourced-path> <sourced-file>: the two
# sections above as one function over EXPLICIT paths, so the ablations
# run the real checks against doctored copies. The real run passes the
# committed pair; a probe that re-implemented the search instead would
# prove only that the probe works.
check_closure() { # <bootstrap-file> <sourced-path> <sourced-file>
  local bf="$1" want_src="$2" sf="$3" src n
  [[ -f "$bf" ]] || { fail "$bf is missing"; return; }
  [[ -f "$sf" ]] || { fail "$sf is missing"; return; }

  src="$(closure_sources "$bf")"
  n="$(printf '%s' "$src" | grep -c . || true)"
  if (( n == 0 )); then
    fail "$bf sources nothing recognisable - the closure cannot be empty, so the parse broke"
    return
  fi
  if [[ "$src" != "$want_src" ]]; then
    fail "$bf sources: $(printf '%s' "$src" | tr '\n' ' ')- the closure is exactly $want_src"
    return
  fi
  ok "$bf sources exactly $want_src"

  local f hit
  for f in "$bf" "$sf"; do
    hit="$(stripped "$f" | grep -noE "$NET_PAT" | head -3)"
    if [[ -n "$hit" ]]; then
      fail "$f invokes a network tool: $(printf '%s' "$hit" | head -1 | sed 's/^/at /')"
    else
      ok "$f invokes no network tool"
    fi
  done
}

echo "== the bootstrap closure is two files and neither reaches the network =="
check_closure "$repo_root/$BOOTSTRAP" "$SEED_SUMS" "$repo_root/$SEED_SUMS"

echo
echo "== the ablations: each doctored closure must be refused =="
pdir="$work/probe"; mkdir -p "$pdir"
cp "$repo_root/$BOOTSTRAP" "$pdir/boot.sh"
cp "$repo_root/$SEED_SUMS" "$pdir/sums.sh"

# (a) a real network invocation in the bootstrap. The comment says what
# it is FOR, so the comment-strip cannot be what finds it.
cp "$pdir/boot.sh" "$pdir/a.sh"
printf '\n# fetch the blessed seed instead of trusting the checkout\ncurl -fsSL https://example.com/seed.ll -o "$work/seed.ll"\n' >> "$pdir/a.sh"
probe_mode=1; probe_failed=0; probe_first=""
check_closure "$pdir/a.sh" "$SEED_SUMS" "$pdir/sums.sh"
probe_mode=0
if (( probe_failed )); then ok "probe: a bootstrap that curls a seed is refused ($probe_first)"
else fail "probe: a bootstrap invoking curl was accepted"; fi

# (b) a widened closure. The sourced file exists and is itself clean -
# what is refused is the widening, not its content.
printf '# nothing networked here\n' > "$pdir/evil.sh"
cp "$pdir/boot.sh" "$pdir/b.sh"
printf '\nsource "$repo_root/scripts/lib/evil.sh"\n' >> "$pdir/b.sh"
probe_mode=1; probe_failed=0; probe_first=""
check_closure "$pdir/b.sh" "$SEED_SUMS" "$pdir/sums.sh"
probe_mode=0
if (( probe_failed )); then ok "probe: a bootstrap sourcing a third file is refused ($probe_first)"
else fail "probe: a widened closure was accepted"; fi

# (c) a network invocation in the sourced half. The bootstrap is clean;
# the check must still fail, or auditing one file audits neither.
cp "$pdir/sums.sh" "$pdir/c-sums.sh"
printf '\ngit ls-remote https://example.com/repo >/dev/null\n' >> "$pdir/c-sums.sh"
probe_mode=1; probe_failed=0; probe_first=""
check_closure "$pdir/boot.sh" "$SEED_SUMS" "$pdir/c-sums.sh"
probe_mode=0
if (( probe_failed )); then ok "probe: a git invocation in the sourced half is refused ($probe_first)"
else fail "probe: a networked $SEED_SUMS was accepted"; fi

# (d) a bootstrap that sources nothing recognisable. Without the floor,
# deleting every source line reads as the smallest possible closure.
grep -vE '^[[:space:]]*source ' "$pdir/boot.sh" > "$pdir/d.sh"
probe_mode=1; probe_failed=0; probe_first=""
check_closure "$pdir/d.sh" "$SEED_SUMS" "$pdir/sums.sh"
probe_mode=0
if (( probe_failed )); then ok "probe: a bootstrap sourcing nothing trips the floor ($probe_first)"
else fail "probe: a bootstrap with no source lines was accepted"; fi

echo
if (( failed )); then
  echo "FAIL: $failed check(s) failed"
  exit 1
fi
echo "PASS: the bootstrap reads the checkout and the host toolchain and"
echo "      nothing else - a stranger needs no maintainer to build it"
