#!/usr/bin/env bash
# Assert that the `.axir` record file survives a trip through its own
# reader unchanged, that its reader REFUSES what its grammar does not
# spell, and - the part that makes the first claim mean anything - that
# the reader is not a passthrough.
#
# WHY A ROUND TRIP AND NOT A GOLDEN. A golden here would churn on every
# change to what the checker records and would be exactly as strong as
# whoever last blessed it. `check-tools-selfhost.sh`'s own header
# records what that costs: both AXSYM goldens were re-blessed clean
# against a compiler emitting a start column shifted by one, and the
# only thing that caught it was `verify-axsym.py`, which re-derives
# every claim from the source instead of comparing to a blessing.
# `emit | read | emit == emit` is a property a re-bless cannot satisfy.
#
# WHY THE THIRD CLAIM EXISTS. `emit | read | emit == emit` is satisfied
# perfectly by a reader that keeps the raw lines and hands them back -
# the vacuous check this repository names as its most common defect,
# and it would be an easy accident here, because a line-oriented format
# invites `readlines` as an implementation. So a NON-NORMAL file goes
# in too: same facts, doubled spaces, a nid written with the sigil the
# writer would emit and nothing else changed. A decomposing reader
# normalises it and the output DIFFERS from the input; a passthrough
# hands it straight back. The gate demands the difference, and then
# demands that the normalised form is a fixed point.
#
# WHAT IS IN THE CORPUS. A probe importing every stdlib module, and the
# compiler's own `self_host/` entry, which is the largest module this
# repository has - each emitted TWICE, once as `--axir` and once as
# `--axir --mir`, because those are two different files and only the
# second carries a body. The hand-written `.axir` fixtures are beside
# them, and since 2026-09-04 they are a supplement rather than the
# whole evidence for `blk`, `op` and `term`: `symbols --axir --mir` now
# writes those lines for every function `self_host/mir.ax`'s `mLowerFn`
# lowers and `mirVerify` passes. Measured on this tree the same day:
# 389 of the probe's 839 records carry a body and 1,457 of
# `self_host/main.ax`'s 4,097 do.
#
# WHAT THE FIXTURES STILL COVER, therefore, is what the compiler does
# NOT write - `tests/axir/body.axir` names blocks `entry` and `loop`
# and uses opcodes this IR does not have, because the grammar is a
# format rather than a spelling of one lowering, and a reader that
# accepted only today's output would refuse tomorrow's.
#
# ABLATIONS (each must turn this gate red):
#   1. make `axirWrite` drop the `@nid` from the header - the corpus
#      round trip stops matching, because the reader decomposed a nid
#      the writer then did not put back.
#   2. make `axirRead` keep raw lines instead of decomposing them - the
#      non-normal file comes back byte-identical and the "it changed"
#      assertion fires.
#   3. delete an arm from `axirKindArityMin` so an unknown kind is
#      accepted - a `.bad` fixture stops being refused.
# Four more landed with the body lines on 2026-09-04, each run in a
# shadow tree with the compiler rebuilt from it, and each recorded with
# what it did to the sections it did NOT fire - because "this ablation
# reddens the gate" says less than "this ablation reddens THIS section
# and leaves the others green":
#   4. drop the `(== mir 1)` guard around `axirLowered` in
#      `axirRender`. The DEFAULT stream grows body lines and §"only
#      under --mir" fires on the probe's very first record. The corpus
#      round trip above stayed GREEN through it - which is the whole
#      reason that section exists.
#   5. make `axirLowered` answer 0 for every declaration. Both corpora
#      then report "839 records, 0 of them with a lowered body,
#      identical after read-back" and the round trip is PERFECT; only
#      the body floor fires. An emitter that stopped emitting is
#      invisible to `emit | read | emit == emit`, and this is the
#      measurement that says so.
#   6. stop `axirWrite` putting the `%` back on a `blk` parameter. The
#      `--mir` round trip breaks on the first join block - `blk bb3 %5`
#      comes back as `blk bb3 5` - because the reader stripped a sigil
#      the writer then did not restore.
#   7. remove the `blk` arm from `axirDecompose` AND the `%` from
#      `axirWrite`, so `blk` is raw on both sides. Every section above
#      goes green again, including the passthrough probe, and the ONLY
#      thing that fires is `blk-param-without-sigil.bad` no longer
#      being refused. That fixture is the sole evidence for the reader
#      arm once both halves are removed together, which is why it is
#      in the corpus.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

# `--axir` is a flag, and the driver's flag table is CLOSED: an unknown
# flag exits 2 before printing anything. Without this probe the whole
# gate would die on its first invocation under `set -e` and report
# nothing - a gate whose failure mode is silence cannot be told from a
# gate that did not run. (check-agent-calls.sh's precedent, and it was
# written after exactly that happened.)
printf '(:: main Int)\n\n(fn (main) 0)\n' > "$work/flagprobe.ax"
set +e
"$axc" symbols --axir "$work/flagprobe.ax" >/dev/null 2>&1
flagrc=$?
set -e
if (( flagrc == 2 )); then
  echo "FAIL: the compiler under test rejects \`symbols --axir\` (exit 2, the"
  echo "      driver's closed flag table). That flag is the whole input to this"
  echo "      gate; a compiler built from before it landed cannot satisfy"
  echo "      anything below."
  exit 1
fi
if (( flagrc != 0 )); then
  echo "FAIL: \`symbols --axir\` exited $flagrc on a three-line program that"
  echo "      declares nothing but \`main\`."
  exit 1
fi

echo "== the emitted corpus round-trips byte for byte =="
# The probe imports every stdlib module, so the corpus is derived from
# the tree and a module is covered the day it lands - check-agent-calls'
# construction, for its reason.
: > "$work/modules"
for f in stdlib/*.ax stdlib/*/*.ax; do
  [[ -e "$f" ]] || continue
  rel="${f#stdlib/}"; dir="$(dirname "$rel")"
  base="$(basename "$rel" .ax)"; base="${base%%.*}"
  if [[ "$dir" == "." ]]; then printf '%s\n' "$base" >> "$work/modules"
  else printf '%s.%s\n' "${dir//\//.}" "$base" >> "$work/modules"; fi
done
LC_ALL=C sort -u -o "$work/modules" "$work/modules"
modcount=$(wc -l < "$work/modules" | tr -d ' ')
if (( modcount < 15 )); then
  echo "FAIL: derived only $modcount stdlib modules from the tree; there were 19 on"
  echo "      2026-09-03 (a derivation that finds nothing imports nothing, and a"
  echo "      corpus of nothing round-trips perfectly)"
  exit 1
fi
{
  while read -r m; do printf '(import %s)\n\n' "$m"; done < "$work/modules"
  printf '(:: main Int)\n\n(fn (main) 0)\n'
} > "$work/probe.ax"

records=0
bodies=0
# Both streams, because they are two different files: `--mir` adds the
# `region` line and the whole body, and a round trip that only ever saw
# the shorter one would say nothing about the half this gate's name is
# about. `--mir` forces the region-facts fixpoint and is the slow one -
# measured 2026-09-04 on this tree, `--axir --mir self_host/main.ax` is
# 31.7s against 7.2s without it, and almost all of that is the fixpoint
# rather than the lowering: the AXSYM `symbols --mir` on the same file,
# which lowers nothing, is 37.6s.
for src in "$work/probe.ax" self_host/main.ax; do
  name="$(basename "$src" .ax)"
  ( cd "$(dirname "$src")" && AXIOM_STDLIB="$repo_root/stdlib" \
      "$axc" symbols --axir "$(basename "$src")" ) > "$work/$name.a.axir"
  "$axc" symbols --axir "$work/$name.a.axir" > "$work/$name.b.axir"
  if ! cmp -s "$work/$name.a.axir" "$work/$name.b.axir"; then
    echo "FAIL: $src does not round-trip; first difference:"
    diff "$work/$name.a.axir" "$work/$name.b.axir" | head -10 | sed 's/^/     /'
    exit 1
  fi
  ( cd "$(dirname "$src")" && AXIOM_STDLIB="$repo_root/stdlib" \
      "$axc" symbols --axir --mir "$(basename "$src")" ) > "$work/$name.m.axir"
  "$axc" symbols --axir "$work/$name.m.axir" > "$work/$name.m2.axir"
  if ! cmp -s "$work/$name.m.axir" "$work/$name.m2.axir"; then
    echo "FAIL: $src does not round-trip under --mir; first difference:"
    diff "$work/$name.m.axir" "$work/$name.m2.axir" | head -10 | sed 's/^/     /'
    exit 1
  fi
  n=$(grep -c '^F ' "$work/$name.a.axir" || true)
  b=$(grep -c '^blk bb0$' "$work/$name.m.axir" || true)
  records=$(( records + n ))
  bodies=$(( bodies + b ))
  echo "ok   $src: $n records, $b of them with a lowered body, identical after read-back"
done
# A floor, because an emitter that answered the magic line alone would
# round-trip flawlessly.
if (( records < 400 )); then
  echo "FAIL: only $records records over the whole corpus; the floor is 400"
  echo "      (4,862 on 2026-09-03). An empty file round-trips perfectly."
  exit 1
fi

echo
echo "== the body lines are written under --mir and nowhere else =="
# THREE CLAIMS, and the third is the one a round trip cannot make.
#
# 1. the default stream carries no body at all. `--axir` is the stream
#    every tool that does not want to pay for the region fixpoint
#    reads, and a body appearing there unasked would move a file
#    nobody asked to move.
# 2. `--mir` is ADDITIVE ON THE BYTE LEVEL: delete every `blk`, `op`
#    and `term` line from it and what is left is the default stream,
#    modulo the `region` line `--mir` was already adding. That is
#    check-mir-projection.sh's silence property, spelled for this
#    stream.
# 3. a FLOOR and an OPCODE CENSUS. `emit | read | emit == emit` is
#    satisfied perfectly by an emitter that writes no bodies, so the
#    round trip above cannot tell a lowering that works from one that
#    refuses everything. The census is derived from `mir.ax`'s own
#    operator table and `axir.ax`'s own terminator writer rather than
#    listed here, so an opcode added to either must be reached by the
#    corpus or say why not.
for name in probe main; do
  if grep -qE '^(blk|op|term) ' "$work/$name.a.axir"; then
    echo "FAIL: the default \`--axir\` stream for $name carries body lines. They cost"
    echo "      a lowering of every function in the program, and --mir is the flag"
    echo "      documented as the slow one:"
    grep -nE '^(blk|op|term) ' "$work/$name.a.axir" | head -3 | sed 's/^/     /'
    exit 1
  fi
  grep -vE '^(blk|op|term) ' "$work/$name.m.axir" > "$work/$name.stripped"
  # `--mir` adds the region line too, and did before this landed; the
  # claim here is only about the body, so the region lines come out of
  # both sides.
  grep -v '^region ' "$work/$name.stripped" > "$work/$name.stripped.noregion"
  grep -v '^region ' "$work/$name.a.axir" > "$work/$name.a.noregion"
  if ! cmp -s "$work/$name.a.noregion" "$work/$name.stripped.noregion"; then
    echo "FAIL: the --mir stream for $name with its body lines deleted is not the"
    echo "      default stream. --mir moved something other than what it added:"
    diff "$work/$name.a.noregion" "$work/$name.stripped.noregion" | head -10 | sed 's/^/     /'
    exit 1
  fi
done
if (( bodies < 800 )); then
  echo "FAIL: only $bodies records over the whole corpus carry a lowered body; the"
  echo "      floor is 800 (389 + 1,457 = 1,846 on 2026-09-04). Every check above"
  echo "      is satisfied by an emitter that writes no body at all - the round"
  echo "      trip most of all."
  exit 1
fi
# The opcode census, derived rather than listed. `mBinOp` answers the
# MIR spelling of an Axiom binary operator on its own line; `axirOpLine`
# spells the two non-operator opcodes and `axirTermLine` the five
# terminators. If a spelling is added to any of them, the corpus has to
# reach it.
opwords="$(sed -n '/^(pub fn (mBinOp nm)/,/^)$/p' self_host/mir.ax \
  | grep -oE '^ *"[a-z]+"$' | tr -d ' "' | LC_ALL=C sort -u)"
opwords="$opwords
$(grep -oE '" (const|call) "' self_host/axir.ax | tr -d ' "' | LC_ALL=C sort -u)"
termwords="$(grep -oE '"term [a-z]+ ' self_host/axir.ax | awk '{print $2}' | LC_ALL=C sort -u)"
nop=$(printf '%s\n' "$opwords" | grep -c . || true)
nterm=$(printf '%s\n' "$termwords" | grep -c . || true)
if (( nop < 13 || nterm < 5 )); then
  echo "FAIL: derived only $nop opcode spellings and $nterm terminator spellings from"
  echo "      the sources; there were 13 and 5 on 2026-09-04. A census derived from"
  echo "      nothing is passed by a corpus of nothing."
  exit 1
fi
cat "$work/probe.m.axir" "$work/main.m.axir" > "$work/all.m.axir"
missing=""
while read -r wd; do
  [[ -n "$wd" ]] || continue
  grep -qE "^op %[0-9]+ $wd( |\$)" "$work/all.m.axir" || missing="$missing op:$wd"
done <<< "$opwords"
while read -r wd; do
  [[ -n "$wd" ]] || continue
  grep -qE "^term $wd( |\$)" "$work/all.m.axir" || missing="$missing term:$wd"
done <<< "$termwords"
if [[ -n "$missing" ]]; then
  echo "FAIL: the emitted corpus never writes:$missing"
  echo "      Every spelling the writer can produce is a line kind the reader has"
  echo "      to accept, and one nothing emits is one nobody has read back. Either"
  echo "      the lowering narrowed itself, or a new opcode needs a corpus that"
  echo "      reaches it."
  exit 1
fi
withparams=$(grep -cE '^blk bb[0-9]+ %' "$work/all.m.axir" || true)
if (( withparams < 50 )); then
  echo "FAIL: only $withparams blocks in the whole corpus take a parameter; the floor"
  echo "      is 50 (1,236 on 2026-09-04). This IR has block parameters instead of"
  echo "      phi nodes, so a corpus with none never exercises the widened \`blk\`"
  echo "      line, its reader arm, or the sigil the writer puts back."
  exit 1
fi
echo "ok   $bodies bodies, $nop opcodes and $nterm terminators all reached, $withparams blocks with parameters"

echo
echo "== the hand-written fixtures round-trip too =="
# `body.axir` carries block labels and opcodes this IR does not have,
# which is the point: the grammar is a format, not a spelling of one
# lowering. `lowered.axir` is the emitted shape verbatim.
fixtures=0
for f in tests/axir/*.axir; do
  [[ -e "$f" ]] || continue
  "$axc" symbols --axir "$f" > "$work/fix.out"
  if ! cmp -s "$f" "$work/fix.out"; then
    echo "FAIL: $f does not round-trip:"
    diff "$f" "$work/fix.out" | head -10 | sed 's/^/     /'
    exit 1
  fi
  fixtures=$(( fixtures + 1 ))
done
if (( fixtures < 1 )); then
  echo "FAIL: no .axir fixtures under tests/axir/. The body grammar - blk, op,"
  echo "      term - is READ and not WRITTEN, so a fixture is the only thing"
  echo "      that exercises those arms at all."
  exit 1
fi
# A separate name from `$bodies` above, which counts the EMITTED
# corpus. One variable for both was one variable: the summary line at
# the bottom reported "4936 records (2 with a lowered body)", the
# fixture count, having lost the 1,846 the corpus had.
fixbodies=$(grep -l '^blk ' tests/axir/*.axir 2>/dev/null | wc -l | tr -d ' ')
if (( fixbodies < 1 )); then
  echo "FAIL: $fixtures fixtures and not one carries a \`blk\` line, so the"
  echo "      reserved half of the grammar is untested."
  exit 1
fi
echo "ok   $fixtures fixtures round-trip, $fixbodies of them carrying block bodies"

echo
echo "== the reader is not a passthrough =="
# Same facts as a well-formed record, spelled non-normally: doubled
# spaces between fields. A reader that decomposes normalises this; a
# reader that keeps raw lines hands it straight back.
cat > "$work/nonnormal.axir" <<'NN'
axir 1  darwin-aarch64   0.0.0
F  alpha   src/a.ax:1:5-10  "(Int -> Int)"   @00000000000000ff
sig   1
param  0   n
end
NN
"$axc" symbols --axir "$work/nonnormal.axir" > "$work/nonnormal.1"
if cmp -s "$work/nonnormal.axir" "$work/nonnormal.1"; then
  echo "FAIL: a file with doubled spaces came back byte-identical. The reader is"
  echo "      handing lines back rather than decomposing them, which makes the"
  echo "      round-trip check above vacuous - it would pass against a reader"
  echo "      that read nothing at all."
  exit 1
fi
"$axc" symbols --axir "$work/nonnormal.1" > "$work/nonnormal.2"
if ! cmp -s "$work/nonnormal.1" "$work/nonnormal.2"; then
  echo "FAIL: normalising is not idempotent - the reader answers a third form"
  echo "      for its own output:"
  diff "$work/nonnormal.1" "$work/nonnormal.2" | head -10 | sed 's/^/     /'
  exit 1
fi
# And what it normalised to has to be the facts, not a shorter file.
if [[ "$(wc -l < "$work/nonnormal.1" | tr -d ' ')" != "5" ]]; then
  echo "FAIL: the normalised form has $(wc -l < "$work/nonnormal.1" | tr -d ' ') lines, not 5."
  echo "      The reader dropped something rather than reformatting it."
  cat "$work/nonnormal.1" | sed 's/^/     /'
  exit 1
fi
if ! grep -q '^F alpha src/a.ax:1:5-10 "(Int -> Int)" @00000000000000ff$' "$work/nonnormal.1"; then
  echo "FAIL: the normalised header is not the tuple that went in:"
  grep '^F ' "$work/nonnormal.1" | sed 's/^/     /'
  exit 1
fi
echo "ok   a non-normal file is normalised, and the normal form is a fixed point"

echo
echo "== the grammar is closed: every malformed fixture is refused =="
bad=0
for f in tests/axir/*.bad; do
  [[ -e "$f" ]] || continue
  set +e
  out="$("$axc" symbols --axir "$f" 2>&1 >/dev/null)"
  rc=$?
  set -e
  if (( rc == 0 )); then
    echo "FAIL: $f was ACCEPTED. The reader took a line its grammar does not"
    echo "      spell, which means a malformed file round-trips as a different"
    echo "      one instead of being refused."
    exit 1
  fi
  if [[ -z "$out" ]]; then
    echo "FAIL: $f was refused with exit $rc and NOTHING on stderr. A refusal"
    echo "      that does not say what is wrong is a refusal nobody can act on."
    exit 1
  fi
  bad=$(( bad + 1 ))
done
if (( bad < 5 )); then
  echo "FAIL: only $bad malformed fixtures under tests/axir/*.bad; there were 7 on"
  echo "      2026-09-04, up from 5 when \`blk\` grew a block-parameter list and"
  echo "      with it two new ways to be wrong. This assertion is as strong as the"
  echo "      corpus behind it."
  exit 1
fi
echo "ok   $bad malformed fixtures refused, each with a message"

echo
echo "== the magic line is what selects the reader =="
# Not the extension. `.axir` under a `.ax` name must still read back,
# and a source file must still compile whatever it is called - that is
# the whole reason the first line says `axir 1`.
cp "$work/nonnormal.1" "$work/disguised.ax"
"$axc" symbols --axir "$work/disguised.ax" > "$work/disguised.out"
if ! cmp -s "$work/nonnormal.1" "$work/disguised.out"; then
  echo "FAIL: a record file named \`.ax\` was not read back. The reader is"
  echo "      selecting on the extension rather than on the magic line, which is"
  echo "      the guess the magic line exists to remove - LLVM's Machine IR is"
  echo "      also an IR in a text file, and this toolchain writes it."
  exit 1
fi
cp "$work/flagprobe.ax" "$work/disguised.axir"
"$axc" symbols --axir "$work/disguised.axir" > "$work/src.out"
if ! grep -q '^F main ' "$work/src.out"; then
  echo "FAIL: a SOURCE file named \`.axir\` was not compiled - the reader claimed"
  echo "      it on its name. Output was:"
  head -5 "$work/src.out" | sed 's/^/     /'
  exit 1
fi
echo "ok   the first line decides, not the file name, in both directions"

echo
echo "ok   check-mir-roundtrip: $records records ($bodies with a lowered body) and"
echo "     $fixtures fixtures round-trip; $bad malformed files refused"
