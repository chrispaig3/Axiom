# The seed set, and the check that `bootstrap/SHA256SUMS` covers it.
#
# WHY THIS IS ITS OWN FILE AND NOT `gate.sh`. Two of the four consumers
# cannot have `gate.sh`. `scripts/bootstrap-from-seed.sh` is the path a
# fresh clone with no Axiom toolchain takes, and it deliberately sources
# nothing (its own comment says so): `gate.sh`'s preamble is what it
# would be running if there were already a compiler. `scripts/reseed.sh`
# sources `gate.sh` but never calls `gate_init`, for the same reason.
# So the seed-integrity check lives HERE - pure shell, no `$AXIOM`, no
# work directory, no trap, nothing built - and every consumer sources
# this one file. That is the point: the gate that probes this code must
# probe the code a clone actually runs, not a second copy of it.
#
# WHAT `seed_sums_verify` ADDS TO `shasum -c`, WHICH IS THE WHOLE REASON
# IT EXISTS. `shasum -a 256 -c SHA256SUMS` checks every row it is given
# and says nothing about a row it was NOT given. Measured 2026-09-03 in
# a three-file scratch directory: delete `axiom-b.ll`'s row, replace
# `axiom-b.ll` with the word BACKDOOR, and the check prints
#
#     axiom-a.ll: OK
#     axiom-c.ll: OK
#
# and exits 0. Until this file existed, that was the outcome on the one
# path that has no CI, no compiler and no second opinion. A corruption
# check that a deletion walks past is not even a corruption check.
#
# So the rows and the files on disk are compared as SETS, both
# directions, before a single hash is verified. The set on disk is
# derived at run time rather than read from `seed_targets` below,
# because those two facts are allowed to differ for one commit - a new
# target's seed lands before every list learns its name - and the fresh
# clone's question is "is every seed I have covered", not "is the list
# current". `scripts/check-seed-supply-chain.sh` is where the lists are
# held to each other.
#
# This changes what SHA256SUMS proves and nothing more. It is still a
# corruption check and not a trust check - the hash and the file are
# committed together and move together, which is what
# `check-seed-provenance.sh` and `check-seed-lineage.sh` answer. What it
# is now is a corruption check that a deletion cannot walk past.

# The six targets a seed is committed for, one per line.
#
# CONSUMERS, and a new one belongs in this list:
#   scripts/reseed.sh                    generates one seed per target
#   scripts/check-seed-provenance.sh     regenerates and compares all six
#   scripts/check-seed-supply-chain.sh   holds the five copies together
#
# NOT a consumer, and conflating them would be a real error:
# `scripts/check-cross-targets.sh` names SEVEN targets. The seventh is
# `windows-x86_64`, which the compiler cross-emits for and which has no
# seed in `bootstrap/`, because hosting the compiler on Windows is a
# later phase. "Targets the compiler emits" and "targets a clone can
# bootstrap on" are two different facts and one list cannot be both.
seed_targets() {
  cat <<'TARGETS'
darwin-aarch64
darwin-x86_64
freebsd-aarch64
freebsd-x86_64
linux-aarch64
linux-x86_64
TARGETS
}

# seed_sums_verify <bootstrap-dir>
#
# 0 when every `.ll` in the directory is named by exactly one row of its
# SHA256SUMS, every row names a file that is there, and every hash
# matches. Non-zero otherwise, with the reason on stderr, naming the
# file rather than leaving it to surface as a link error three steps
# downstream.
seed_sums_verify() {
  local dir="$1" sums="$1/SHA256SUMS" rc=0 tmp
  if [[ ! -f "$sums" ]]; then
    echo "$sums is missing: an unverifiable seed is not a seed" >&2
    return 1
  fi
  tmp="$(mktemp -d)" || return 1

  # The files present, and the rows. `shasum` writes `<hash>  <name>`
  # with two spaces, so the name is everything after the first run of
  # blanks - `awk '{print $2}'` would truncate a name containing one,
  # which no seed has and which the bare-name check below refuses.
  ls -1 "$dir" 2>/dev/null | grep '\.ll$' | LC_ALL=C sort > "$tmp/on-disk"
  sed -n 's/^[0-9a-fA-F]\{64\}[[:space:]][[:space:]]*//p' "$sums" \
    | LC_ALL=C sort > "$tmp/listed"

  if [[ ! -s "$tmp/listed" ]]; then
    echo "$sums names no seed: it is empty, or no line is a 64-hex hash and a name" >&2
    rm -rf "$tmp"
    return 1
  fi

  # A row naming `../elsewhere.ll` would be verified from beside the
  # sums file and compared against something outside it.
  if grep -q '/' "$tmp/listed"; then
    echo "$sums names a path rather than a bare filename:" >&2
    grep '/' "$tmp/listed" | sed 's/^/    /' >&2
    rc=1
  fi

  # Two rows for one file: the second is never reached by a reader
  # deciding what the seed should hash to, and `shasum -c` verifies the
  # file twice rather than reporting the disagreement between them.
  if [[ "$(LC_ALL=C sort -u "$tmp/listed" | wc -l)" != "$(wc -l < "$tmp/listed")" ]]; then
    echo "$sums names a file more than once:" >&2
    LC_ALL=C uniq -d "$tmp/listed" | sed 's/^/    /' >&2
    rc=1
  fi

  # The two directions, separately, because they are two different
  # facts. A seed on disk with no row is the one that walks past
  # `shasum -c` unremarked; a row with no seed is a file that went
  # missing, which `shasum -c` does already report.
  if [[ -n "$(LC_ALL=C comm -23 "$tmp/on-disk" "$tmp/listed")" ]]; then
    echo "$dir holds a seed that $sums does not name - its bytes are checked by nothing:" >&2
    LC_ALL=C comm -23 "$tmp/on-disk" "$tmp/listed" | sed 's/^/    /' >&2
    rc=1
  fi
  if [[ -n "$(LC_ALL=C comm -13 "$tmp/on-disk" "$tmp/listed")" ]]; then
    echo "$sums names a seed that is not in $dir:" >&2
    LC_ALL=C comm -13 "$tmp/on-disk" "$tmp/listed" | sed 's/^/    /' >&2
    rc=1
  fi

  if (( rc != 0 )); then
    rm -rf "$tmp"
    return 1
  fi

  # Only now the hashes, and from beside the files, because the rows
  # name them bare.
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$dir" && sha256sum -c SHA256SUMS) > "$tmp/log" 2>&1 || rc=1
  else
    (cd "$dir" && shasum -a 256 -c SHA256SUMS) > "$tmp/log" 2>&1 || rc=1
  fi
  if (( rc != 0 )); then
    sed 's/^/    /' "$tmp/log" >&2
    echo "a seed in $dir does not match its recorded hash" >&2
  fi
  rm -rf "$tmp"
  return $rc
}
