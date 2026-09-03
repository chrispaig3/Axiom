#!/usr/bin/env bash
# Regenerate the checked-in bootstrap seeds from the current tree, with
# a compiler descended from the COMMITTED seed, and record the link.
#
# Run this when `scripts/bootstrap-from-seed.sh` fails because the
# committed seed can no longer compile self_host/ - that is the seed
# going stale, and it is the only routine reason to move it. Advancing
# it otherwise is optional and costs about 42 MB of generated text in
# the diff - six files of 7.06 MB, measured 2026-08-29 - so do it on
# purpose.
#
# The seeds are the compiler's own LLVM IR, one per target, produced by
# the compiler currently in the tree. Every target is generated from a
# single host, which is exactly what scripts/check-cross-targets.sh
# already proves is sound - the target decides the syscall ABI and the
# triple, not the machine doing the compiling. Measured 2026-08-29: the
# six files differ from one another in at most 342 lines of 180,774
# (darwin-aarch64 against linux-x86_64), and the two x86_64 BSDs, which
# share a syscall template, in 139.
#
# WHO GENERATES. The generator is built here, from the committed seed
# and nothing else: the host's `bootstrap/axiom-<target>.ll` through
# `llc` and `cc` is the previous compiler, it compiles this tree, and
# the result - `gen` - emits the six seeds. So the seed about to be
# committed is, by construction, the previous seed's emission of this
# tree or that emission's own re-emission, which is what
# `scripts/check-seed-lineage.sh` replays and what a row of
# `bootstrap/CHAIN` records. This script writes that row.
#
# It used to build `gen` with whatever `$AXIOM` named - "the previous
# commit's `.axiom-bin/axiom` is the usual answer", the comment said -
# and five of the fourteen reseeds in this repository's history were
# generated that way from a compiler built out of an UNCOMMITTED tree:
# three of the committed seeds (`1c682ef`, `24bdf29`, `79c8ebc`) are
# not their own tree's emission and cannot be reproduced from anything
# in the history, measured 2026-08-29 by replaying every link. A seed
# nothing can reproduce is a seed that has to be taken on trust, which
# is the one thing `bootstrap/` exists not to ask.
#
# WHEN THE COMMITTED SEED CANNOT COMPILE THE TREE - the routine reason
# to be here - this script says so and STOPS. That is the moment a link
# would break, and it must be recorded rather than papered over:
#
#   scripts/reseed.sh --bridge /path/to/a/compiler/that/can
#
# generates with the named compiler and writes the row as
# `bridge-needed`, which the gate refuses until it is replaced by a
# method that replays (a `mixed-tree` or a `walk`; see the CHAIN header).
# The way to never need it is the seed-skew rule: land the construct
# the compiler must learn, reseed, THEN use it.
#
# The seeds are REPRODUCIBLE - scripts/check-reproducible.sh is the gate
# that says so - which means re-running this against an unchanged tree
# brings the six `.ll` files and `SHA256SUMS` back byte-identical. If
# one of THOSE moves without the compiler moving, the compiler has a
# nondeterminism bug and that is the thing to fix.
#
# `bootstrap/STAMP` is the exception and always moves: it records the
# time, which is `bootstrap/README.md`'s point about it being the one
# file there carrying no signal about the compiler. So `git status` is
# NOT clean after a no-op reseed, and this comment used to say it was -
# which turned the one file whose movement means nothing into the
# evidence for a bug that had not happened.

set -uo pipefail

# Not `gate_init`: that preamble bootstraps a compiler from the
# committed seed when none is installed, and refuses when it cannot -
# which is exactly the situation this script exists to handle, and it
# must be the one to say so. The helpers are all that is needed.
source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/seed-sums.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1
link_entry="$(gate_link_entry)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

bridge=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bridge) bridge="${2:-}"; [[ -x "$bridge" ]] || fail "--bridge needs an executable compiler"; shift 2 ;;
    *) fail "unknown argument $1 (usage: $0 [--bridge COMPILER])" ;;
  esac
done

command -v git >/dev/null || fail "git is not on PATH"
command -v llc >/dev/null || fail "llc is not on PATH"
command -v cc  >/dev/null || fail "cc is not on PATH"
have_opt=0; command -v opt >/dev/null && have_opt=1

case "$(uname -s)" in
  Darwin)  os=darwin ;;
  Linux)   os=linux ;;
  FreeBSD) os=freebsd ;;
  *) fail "no seed for $(uname -s)" ;;
esac
case "$(uname -m)" in
  arm64|aarch64) arch=aarch64 ;;
  x86_64|amd64)  arch=x86_64 ;;
  *) fail "unsupported architecture $(uname -m)" ;;
esac
host="$os-$arch"

# One list, in `scripts/lib/seed-sums.sh`. It was written out here and
# in `check-seed-provenance.sh` and implied by `bootstrap/SHA256SUMS`,
# the files on disk and `bootstrap/README.md`'s box - five copies of one
# fact that nothing compared. `check-seed-supply-chain.sh` compares them
# now, and this is the copy it treats as the declaration.
targets="$(seed_targets | tr '\n' ' ')"

# --------------------------------------------------------------------
# The previous seed: the commit that last wrote the six `.ll` files,
# and the files in the tree must be that commit's - a seed edited in
# the working tree has no lineage to record.
# --------------------------------------------------------------------
prev="$(git log -1 --format=%h -- 'bootstrap/*.ll' 2>/dev/null || true)"
[[ -n "$prev" ]] || fail "no commit in history touches bootstrap/*.ll (a shallow clone cannot reseed)"
if ! git diff --quiet HEAD -- 'bootstrap/*.ll'; then
  fail "bootstrap/*.ll differs from HEAD in the working tree; restore the committed seed first (git checkout -- bootstrap/), or the row this writes would name a seed nothing wrote"
fi
echo "the committed seed is ${prev}'s"

ln -s "$repo_root/stdlib"    "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"
cp "$repo_root/self_host/main.ax" "$work/in.ax"

optimised() {
  if (( have_opt )) && opt -O1 "$1" -S -o "$2" 2>/dev/null; then printf '%s' "$2"; else printf '%s' "$1"; fi
}
build_compiler() {  # <in.ll> <out>
  llc -filetype=obj -relocation-model=pic "$(optimised "$1" "$2.opt.ll")" -o "$2.o" 2>"$2.err" \
    && cc "$2.o" -o "$2" $link_entry 2>>"$2.err"
}
emit() {  # <compiler> <target> <out.ll>: the shape every seed is emitted in
  ( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" "$1" in.ax "$2" > "$3" 2> "$3.err" ) || return 1
  grep -q '^target triple' "$3" || return 1
  (( $(wc -l < "$3") > 10000 )) || return 1
}

# --------------------------------------------------------------------
# The generator, from the committed seed.
# --------------------------------------------------------------------
method="seed"; stage=""; generator=""
t0=$SECONDS
build_compiler "bootstrap/axiom-$host.ll" "$work/seed" \
  || { head -3 "$work/seed.err" >&2; fail "the committed $host seed does not build"; }
echo "the $prev seed is built ($((SECONDS - t0))s)"
if emit "$work/seed" "$host" "$work/d1.ll"; then
  build_compiler "$work/d1.ll" "$work/gen" \
    || { head -3 "$work/gen.err" >&2; fail "the ${prev} seed compiled this tree, but the result does not build"; }
  echo "the $prev seed compiled this tree into the generator ($((SECONDS - t0))s)"
else
  echo "the committed seed (${prev}) cannot compile this tree:" >&2
  sed 's/\x1b\[[0-9;]*m//g' "$work/d1.ll.err" | grep -iE 'error|fault' | head -5 | sed 's/^/    /' >&2
  [[ -s "$work/d1.ll.err" ]] || echo "    (no diagnostic; $(wc -l < "$work/d1.ll" | tr -d ' ') lines emitted)" >&2
  if [[ -z "$bridge" ]]; then
    echo >&2
    echo "The link from the ${prev} seed to the seed you are about to generate needs a" >&2
    echo "bridge, and this script will not build one silently. Either land the construct" >&2
    echo "the seed cannot compile in a form the seed CAN compile first (the seed-skew" >&2
    echo "rule: definition, reseed, then use), or generate with a compiler that can:" >&2
    echo "    scripts/reseed.sh --bridge /path/to/compiler" >&2
    echo "which records the row as \`bridge-needed\` for scripts/check-seed-lineage.sh to" >&2
    echo "refuse until the link is certified (bootstrap/CHAIN's header says how)." >&2
    exit 1
  fi
  echo "generating with the bridge compiler $bridge instead, and recording that"
  if ! "$bridge" build --input self_host/main.ax --output "$work/gen" >"$work/build.log" 2>&1; then
    tail -20 "$work/build.log" >&2
    fail "could not build a generator with $bridge either"
  fi
  method="bridge-needed"; stage="-"; generator="generator=$(gate_sha "$bridge" | cut -c1-12)"
fi
echo "generator built"

mkdir -p bootstrap
# Six since 2026-08-29. The FreeBSD pair were minted the commit after
# `targetCode` learned their names, which is the only order that works:
# a seed can be emitted only by a compiler that knows the target, and
# `gen` here is built from THIS tree and is what emits.
for t in $targets; do
  emit "$work/gen" "$t" "$work/out-$t.ll" \
    || { head -3 "$work/out-$t.ll.err" >&2; fail "could not emit the seed for $t (a seed that is empty or the wrong target fails far from here)"; }
done
# The stage the link will replay at: the previous seed's own emission
# of this tree is stage1, and equals the new seed when the two
# compilers agree byte for byte; otherwise the generator's emission is
# the new seed and the link is stage2, by construction.
if [[ "$method" == seed ]]; then
  if cmp -s "$work/d1.ll" "$work/out-$host.ll"; then stage="stage1"; else stage="stage2"; fi
fi
secs=$((SECONDS - t0))
for t in $targets; do
  mv "$work/out-$t.ll" "bootstrap/axiom-$t.ll"
  printf '  %-16s %8d bytes  %7d lines\n' "$t" "$(wc -c <"bootstrap/axiom-$t.ll")" "$(wc -l <"bootstrap/axiom-$t.ll")"
done

( cd bootstrap && { command -v sha256sum >/dev/null && sha256sum axiom-*.ll || shasum -a 256 axiom-*.ll; } ) \
  > bootstrap/SHA256SUMS
echo "wrote bootstrap/SHA256SUMS"

# THE STAMP RECORDS A HASH, NOT A COMMIT, and that is a correction
# rather than a preference. This wrote `git rev-parse HEAD`, and the
# routine reason to run `reseed.sh` is that `self_host/` has just
# changed - so the tree is DIRTY here by construction, and HEAD is the
# commit before the one that will carry the seed. The recorded commit
# was therefore wrong every time, and nothing read it, so nothing said
# so: measured 2026-08-25, it named `ee0e4e1` while the seed was
# `93a74e5`'s emission, differing by 1,532 lines.
#
# A hash of the bytes that were actually read cannot have that failure
# mode. `scripts/check-seed-provenance.sh` resolves the commit the
# other way - the one that last touched the six `.ll` files - and requires its
# sources to hash to this line before regenerating from them.
stamp="$(gate_seed_source_stamp "$repo_root")"
nfiles="$( cd "$repo_root" && find self_host stdlib -name '*.ax' -type f | wc -l | tr -d ' ' )"
{
  printf 'Source stamp:          %s\n' "$stamp"
  printf 'Source files:          %s\n' "$nfiles"
  printf 'Generated on:          %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # THE HOST, so that a second witness can be named as one.
  #
  # The committed seed is generated here, on darwin-aarch64, and
  # `check-seed-provenance.sh` regenerates it byte-identically on
  # `ubuntu-latest`. That is two toolchains on two operating systems
  # agreeing on 1.2 M lines of IR, which is a stronger fact than the
  # regeneration alone - and until this line existed nothing recorded
  # which host generated the seed, so nothing could tell the two-host
  # case from the one-host case, and nothing would have noticed the
  # property quietly becoming the second. The provenance gate reads this
  # line when it is there and reports ABSENT when it is not; it never
  # reads absence as agreement.
  #
  # `llc` is in it because `llc` is on the trust base
  # (`bootstrap/THREATS.md`, row 5): two hosts running the same `llc`
  # build are less of a second witness than two running different ones,
  # and that is a difference a reader should be able to see.
  # `.*LLVM version` and not `^ *LLVM version`: Homebrew's llc prints
  # "Homebrew LLVM version 23.1.0" and the anchored pattern this first
  # had matched nothing, which would have written `darwin-aarch64 ()` -
  # a recorded fact silently emptied, in the file whose whole subject is
  # facts that cannot be wrong when they are written. Measured here
  # 2026-09-03 before it could be committed.
  printf 'Generated on host:     %s (llc %s)\n' "$host" \
    "$(llc --version 2>/dev/null | sed -n 's/.*LLVM version *//p' | head -1 | tr -d '\n')"
  printf 'Regenerate with:       scripts/reseed.sh\n'
  printf 'Verified by:           scripts/bootstrap-from-seed.sh, scripts/check-seed-provenance.sh, scripts/check-seed-lineage.sh\n'
  printf '\n'
  printf 'The source stamp is `gate_seed_source_stamp` (scripts/lib/gate.sh) over\n'
  printf 'the `self_host/**.ax` and `stdlib/**.ax` bytes these seeds were\n'
  printf 'generated from: the path list, then every byte, hashed. It is the\n'
  printf 'CHECKABLE claim here, and `scripts/check-seed-provenance.sh` checks it -\n'
  printf 'it finds the commit that last touched the six `.ll` files - not this\n'
  printf 'directory, which also holds metadata about them - requires that\n'
  printf "commit's sources to hash to this line, and then regenerates all six\n"
  printf 'seeds from them and requires the result to be byte-identical.\n'
  printf '\n'
  printf '`Generated on host:` is a REPORT, not a claim: nothing can check where\n'
  printf 'a file was written. It is here so that when the provenance gate\n'
  printf 'regenerates these bytes on a different host it can say so - two\n'
  printf 'toolchains agreeing is more than one repeating itself - and so that the\n'
  printf 'day it stops being a different host, that is visible rather than silent.\n'
} > bootstrap/STAMP
cat bootstrap/STAMP

# --------------------------------------------------------------------
# The row. The seed's own commit does not exist yet - the same reason
# STAMP records a hash - so the row says `next`, and the gate resolves
# it to the commit that last wrote the `.ll` files.
#
# This only ever APPENDS a row, or rewrites the `next` in the last one,
# and `bootstrap/CHAIN.checkpoint` never covers a `next` row - so a
# reseed does not void the checkpoint and needs no re-blessing. The new
# link is outside the certified prefix, which means it is replayed on
# every run until someone blesses it. That is the intended direction:
# blessing is a deliberate act, and the rows waiting for one are visible
# in what the gate replays. The NEXT reseed
# replaces `next` with the hash it can then see. A `next` row whose
# `from` is still the committed seed is a reseed that was never
# committed, and is replaced rather than chained from.
# --------------------------------------------------------------------
chain="bootstrap/CHAIN"
[[ -f "$chain" ]] || fail "$chain is missing; every seed since 2026-08-29 has a row, and this one must too"
row="next $prev $method $stage $secs${generator:+ $generator}"
last="$(grep -vE '^[[:space:]]*(#|$)' "$chain" | tail -1)"
set -- $last
if [[ "${1:-}" == next ]]; then
  if [[ "${2:-}" == "$prev" ]]; then
    echo "the last row of $chain is an uncommitted reseed from $prev; replacing it"
    n="$(grep -nvE '^[[:space:]]*(#|$)' "$chain" | tail -1 | cut -d: -f1)"
    sed "${n}d" "$chain" > "$chain.new" && mv "$chain.new" "$chain"
  else
    echo "the last row of $chain was written as \`next\` and its seed is now ${prev}; naming it"
    awk -v h="$prev" '{ if ($1 == "next") { $1 = h; print; } else print }' "$chain" > "$chain.new" && mv "$chain.new" "$chain"
  fi
fi
printf '%s\n' "$row" >> "$chain"
echo "appended to $chain: $row"

echo
if [[ "$method" == seed ]]; then
  echo "seeds regenerated from the ${prev} seed's own compile of this tree ($stage);"
  echo "run scripts/bootstrap-from-seed.sh before committing them, and commit bootstrap/ whole"
else
  echo "seeds regenerated with a BRIDGE compiler; scripts/check-seed-lineage.sh is red until the"
  echo "\`bridge-needed\` row in $chain is replaced by a method that replays"
fi
