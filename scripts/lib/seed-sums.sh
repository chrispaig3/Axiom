# The seed set, and the check that `bootstrap/SHA256SUMS` covers it.
#
# It is pure shell, kept out of `gate.sh`, because some consumers must
# not run the gate preamble. `scripts/bootstrap-from-seed.sh` runs on a
# fresh clone with no Axiom toolchain and sources nothing else, and
# `scripts/reseed.sh` never calls `gate_init`. So this file needs no
# `$AXIOM`, work directory or trap, and builds nothing. Every consumer
# sources it, so the gate that probes it probes the code a clone runs.
#
# `shasum -a 256 -c SHA256SUMS` checks only the rows it is given. Drop a
# seed's row, replace the seed, and it still prints OK for the rest and
# exits 0. So `seed_sums_verify` compares the rows and the `.ll` files on
# disk as sets, in both directions, before checking any hash.
#
# The on-disk set is read at run time, not from `seed_targets`, because a
# new target's seed can land before every list learns its name. A fresh
# clone asks "is every seed I have covered?", not "is the list current?".
# `scripts/check-seed-supply-chain.sh` holds the lists to each other.
#
# This is a corruption check, not a trust check: a seed and its hash are
# committed together. `check-seed-provenance.sh` and
# `check-seed-lineage.sh` answer the trust question.

# The six targets a seed is committed for, one per line.
#
# Consumers (add any new one here):
#   scripts/reseed.sh                    generates one seed per target
#   scripts/check-seed-provenance.sh     regenerates and compares all six
#   scripts/check-seed-supply-chain.sh   holds the five copies together
#
# `scripts/check-cross-targets.sh` keeps its own, longer list. It adds
# `windows-x86_64` and `windows-aarch64`, which the compiler cross-emits
# for but which have no seed, because the compiler does not run on
# Windows. Targets the compiler emits and targets a clone can bootstrap
# on are different facts, so one list cannot serve both.
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
# Returns 0 when every `.ll` in the directory has exactly one row in its
# SHA256SUMS, every row names a file that is there, and every hash
# matches. Otherwise it returns non-zero and names the file on stderr, so
# the fault does not surface later as a link error.
seed_sums_verify() {
  local dir="$1" sums="$1/SHA256SUMS" rc=0 tmp
  if [[ ! -f "$sums" ]]; then
    echo "$sums is missing: an unverifiable seed is not a seed" >&2
    return 1
  fi
  tmp="$(mktemp -d)" || return 1

  # The files present, and the rows. `shasum` writes `<hash>  <name>`, so
  # the name is everything after the first run of blanks. `awk '{print $2}'`
  # would truncate a name containing a blank.
  ls -1 "$dir" 2>/dev/null | grep '\.ll$' | LC_ALL=C sort > "$tmp/on-disk"
  sed -n 's/^[0-9a-fA-F]\{64\}[[:space:]][[:space:]]*//p' "$sums" \
    | LC_ALL=C sort > "$tmp/listed"

  if [[ ! -s "$tmp/listed" ]]; then
    echo "$sums names no seed: it is empty, or no line is a 64-hex hash and a name" >&2
    rm -rf "$tmp"
    return 1
  fi

  # A row naming `../elsewhere.ll` would verify a file outside the directory.
  if grep -q '/' "$tmp/listed"; then
    echo "$sums names a path rather than a bare filename:" >&2
    grep '/' "$tmp/listed" | sed 's/^/    /' >&2
    rc=1
  fi

  # Two rows for one file leave its expected hash ambiguous, and
  # `shasum -c` checks the file twice without reporting the duplicate.
  if [[ "$(LC_ALL=C sort -u "$tmp/listed" | wc -l)" != "$(wc -l < "$tmp/listed")" ]]; then
    echo "$sums names a file more than once:" >&2
    LC_ALL=C uniq -d "$tmp/listed" | sed 's/^/    /' >&2
    rc=1
  fi

  # Each direction separately. A seed with no row is the case `shasum -c`
  # misses. A row with no seed is a missing file, which `shasum -c` does
  # report.
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

  # Only now the hashes, run from inside the directory because the rows
  # name the files bare.
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
