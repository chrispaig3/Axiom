#!/usr/bin/env bash
# Check that building from source needs no maintainer and no network.
#
# `CONTRIBUTING.md`'s Quick Start promises that after the clone, the
# checkout plus the host's `llc` and `cc` are enough. That path answers
# the single-maintainer risk `SECURITY.md` names, and this gate keeps
# the promise true. `scripts/install.sh` downloads a prebuilt release,
# so it is out of scope.
#
# Over the bootstrap closure, `bootstrap-from-seed.sh` plus every file
# it sources, it asserts:
#
#   1. The closure is exactly two files: the script may source only
#      `scripts/lib/seed-sums.sh`. A new `source` line fails here until
#      this gate's closure is extended.
#   2. No member invokes a tool from `NET_PAT` below or names an
#      `https?://` URL. Comments are stripped first, so a comment naming
#      a tool does not trip it. The ablations plant real invocations to
#      prove the search can fire.
#
# It does not rebuild offline: removing a CI runner's network needs
# privileges a portable gate cannot assume. When the closure changes,
# run the bootstrap by hand under `podman run --network=none` with
# `llc`, `cc`, python3 and git, and confirm it reaches stage2 == stage3.
#
# It needs no compiler, `llc` or network, so it skips `gate_init`.
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
# understood. The closure check refuses a relative or computed source
# line rather than resolving it.
closure_sources() {
  grep -E '^[[:space:]]*source ' "$1" \
    | sed -E 's/^[[:space:]]*source "\$repo_root\///; s/"$//' \
    | LC_ALL=C sort -u
}

# stripped <file>: the file with `#` comments removed. A `#` inside a
# quoted string over-strips. Since stripping can only hide text, the risk
# is a false pass, which ablation (a) guards against.
stripped() { sed 's/#.*//' "$1"; }

# One alternation, so an ablation plants one line and the error names
# the tool it found.
NET_PAT='\b(curl|wget|ssh|scp|sftp|ftp|telnet|nc|ncat|git|gh|cargo|rustc|npm|yarn|pnpm|pip|brew|apt-get|apt|dnf|pacman|apk)\b|https?://'

# check_closure <bootstrap-file> <sourced-path> <sourced-file>: both
# assertions over explicit paths, so the ablations run the real checks
# against doctored copies instead of a reimplementation of them.
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

# (a) A real curl invocation in the bootstrap. The comment planted above
# it names no tool, so only the code line can trip the search.
cp "$pdir/boot.sh" "$pdir/a.sh"
printf '\n# fetch the blessed seed instead of trusting the checkout\ncurl -fsSL https://example.com/seed.ll -o "$work/seed.ll"\n' >> "$pdir/a.sh"
probe_mode=1; probe_failed=0; probe_first=""
check_closure "$pdir/a.sh" "$SEED_SUMS" "$pdir/sums.sh"
probe_mode=0
if (( probe_failed )); then ok "probe: a bootstrap that curls a seed is refused ($probe_first)"
else fail "probe: a bootstrap invoking curl was accepted"; fi

# (b) A widened closure. The extra file exists and is clean, so only the
# widening itself can be refused.
printf '# nothing networked here\n' > "$pdir/evil.sh"
cp "$pdir/boot.sh" "$pdir/b.sh"
printf '\nsource "$repo_root/scripts/lib/evil.sh"\n' >> "$pdir/b.sh"
probe_mode=1; probe_failed=0; probe_first=""
check_closure "$pdir/b.sh" "$SEED_SUMS" "$pdir/sums.sh"
probe_mode=0
if (( probe_failed )); then ok "probe: a bootstrap sourcing a third file is refused ($probe_first)"
else fail "probe: a widened closure was accepted"; fi

# (c) A network invocation in the sourced file. The bootstrap is clean,
# and the check must still fail, or the sourced file goes unaudited.
cp "$pdir/sums.sh" "$pdir/c-sums.sh"
printf '\ngit ls-remote https://example.com/repo >/dev/null\n' >> "$pdir/c-sums.sh"
probe_mode=1; probe_failed=0; probe_first=""
check_closure "$pdir/boot.sh" "$SEED_SUMS" "$pdir/c-sums.sh"
probe_mode=0
if (( probe_failed )); then ok "probe: a git invocation in the sourced half is refused ($probe_first)"
else fail "probe: a networked $SEED_SUMS was accepted"; fi

# (d) A bootstrap that sources nothing recognisable. Without this floor,
# deleting every source line would pass as the smallest closure.
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
