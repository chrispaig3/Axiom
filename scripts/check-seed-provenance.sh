#!/usr/bin/env bash
# The committed seed IS the emission of source in this repository's own
# history, and here is the regeneration that says so.
#
# WHAT THIS ADDS, AND TO WHAT. `bootstrap/SHA256SUMS` is a hash and a
# file committed together, so it moves when they move: it reports a
# DAMAGED seed, and `bootstrap/README.md` has always said so in its own
# words - "a corruption check, not a trust check". `check-bootstrap.sh`
# adds the other half a clone needs, that the seed can BUILD this
# source, by building it. Neither asks the question this one asks:
#
#     is the seed the output of source anyone can read?
#
# Until 2026-08-25 nothing in the repository related the 5 MB of
# generated text under `bootstrap/` to any source at all, in either
# direction. A seed defining a function that has never existed in this
# repository passed every gate green, and the one file that claimed a
# provenance fact - `bootstrap/STAMP` - was wrong, because nothing read
# it. See STAMP for what it said and what it should have said.
#
# WHAT IT PROVES, AND WHAT IT CANNOT. It proves the seed is a build
# product of reviewable source, reproducibly, on six targets: a
# tampered seed now has to be a tamper somebody can find by reading
# `.ax` files rather than 139,638 lines of LLVM IR. It does NOT answer
# Ken Thompson - the compiler that regenerates the seed here is itself
# seed-descended, so a compiler that reproduces a backdoor in its own
# output reproduces it here too. Nothing a single implementation can
# check answers that. `check-seed-lineage.sh` is the answer that exists:
# it replays every seed from the one before it, back to the Rust
# compiler at `bb730db`, which no Axiom seed ever touched.
#
# WHY THE COMMIT IS FOUND RATHER THAN READ. The seed's provenance
# commit cannot be recorded by `reseed.sh`, because it does not exist
# yet when `reseed.sh` runs - the seed is generated from a dirty tree
# and lands in the NEXT commit. That is exactly how the old
# `Generated from commit:` line came to be wrong. So the commit is
# derived from git, and STAMP's `Source stamp:` is the falsifiable
# half: the commit's sources must hash to it before anything is
# regenerated.
#
# THE SEED IS THE SIX `.ll` FILES, NOT THE DIRECTORY. The first
# version of this asked for the last commit to touch `bootstrap/`, and
# it went red on the very commit that added this gate - because that
# commit rewrote `bootstrap/STAMP` and `bootstrap/README.md`, which are
# metadata ABOUT the seed and not the seed. A later commit that only
# corrects a sentence in the README must not be read as a reseed. The
# check caught its own author, which is the property this file is for.
#
# COST. One compiler build plus six whole-compiler emissions - four
# took about five minutes, so budget seven. It is its own CI job for
# that reason, and it needs the full history - `fetch-depth: 0` -
# because a shallow clone cannot see the commit that introduced a file
# it did not fetch.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

failed=0
fail() { echo "FAIL: $*"; failed=$((failed + 1)); }

command -v git >/dev/null || { echo "FAIL: git is not on PATH"; exit 1; }

targets="darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64 freebsd-x86_64 freebsd-aarch64"

# --------------------------------------------------------------------
echo "== STAMP states a source stamp, and it is well formed =="
# --------------------------------------------------------------------
stamp_file="bootstrap/STAMP"
[[ -f "$stamp_file" ]] || { echo "FAIL: $stamp_file is missing"; exit 1; }
want_stamp="$(sed -n 's/^Source stamp: *//p' "$stamp_file" | tr -d '[:space:]')"
want_files="$(sed -n 's/^Source files: *//p' "$stamp_file" | tr -d '[:space:]')"
if [[ ! "$want_stamp" =~ ^[0-9a-f]{64}$ ]]; then
  echo "FAIL: $stamp_file has no 64-hex 'Source stamp:' line"
  echo "      It read: '${want_stamp:-<nothing>}'"
  exit 1
fi
if [[ ! "$want_files" =~ ^[0-9]+$ ]] || (( want_files == 0 )); then
  echo "FAIL: $stamp_file has no positive 'Source files:' count"
  exit 1
fi
echo "ok   STAMP claims ${want_stamp:0:12}… over $want_files source files"

# The old spelling must not come back. It is not merely superseded: it
# named a commit the seed does not correspond to, and a reader who
# trusts it is misled in the one file whose subject is provenance.
if grep -q '^Generated from commit:' "$stamp_file"; then
  fail "$stamp_file has gone back to recording a commit; see its own note"
else
  echo "ok   it records no 'Generated from commit:' line"
fi

# --------------------------------------------------------------------
echo
echo "== the commit that carries this seed =="
# --------------------------------------------------------------------
commit="$(git -C "$repo_root" log -1 --format=%H -- 'bootstrap/*.ll' 2>/dev/null || true)"
if [[ -z "$commit" ]]; then
  echo "FAIL: no commit in history touches bootstrap/*.ll."
  echo "      A shallow clone cannot answer this - the job needs fetch-depth: 0."
  exit 1
fi
echo "ok   the six seeds were last written by ${commit:0:7}"

extract() {
  local sha="$1" dest="$2"
  rm -rf "$dest"; mkdir -p "$dest"
  ( cd "$repo_root" && git archive "$sha" self_host stdlib ) | tar -x -C "$dest"
}

tree="$work/tree"
extract "$commit" "$tree"
got_stamp="$(gate_seed_source_stamp "$tree")"
got_files="$(cd "$tree" && find self_host stdlib -name '*.ax' -type f | wc -l | tr -d ' ')"
if [[ "$got_stamp" == "$want_stamp" ]] && [[ "$got_files" == "$want_files" ]]; then
  echo "ok   its sources hash to what STAMP says ($got_files files)"
else
  fail "STAMP does not describe ${commit:0:7}'s sources"
  echo "     STAMP: $want_stamp over $want_files files"
  echo "     ${commit:0:7}: $got_stamp over $got_files files"
  echo "     Either the seed was committed without its STAMP, or STAMP was"
  echo "     edited by hand. Re-run scripts/reseed.sh and commit both."
fi

# --------------------------------------------------------------------
echo
echo "== regenerating all six seeds from those sources =="
# --------------------------------------------------------------------
# `reseed.sh`'s own procedure, reproduced here rather than invoked,
# because that script writes into `bootstrap/` and this one must not
# touch the tree: it builds a compiler from the named sources and emits
# `self_host/main.ax` once per target.
#
# `AXIOM_STDLIB` IS SET FOR BOTH STEPS, and the second one is the one
# that matters. `gate_init` exports this checkout's `stdlib/`, so an
# emit that inherited it would compile a self_host from the seed's
# commit against TODAY's standard library - which is not the source
# STAMP names, and which is a moving target by construction. It also
# does not merely produce a different answer: measured while writing
# this, it FAILED to compile, because `vecGet`'s return type changed
# after that commit. A gate whose regeneration silently used the wrong
# sources would compare the wrong two things.
regenerate() {
  local src="$1" out="$2" log="$3"
  rm -rf "$out"; mkdir -p "$out"
  if ! AXIOM_STDLIB="$src/stdlib" "$axiom" build \
         --input "$src/self_host/main.ax" --output "$out/gen" >"$log" 2>&1; then
    return 1
  fi
  # The emit runs from a directory holding `in.ax` beside links to the
  # two module trees, which is the shape `reseed.sh` emits in - and the
  # input's NAME reaches the output, so it has to be `in.ax` here too.
  ln -s "$src/stdlib"    "$out/stdlib"
  ln -s "$src/self_host" "$out/self_host"
  cp "$src/self_host/main.ax" "$out/in.ax"
  local t
  for t in $targets; do
    if ! ( cd "$out" && AXIOM_STDLIB="$src/stdlib" ./gen in.ax "$t" \
             >"$out/axiom-$t.ll" 2>"$out/$t.err" ); then
      echo "     the $t emit failed:" >&2
      head -5 "$out/$t.err" | sed 's/^/       /' >&2
      return 1
    fi
    # `reseed.sh`'s own two sanity checks, for the same reason it has
    # them: a TRUNCATED emit is not a mismatch, it is a broken run, and
    # comparing it would report "differs" where the honest answer is
    # "nothing was produced". The negative probe below would otherwise
    # pass on an empty file.
    grep -q '^target triple' "$out/axiom-$t.ll" || {
      echo "     the $t emit has no target triple - it is not an LLVM module" >&2
      return 1
    }
    (( $(wc -l <"$out/axiom-$t.ll") > 10000 )) || {
      echo "     the $t emit is only $(wc -l <"$out/axiom-$t.ll") lines - truncated" >&2
      return 1
    }
  done
  return 0
}

gen="$work/gen"
if ! regenerate "$tree" "$gen" "$work/build.log"; then
  fail "could not regenerate the seed from ${commit:0:7}"
  tail -20 "$work/build.log" | sed 's/^/     /'
else
  same=0
  for t in $targets; do
    if cmp -s "$gen/axiom-$t.ll" "$repo_root/bootstrap/axiom-$t.ll"; then
      echo "ok   axiom-$t.ll is byte-identical to the regeneration"
      same=$((same + 1))
    else
      fail "axiom-$t.ll differs from the regeneration"
      echo "     committed:    $(wc -c <"$repo_root/bootstrap/axiom-$t.ll" | tr -d ' ') bytes"
      echo "     regenerated:  $(wc -c <"$gen/axiom-$t.ll" | tr -d ' ') bytes"
      echo "     differing lines: $(diff "$gen/axiom-$t.ll" "$repo_root/bootstrap/axiom-$t.ll" | grep -c '^[<>]' || true)"
      diff "$gen/axiom-$t.ll" "$repo_root/bootstrap/axiom-$t.ll" | head -8 | sed 's/^/       /'
    fi
  done
  (( same == 6 )) && echo "     all six targets, $(wc -l <"$repo_root/bootstrap/axiom-darwin-aarch64.ll" | tr -d ' ') lines each"
fi

# --------------------------------------------------------------------
echo
echo "== negative probe: a one-byte source change must move the seed =="
# --------------------------------------------------------------------
# The regeneration above is worth nothing if it would agree with
# anything. This perturbs ONE source file in a copy of the tree and
# requires the emission to stop matching. It is deliberately a change
# to a function body rather than to a comment: a comment does not reach
# the IR, so a probe built on one would pass while proving nothing.
#
# Only ONE target is regenerated here. The property under test is "the
# comparison can fail", which one target establishes, and the other
# three would cost four minutes to restate it.
probe="$work/probe"
cp -R "$tree" "$probe"
victim="$probe/stdlib/Path.ax"
[[ -f "$victim" ]] || { echo "FAIL: the probe's victim file is missing"; exit 1; }
# `pathIsAbsolute` asks whether byte 0 is `/` (47). Ask about `\` (92)
# instead: one literal, one instruction, and it cannot be optimised
# away because the function is exported.
if ! grep -q '(== (strByte p 0) 47)' "$victim"; then
  echo "FAIL: the probe's anchor is gone from stdlib/Path.ax - re-derive it"
  exit 1
fi
sed -i.bak 's/(== (strByte p 0) 47)/(== (strByte p 0) 92)/' "$victim"
rm -f "$victim.bak"
probe_out="$work/probe-out"
if ! AXIOM_STDLIB="$probe/stdlib" "$axiom" build \
       --input "$probe/self_host/main.ax" --output "$work/probe-gen" >"$work/probe.log" 2>&1; then
  fail "the probe tree does not build - the probe is measuring itself"
  tail -10 "$work/probe.log" | sed 's/^/     /'
else
  mkdir -p "$probe_out"
  ln -s "$probe/stdlib"    "$probe_out/stdlib"
  ln -s "$probe/self_host" "$probe_out/self_host"
  cp "$probe/self_host/main.ax" "$probe_out/in.ax"
  cp "$work/probe-gen" "$probe_out/gen"
  ( cd "$probe_out" && AXIOM_STDLIB="$probe/stdlib" ./gen in.ax darwin-aarch64 \
      >"$probe_out/out.ll" 2>"$probe_out/err" ) || true
  # The probe must be a DIFFERENT emission, not an absent one. Without
  # this the probe passed on a zero-line file - which it did, measured,
  # while the emit above was reaching for the wrong standard library.
  if ! grep -q '^target triple' "$probe_out/out.ll" \
     || (( $(wc -l <"$probe_out/out.ll") < 10000 )); then
    fail "the probe emitted nothing to compare - it would pass on an empty file"
    head -5 "$probe_out/err" | sed 's/^/     /'
  elif cmp -s "$probe_out/out.ll" "$repo_root/bootstrap/axiom-darwin-aarch64.ll"; then
    fail "one byte of stdlib/Path.ax changed and the seed did not move"
    echo "     The comparison above cannot distinguish this source from any other."
  else
    echo "ok   a one-byte source change moves the emission ($(diff "$probe_out/out.ll" "$repo_root/bootstrap/axiom-darwin-aarch64.ll" | grep -c '^[<>]' || true) lines)"
  fi
  # And the stamp moves with it, which is what makes STAMP falsifiable.
  if [[ "$(gate_seed_source_stamp "$probe")" == "$want_stamp" ]]; then
    fail "the source stamp did not move when a source byte did"
  else
    echo "ok   the source stamp moves with it"
  fi
fi

# --------------------------------------------------------------------
echo
echo "== negative probe: the wrong commit must be reported wrong =="
# --------------------------------------------------------------------
# The commit is DERIVED here, so the failure this guards against is the
# derivation silently landing on a tree that happens to hash right.
# `${commit}^` is the tree the old STAMP named - the commit before the
# seed - which is the exact mistake that was live until 2026-08-25.
#
# THE TREE COMPARED AGAINST IS THE ONE BEFORE THE SOURCES LAST MOVED.
# `moved` is the commit that last touched a `.ax` file at or before the
# seed commit; when a reseed rides in the commit that changed
# `self_host/` - every reseed until 2026-08-29 - that IS the seed
# commit and `${moved}^` is its parent, the old STAMP's mistake
# exactly. It is further back when a commit carries the seed alone.
# That happened the day the FreeBSD targets arrived: their names had to
# land one commit BEFORE their seeds, because only a compiler that
# knows a target can emit its seed, so the seed commit's parent was the
# same source tree and the stamp agreed with it, as it must -
# regenerating from either gives the same bytes. Comparing against the
# parent read that agreement as "the stamp cannot tell them apart" and
# went red on a seed that was exactly its source's emission. What this
# asserts is that STAMP distinguishes TREES, and two commits with one
# tree are one tree; so a seed-only commit's parent is REQUIRED to hash
# the same, and the tree before the sources last moved is required not
# to.
parent="$(git -C "$repo_root" rev-parse --verify "${commit}^" 2>/dev/null || true)"
moved="$(git -C "$repo_root" log -1 --format=%H "$commit" -- 'self_host/*.ax' 'stdlib/*.ax' 2>/dev/null || true)"
before="$(git -C "$repo_root" rev-parse --verify "${moved}^" 2>/dev/null || true)"
if [[ -z "$parent" || -z "$moved" || -z "$before" ]]; then
  echo "warn: ${commit:0:7} has no ancestor before its sources last moved - the wrong-commit probe cannot run here"
else
  if [[ "$moved" != "$commit" ]]; then
    extract "$parent" "$work/parent"
    if [[ "$(gate_seed_source_stamp "$work/parent")" == "$want_stamp" ]]; then
      echo "ok   ${commit:0:7} carries the seed alone; its parent ${parent:0:7} is the same source tree and hashes the same, as one tree must"
    else
      fail "${parent:0:7} touches no source file after ${moved:0:7} yet hashes differently from ${commit:0:7} - the stamp is reading something other than the sources"
    fi
  fi
  extract "$before" "$work/before"
  if [[ "$(gate_seed_source_stamp "$work/before")" == "$want_stamp" ]]; then
    fail "${before:0:7}'s sources hash the same as ${commit:0:7}'s - the stamp cannot tell them apart"
  else
    echo "ok   ${before:0:7}, the tree before the sources last moved (${moved:0:7}), hashes differently, so STAMP identifies one tree"
  fi
fi

echo
if (( failed > 0 )); then
  echo "check-seed-provenance: $failed check(s) failed"
  exit 1
fi
echo "check-seed-provenance: the seed is ${commit:0:7}'s emission, on all six targets,"
echo "                       and a one-byte source change is enough to say so"
