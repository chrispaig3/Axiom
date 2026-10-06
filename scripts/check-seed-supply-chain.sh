#!/usr/bin/env bash
# The seed's supply chain: its facts agree with each other, and the
# integrity check it rests on cannot be walked past.
#
# This is not a third seed-trust gate. `check-seed-provenance.sh` proves
# the seed is the emission of source in this history, and
# `check-seed-lineage.sh` proves the compiler that emitted it descends,
# by replayable steps, from a Rust compiler no Axiom seed ever touched.
# Do not rebuild those here. This gate holds five properties around them:
#
#   1. The seed-target set is one fact. `seed_targets`
#      (`scripts/lib/seed-sums.sh`) declares it. `reseed.sh` and
#      `check-seed-provenance.sh` must derive their lists from it, and
#      `bootstrap/SHA256SUMS`, the `.ll` files and `bootstrap/README.md`'s
#      box must agree with it. A target missing from the regenerator
#      would be a seed no gate regenerates.
#
#   2. `SHA256SUMS` accounts for every seed. `shasum -a 256 -c` checks
#      only the rows it is given, so removing a row and replacing the
#      file it named exits 0. Section 2 runs that attack against the
#      code a fresh clone runs.
#
#   3. Every `yes` row of `bootstrap/THREATS.md` names a gate that exists
#      and that CI runs, or it is a promise nobody keeps.
#
#   4. The lineage gate still reads its own text to assert that no
#      seed-descended Axiom binary runs on its compared path. That
#      self-read is one deleted line from being absent, and its absence
#      is silent. Section 4 requires the marker and the grep, in that
#      order.
#
#   5. The Rust anchor's size, "28,082 lines", tells a reader what
#      auditing the trust root costs. Every site that states it must
#      agree, with each other and with `bb730db`.
#
# It needs no compiler, no `llc` and no network: pure shell over the
# tree, about a second. That is why it does not use `gate_init`.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1
source "$repo_root/scripts/lib/seed-sums.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failed=0
# In probe mode a failure is the expected outcome, so it is counted
# rather than reported. As with `check-seed-lineage.sh`'s `probe_mode`,
# the probe runs the real checking code rather than a copy of it.
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

# ---------------------------------------------------------------------
echo "== 1. the six-target set is one fact, and its copies agree =="
# ---------------------------------------------------------------------
# The declaration is `seed_targets`. Everything else is compared to it.
seed_targets | LC_ALL=C sort > "$work/declared"
ndeclared="$(wc -l < "$work/declared" | tr -d ' ')"

# A floor, because every comparison below is against this file: an empty
# or truncated declaration would make them all agree about nothing and
# pass. The floor is 5, low enough that retiring one target does not
# trip it.
if (( ndeclared < 5 )); then
  echo "FAIL: seed_targets names only $ndeclared targets; the floor is 5"
  echo "      Every comparison in this section is against that list, so a"
  echo "      truncated one makes the section vacuous rather than red."
  exit 1
fi
ok "seed_targets declares $ndeclared targets"

# The three derivations, each from a real file so a probe can point them
# at a tampered copy.
targets_on_disk() {   # <bootstrap-dir>
  ls -1 "$1" 2>/dev/null | sed -n 's/^axiom-\(.*\)\.ll$/\1/p' | LC_ALL=C sort
}
targets_in_sums() {   # <SHA256SUMS>
  sed -n 's/^[0-9a-fA-F]\{64\}[[:space:]][[:space:]]*axiom-\(.*\)\.ll$/\1/p' "$1" \
    | LC_ALL=C sort
}
# The fenced box at the top of bootstrap/README.md. Anchored on the
# `axiom-<target>.ll` shape and not on line numbers, which move.
targets_in_readme() { # <README.md>
  sed -n 's/^axiom-\([a-z0-9_]*-[a-z0-9_]*\)\.ll.*$/\1/p' "$1" | LC_ALL=C sort
}

# compare_targets <label> <file of names>
compare_targets() {
  local label="$1" got="$2" missing extra
  missing="$(LC_ALL=C comm -23 "$work/declared" "$got")"
  extra="$(LC_ALL=C comm -13 "$work/declared" "$got")"
  if [[ -z "$missing" && -z "$extra" ]]; then
    ok "$label names the same $ndeclared targets"
    return 0
  fi
  [[ -z "$missing" ]] || fail "$label does not name: $(echo "$missing" | tr '\n' ' ')"
  [[ -z "$extra"   ]] || fail "$label names a target seed_targets does not: $(echo "$extra" | tr '\n' ' ')"
  return 1
}

targets_on_disk   bootstrap             > "$work/disk"
targets_in_sums   bootstrap/SHA256SUMS  > "$work/sums"
targets_in_readme bootstrap/README.md   > "$work/readme"
compare_targets "the .ll files in bootstrap/" "$work/disk"
compare_targets "bootstrap/SHA256SUMS"        "$work/sums"
compare_targets "bootstrap/README.md's box"   "$work/readme"

# The two generators must derive their list, not restate it. Comparing
# the files alone would not notice a hand-written `targets=` line
# returning.
for s in scripts/reseed.sh scripts/check-seed-provenance.sh; do
  if grep -qE '^[[:space:]]*targets=.*(darwin|linux|freebsd)' "$s"; then
    fail "$s writes the target list out by hand again; it must call seed_targets"
  elif grep -q 'seed_targets' "$s"; then
    ok "$s derives its targets from seed_targets"
  else
    fail "$s names no target list at all - has it stopped generating seeds?"
  fi
done

# -- the ablations for section 1 --------------------------------------
#
# Each probe puts a tampered copy through the same `compare_targets`,
# which must refuse it:
#
#   (1a) SHA256SUMS with axiom-linux-x86_64.ll's row removed:
#        "bootstrap/SHA256SUMS (probe) does not name: linux-x86_64"
#   (1b) an unlisted seed axiom-linux-riscv64.ll on disk:
#        "the .ll files (probe) names a target seed_targets does not: linux-riscv64"
#   (1c) README.md's box with the darwin-x86_64 line deleted:
#        "bootstrap/README.md's box (probe) does not name: darwin-x86_64"
#
# The real files pass the same comparison above, so a comparator that
# refuses everything cannot satisfy this section.
pdir="$work/probe1"; mkdir -p "$pdir"
cp bootstrap/SHA256SUMS bootstrap/README.md "$pdir/"
for t in $(cat "$work/declared"); do : > "$pdir/axiom-$t.ll"; done

grep -v 'axiom-linux-x86_64\.ll' "$pdir/SHA256SUMS" > "$pdir/SUMS.dropped"
if cmp -s "$pdir/SUMS.dropped" "$pdir/SHA256SUMS"; then
  fail "probe 1a removed no row from a copy of SHA256SUMS"
else
  targets_in_sums "$pdir/SUMS.dropped" > "$pdir/t"
  probe_mode=1; probe_failed=0; probe_first=""
  compare_targets "bootstrap/SHA256SUMS (probe)" "$pdir/t"
  probe_mode=0
  if (( probe_failed )); then ok "probe: SHA256SUMS with a row removed is refused ($probe_first)"
  else fail "probe: SHA256SUMS with axiom-linux-x86_64.ll's row removed was accepted"; fi
fi

: > "$pdir/axiom-linux-riscv64.ll"
targets_on_disk "$pdir" > "$pdir/t"
probe_mode=1; probe_failed=0; probe_first=""
compare_targets "the .ll files (probe)" "$pdir/t"
probe_mode=0
if (( probe_failed )); then ok "probe: a seventh unlisted seed on disk is refused ($probe_first)"
else fail "probe: an unlisted axiom-linux-riscv64.ll was accepted"; fi
rm -f "$pdir/axiom-linux-riscv64.ll"

grep -v '^axiom-darwin-x86_64\.ll' "$pdir/README.md" > "$pdir/README.dropped"
if cmp -s "$pdir/README.dropped" "$pdir/README.md"; then
  fail "probe 1c removed no line from a copy of bootstrap/README.md"
else
  targets_in_readme "$pdir/README.dropped" > "$pdir/t"
  probe_mode=1; probe_failed=0; probe_first=""
  compare_targets "bootstrap/README.md's box (probe)" "$pdir/t"
  probe_mode=0
  if (( probe_failed )); then ok "probe: README's box with a target dropped is refused ($probe_first)"
  else fail "probe: bootstrap/README.md's box missing darwin-x86_64 was accepted"; fi
fi

# ---------------------------------------------------------------------
echo
echo "== 2. SHA256SUMS accounts for every seed present =="
# ---------------------------------------------------------------------
# `seed_sums_verify` is the function `scripts/bootstrap-from-seed.sh`
# and `scripts/check-bootstrap.sh` call, sourced from the same file.
# This section runs that function, so a probe that passes here is a
# statement about the code a clone executes.
if seed_sums_verify bootstrap 2> "$work/real.log"; then
  ok "the tree's own bootstrap/ passes seed_sums_verify"
else
  sed 's/^/     /' "$work/real.log"
  fail "the tree's own bootstrap/ does not pass seed_sums_verify"
fi

# The attack, on a copy of the real seeds: drop a row, then replace the
# seed it named.
p2="$work/probe2"; mkdir -p "$p2"
cp bootstrap/*.ll bootstrap/SHA256SUMS "$p2/"
victim=axiom-linux-x86_64.ll
grep -v "$victim" "$p2/SHA256SUMS" > "$p2/s" && mv "$p2/s" "$p2/SHA256SUMS"
echo BACKDOOR > "$p2/$victim"

# The baseline first: bare `shasum -c` must accept this attack, or the
# probe below no longer shows what `seed_sums_verify` adds.
if command -v sha256sum >/dev/null 2>&1; then
  ( cd "$p2" && sha256sum -c SHA256SUMS ) > "$work/bare.log" 2>&1; bare=$?
else
  ( cd "$p2" && shasum -a 256 -c SHA256SUMS ) > "$work/bare.log" 2>&1; bare=$?
fi
if (( bare == 0 )); then
  ok "baseline: bare 'shasum -c' accepts the dropped row and the backdoored seed (rc=0)"
else
  fail "baseline: bare 'shasum -c' refused the dropped-row case (rc=$bare) - the"
  echo "     hole this section exists for has closed somewhere else, and the"
  echo "     probe below no longer distinguishes seed_sums_verify from it."
fi

if seed_sums_verify "$p2" > "$work/p2.log" 2>&1; then
  fail "probe: a dropped row plus a backdoored seed passed seed_sums_verify"
else
  ok "probe: a dropped row plus a backdoored seed is refused ($(head -1 "$work/p2.log" | sed 's|.*/||'))"
fi

# A row naming a seed that is gone, and a flipped byte: the two shapes
# `shasum -c` does catch, asserted here so that a rewrite of the
# function cannot lose them while keeping the new check.
p3="$work/probe3"; mkdir -p "$p3"
cp bootstrap/*.ll bootstrap/SHA256SUMS "$p3/"
rm -f "$p3/$victim"
if seed_sums_verify "$p3" > "$work/p3.log" 2>&1; then
  fail "probe: a row naming a seed that is not there passed seed_sums_verify"
else
  ok "probe: a row naming a missing seed is refused"
fi

p4="$work/probe4"; mkdir -p "$p4"
cp bootstrap/*.ll bootstrap/SHA256SUMS "$p4/"
at=$(( $(wc -c < "$p4/$victim") / 2 ))
printf 'X' | dd of="$p4/$victim" bs=1 seek="$at" conv=notrunc 2>/dev/null
if cmp -s "$p4/$victim" "bootstrap/$victim"; then
  fail "probe: the flip at byte $at did not change the copy"
elif seed_sums_verify "$p4" > "$work/p4.log" 2>&1; then
  fail "probe: a seed with one byte flipped at offset $at passed seed_sums_verify"
else
  ok "probe: one byte flipped at offset $at in $victim is refused"
fi

# ---------------------------------------------------------------------
echo
echo "== 3. every 'defended' row of THREATS.md names a gate CI runs =="
# ---------------------------------------------------------------------
threats="bootstrap/THREATS.md"
ci=".github/workflows/ci.yml"
[[ -f "$threats" ]] || { echo "FAIL: $threats is missing"; exit 1; }
[[ -f "$ci" ]] || { echo "FAIL: $ci is missing"; exit 1; }

# threats_rows <THREATS.md>
# Prints one line per table row: "<n>|<defended>|<scripts named>".
threats_rows() {
  # `\|` inside a code span is an escaped pipe, not a cell boundary.
  sed 's/\\|/\x01/g' "$1" \
    | awk -F'|' '/^\| *[0-9]+ *\|/ { n=$2; d=$4; b=$5;
        gsub(/^[ \t]+|[ \t]+$/, "", n);
        gsub(/^[ \t]+|[ \t]+$/, "", d); gsub(/^[ \t]+|[ \t]+$/, "", b);
        gsub(/[ \t]+/, " ", b);
        print n "|" d "|" b }'
}

check_threats() { # <THREATS.md>
  local rows nrows nyes n d by s
  rows="$(threats_rows "$1")"
  nrows="$(printf '%s\n' "$rows" | grep -c '|' || true)"
  nyes="$(printf '%s\n' "$rows" | awk -F'|' '$2 ~ /^yes/' | wc -l | tr -d ' ')"
  # Two floors keep this section from going vacuous: a parse that
  # stopped matching would find no rows, no `yes` rows and no bad ones,
  # and pass. The floors (8 and 3) are low enough that retiring a row
  # does not trip them and high enough that a broken parse cannot pass.
  (( nrows >= 8 )) || { fail "$1 parses to only $nrows rows; the floor is 8 (the table moved or the parse broke)"; return; }
  (( nyes  >= 3 )) || { fail "$1 parses to only $nyes 'yes' rows; the floor is 3"; return; }
  # The document's count of itself, recomputed. Its opening paragraph
  # summarises the table before a reader reaches it, and a prose
  # summary of a table goes stale silently.
  if ! grep -qF "This table has $nrows rows, $nyes defended," "$1"; then
    fail "$1 parses to $nrows rows, $nyes of them defended, and does not say so:"
    fail "  its opening must read \"This table has $nrows rows, $nyes defended,\""
  fi
  while IFS='|' read -r n d by; do
    [[ -n "$n" ]] || continue
    [[ "$d" == yes* ]] || continue
    # Every scripts/check-*.sh named in the cell.
    local named
    named="$(printf '%s\n' "$by" | grep -oE 'scripts/check-[a-z0-9-]+\.sh' | sort -u)"
    if [[ -z "$named" ]]; then
      fail "$1 row $n says 'yes' and names no scripts/check-*.sh - a defence nobody performs"
      continue
    fi
    for s in $named; do
      if [[ ! -f "$s" ]]; then
        fail "$1 row $n names $s, which does not exist"
      elif ! grep -q "$s" "$ci"; then
        fail "$1 row $n names $s, which .github/workflows/ci.yml does not run"
      fi
    done
  done <<< "$rows"
}

check_threats "$threats"
nrows_real="$(threats_rows "$threats" | grep -c '|' || true)"
nyes_real="$(threats_rows "$threats" | awk -F'|' '$2 ~ /^yes/' | wc -l | tr -d ' ')"
ok "$threats: $nrows_real rows, $nyes_real defended, every defence a gate ci.yml runs"

# -- the ablations for section 3 --------------------------------------
#
# A copy with row 2's cell re-pointed at a script that does not exist:
#
#     FAIL: <copy> row 2 names scripts/check-nonexistent.sh, which does not exist
#
# and a copy with the table's rows deleted:
#
#     FAIL: <copy> parses to only 0 rows; the floor is 8 (the table moved
#           or the parse broke)
p5="$work/THREATS.repointed.md"
sed 's|scripts/check-seed-provenance\.sh|scripts/check-nonexistent.sh|' "$threats" > "$p5"
if cmp -s "$p5" "$threats"; then
  fail "probe 3a re-pointed no cell in the copy of $threats"
else
  probe_mode=1; probe_failed=0; probe_first=""
  check_threats "$p5"
  probe_mode=0
  if (( probe_failed )); then ok "probe: a row naming scripts/check-nonexistent.sh is refused ($probe_first)"
  else fail "probe: $threats with a row re-pointed at a nonexistent gate was accepted"; fi
fi

p6="$work/THREATS.gutted.md"
grep -v '^| *[0-9]* *|' "$threats" > "$p6"
probe_mode=1; probe_failed=0; probe_first=""
check_threats "$p6"
probe_mode=0
if (( probe_failed )); then ok "probe: a THREATS.md with no rows trips the floor ($probe_first)"
else fail "probe: a THREATS.md with every row deleted was accepted"; fi

# A gate named in a `yes` row that exists but that CI does not run is
# the third shape: a row true on a maintainer's machine and false on
# every push. `check-ci-coverage.sh` requires every `scripts/check-*.sh`
# to be on a `run:` line, so no real unwired gate exists to point a row
# at, and a non-gate script would trip the "names no scripts/check-*.sh"
# arm instead. So this probe removes a real, wired gate from a copy of
# `ci.yml`, and the unchanged THREATS.md must then be refused for naming
# it. That exercises the `$ci` lookup and nothing else:
#
#     FAIL: bootstrap/THREATS.md row 2 names scripts/check-seed-provenance.sh,
#           which .github/workflows/ci.yml does not run
p7="$work/ci.unwired.yml"
grep -v 'scripts/check-seed-provenance\.sh' "$ci" > "$p7"
if grep -q 'scripts/check-seed-provenance\.sh' "$p7"; then
  fail "probe: could not build a ci.yml without check-seed-provenance.sh"
fi
ci_real="$ci"; ci="$p7"
probe_mode=1; probe_failed=0; probe_first=""
check_threats "$threats"
probe_mode=0
ci="$ci_real"
if (( probe_failed )); then ok "probe: a row naming a gate ci.yml does not run is refused ($probe_first)"
else fail "probe: a row naming an unwired gate was accepted"; fi

# And the document's count of itself: a copy whose opening paragraph
# claims one more defended row than the table carries.
#
#     FAIL: <copy> parses to 12 rows, 7 of them defended, and does not
#           say so
p13="$work/THREATS.miscounted.md"
sed 's/This table has 12 rows, 7 defended,/This table has 12 rows, 8 defended,/' "$threats" > "$p13"
if cmp -s "$p13" "$threats"; then
  fail "probe 3d changed no count in the copy - the sentence this section pins has been reworded"
else
  probe_mode=1; probe_failed=0; probe_first=""
  check_threats "$p13"
  probe_mode=0
  if (( probe_failed )); then ok "probe: a THREATS.md miscounting its own table is refused ($probe_first)"
  else fail "probe: a THREATS.md claiming 8 defended rows over 7 was accepted"; fi
fi

# ---------------------------------------------------------------------
echo
echo "== 4. the lineage gate still reads its own compared path =="
# ---------------------------------------------------------------------
# `check-seed-lineage.sh` asserts, on its own text, that nothing below a
# marker line reaches for an Axiom binary. That is what makes its
# double-compile diverse rather than a compiler checking itself. Delete
# the marker and `sed -n "/marker/,\$p"` matches nothing, the grep finds
# nothing, and the gate passes over an empty search.
lineage="scripts/check-seed-lineage.sh"
marker='# === the compared path begins here ==='

check_lineage_selfread() { # <script>
  local f="$1" mline gline
  mline="$(grep -nxF "$marker" "$f" | head -1 | cut -d: -f1)"
  if [[ -z "$mline" ]]; then
    fail "$f no longer carries its '=== the compared path begins here ===' marker;"
    fail "  without it the self-read below matches nothing and passes over an empty search"
    return
  fi
  gline="$(grep -n 'BASH_SOURCE\[0\]' "$f" | grep 'self_marker' | head -1 | cut -d: -f1)"
  if [[ -z "$gline" ]]; then
    gline="$(grep -n 'sed -n "/\^\${self_marker}' "$f" | head -1 | cut -d: -f1)"
  fi
  if [[ -z "$gline" ]]; then
    fail "$f keeps the marker but no longer reads itself from it - the assertion is gone"
    return
  fi
  if (( gline >= mline )); then
    fail "$f reads itself at line $gline, at or below the marker at $mline: the guard"
    fail "  would be inside the region it is supposed to be checking"
    return
  fi
  # And it must still look for all four names of an Axiom binary. A
  # guard that greps for nothing is the same vacuity one level down.
  local pats
  pats="$(sed -n "${gline}p" "$f")"
  for want in '$axiom' 'axiom-bin' 'AXIOM_AXC' 'gate_build_axc'; do
    case "$pats" in
      *"$want"*) ;;
      *) fail "$f's self-read no longer looks for $want" ;;
    esac
  done
  ok "$f reads itself at line $gline, above the marker at $mline, for all four names"
}

check_lineage_selfread "$lineage"

# -- the ablations for section 4 --------------------------------------
#
#   (4a) a copy with the marker line deleted:
#        "FAIL: <copy> no longer carries its '=== the compared path begins
#         here ===' marker; ..."
#   (4b) a copy with the self-reading grep deleted but the marker kept:
#        "FAIL: <copy> keeps the marker but no longer reads itself from it"
p8="$work/lineage.nomarker.sh"
grep -vxF "$marker" "$lineage" > "$p8"
if cmp -s "$p8" "$lineage"; then
  fail "probe 4a deleted no marker from the copy"
else
  probe_mode=1; probe_failed=0; probe_first=""
  check_lineage_selfread "$p8"
  probe_mode=0
  if (( probe_failed )); then ok "probe: a lineage gate with no marker is refused ($probe_first)"
  else fail "probe: a copy of $lineage with the marker deleted was accepted"; fi
fi

p9="$work/lineage.noselfread.sh"
grep -v 'self_marker' "$lineage" > "$p9"
if cmp -s "$p9" "$lineage"; then
  fail "probe 4b deleted no self-read from the copy"
else
  probe_mode=1; probe_failed=0; probe_first=""
  check_lineage_selfread "$p9"
  probe_mode=0
  if (( probe_failed )); then ok "probe: a lineage gate that keeps the marker but stops reading itself is refused ($probe_first)"
  else fail "probe: a copy of $lineage with the self-read deleted was accepted"; fi
fi

# (4c) The narrowest: the marker and the self-read are there, but it has
# stopped looking for one of the four names. `AXIOM_AXC` is the one
# dropped, because `run-gates.sh` exports it to share a compiler across
# the battery. A guard blind to it would let that shared binary onto
# the compared path.
#
#   FAIL: <copy>'s self-read no longer looks for AXIOM_AXC
p12="$work/lineage.narrowed.sh"
sed 's/|AXIOM_AXC//' "$lineage" > "$p12"
if cmp -s "$p12" "$lineage"; then
  fail "probe 4c narrowed no pattern in the copy"
else
  probe_mode=1; probe_failed=0; probe_first=""
  check_lineage_selfread "$p12"
  probe_mode=0
  if (( probe_failed )); then ok "probe: a self-read that stopped looking for one name is refused ($probe_first)"
  else fail "probe: a copy of $lineage whose guard dropped AXIOM_AXC was accepted"; fi
fi

# ---------------------------------------------------------------------
echo
echo "== 5. the Rust anchor's size is one fact too =="
# ---------------------------------------------------------------------
# `bb730db` is the trust root: row 4 rests on a reviewer being able to
# read it, and "28,082 lines" tells them what that costs. The size is
# stated in `bootstrap/README.md` and in `check-seed-lineage.sh`'s
# header, and every statement must agree.
#
# This is not a `claim()` in `check-doc-drift.sh`, where the other
# recomputed numerals live. That gate runs in the `test` matrix job,
# whose depth-1 checkout has no `bb730db`, so a `claim()` would fail on
# every run or need a skip. Here the sites are always compared with each
# other, which needs no history, and with the commit when it is present.
# When it is absent the gate says so. This gate also runs in the
# `seed-provenance` job, which has `fetch-depth: 0`, so the git arm does
# run in CI.
anchor_numerals() { # <file> - every stated size of the anchor, one per line
  tr '\n' ' ' < "$1" \
    | grep -oE '[0-9][0-9,]*[[:space:]]+lines of Rust' \
    | grep -oE '^[0-9][0-9,]*'
  tr '\n' ' ' < "$1" \
    | grep -oE '430a138`, [0-9][0-9,]* lines' \
    | sed 's/^430a138., *//; s/ lines$//'
}

check_anchor_sites() { # <tag> <file>...
  local tag="$1"; shift
  local f n nstated distinct stated measured nfiles_rs
  : > "$work/anchor.$tag"
  for f in "$@"; do
    while read -r n; do
      [[ -n "$n" ]] && echo "$f $n" >> "$work/anchor.$tag"
    done < <(anchor_numerals "$f")
  done
  nstated="$(wc -l < "$work/anchor.$tag" | tr -d ' ')"
  # The floor. A reworded sentence that stopped matching would leave
  # this section comparing an empty set and passing.
  if (( nstated < 3 )); then
    fail "the anchor's size is stated only $nstated time(s) where this gate looks; the floor is 3"
    fail "  (reword the gate with the sentence, do not narrow the sentence to the gate)"
    return
  fi
  distinct="$(awk '{print $2}' "$work/anchor.$tag" | sort -u | wc -l | tr -d ' ')"
  if (( distinct != 1 )); then
    fail "the anchor's size is stated $nstated times with $distinct different numbers:"
    (( probe_mode )) || sed 's/^/       /' "$work/anchor.$tag"
    return
  fi
  stated="$(awk '{print $2}' "$work/anchor.$tag" | head -1)"
  ok "the anchor's size is stated $nstated times, always as $stated"

  # And against the commit, when the clone has it.
  if git -C "$repo_root" cat-file -e 'bb730db^{commit}' 2>/dev/null; then
      # `git grep -c ''` counts every line of every `.rs` file at that
      # commit, which is `wc -l` over the same set. Compared as
      # integers: `28,082` and `28082` are one claim, and the readable
      # spelling is the one the prose is allowed to use.
      measured="$(git -C "$repo_root" grep -c '' bb730db -- '*.rs' 2>/dev/null \
        | awk -F: '{s += $NF} END {print s + 0}')"
      nfiles_rs="$(git -C "$repo_root" grep -c '' bb730db -- '*.rs' 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${stated//,/}" == "$measured" ]]; then
      ok "and bb730db really carries $measured lines of Rust, over $nfiles_rs files"
    else
      fail "the sites say $stated lines of Rust at bb730db; git counts $measured"
    fi
  else
    (( probe_mode )) || {
      echo "--   bb730db is not in this clone (depth-1 checkout), so the number was"
      echo "     compared across its sites but NOT against the commit. The"
      echo "     seed-provenance job fetches full history and does compare it."
    }
  fi
}

anchor_sites=(bootstrap/README.md scripts/check-seed-lineage.sh)
check_anchor_sites real "${anchor_sites[@]}"

# -- the ablations for section 5 --------------------------------------
#
# A copy of bootstrap/README.md with one of its numerals changed to
# 28,083:
#
#     FAIL: the anchor's size is stated 4 times with 2 different numbers
#
# and a copy with both of its sentences deleted, checked on its own,
# which trips the floor rather than passing over an empty comparison:
#
#     FAIL: the anchor's size is stated only 0 time(s) where this gate
#           looks; the floor is 3
p10="$work/README.wrongsize.md"
sed 's/28,082/28,083/' bootstrap/README.md > "$p10"
if cmp -s "$p10" bootstrap/README.md; then
  fail "probe 5a changed no numeral in the copy of bootstrap/README.md"
else
  probe_mode=1; probe_failed=0; probe_first=""
  check_anchor_sites p5a "$p10" scripts/check-seed-lineage.sh
  probe_mode=0
  if (( probe_failed )); then ok "probe: one site restating the anchor's size differently is refused ($probe_first)"
  else fail "probe: bootstrap/README.md saying 28,083 while the gate says 28,082 was accepted"; fi
fi

p11="$work/README.nosize.md"
grep -v '28,082' bootstrap/README.md > "$p11"
probe_mode=1; probe_failed=0; probe_first=""
check_anchor_sites p5b "$p11"
probe_mode=0
if (( probe_failed )); then ok "probe: the anchor's size stated too few times trips the floor ($probe_first)"
else fail "probe: a document stating the anchor's size nowhere was accepted"; fi

echo
if (( failed )); then
  echo "FAIL: $failed check(s) failed"
  exit 1
fi
echo "PASS: the seed's supply chain is one fact, its integrity check is not vacuous,"
echo "      every defended row names a gate CI runs, the lineage gate still reads"
echo "      its own compared path, and the anchor's size is what git says it is"
