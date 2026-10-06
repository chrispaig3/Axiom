#!/usr/bin/env bash
# Check that the `.axir` record file survives a trip through its own
# reader unchanged, that the reader refuses what its grammar does not
# spell, and that the reader is not a passthrough.
#
# A round trip, not a golden: a golden churns with every change to what
# the checker records and is only as strong as whoever last blessed it.
# `emit | read | emit == emit` is a property a re-bless cannot satisfy.
#
# A reader that keeps raw lines and hands them back also satisfies it,
# and a line-oriented format invites `readlines`. So a non-normal file
# goes in too: the same facts with doubled spaces. A decomposing reader
# normalises it, so the output must differ from the input and the
# normalised form must be a fixed point.
#
# The corpus is a probe importing every stdlib module, plus the
# compiler's own `self_host/` entry. Each is emitted twice, as `--axir`
# and as `--axir --mir`, because only the second carries bodies: `blk`,
# `op` and `term` lines for every function that `mLowerFn` in
# `self_host/mir.ax` lowers and `mirVerify` passes.
#
# `--mir` must not cost a multiple of what the plain stream costs: its
# peak memory is held to four times the plain stream's, for each input.
# The compiler's own entry measures 2.7 times (the region fixpoint), the
# probe 1.1 times. The verifier's dominators were once an n-by-n matrix,
# and the probe's unrolled hash rounds (5,460 blocks in one function)
# made that 26 times, 19 GB: more than a CI runner has.
#
# The hand-written fixtures in `tests/axir/` cover what the compiler
# does not write. `body.axir` names blocks `entry` and `loop` and uses
# opcodes this IR does not have: the grammar is a format, and a reader
# that accepted only today's output would refuse tomorrow's.
#
# Ablations, each of which must turn this gate red:
#   1. Make `axirWrite` drop the `@nid` from the header: the corpus
#      round trip stops matching.
#   2. Make `axirRead` keep raw lines instead of decomposing them: the
#      non-normal file comes back byte-identical.
#   3. Delete an arm from `axirKindArityMin` so an unknown kind is
#      accepted: a `.bad` fixture stops being refused.
#   4. Drop the `(== mir 1)` guard around `axirLowered` in `axirRender`:
#      the default stream grows body lines and "only under --mir" fires.
#      The corpus round trip stays green, which is why that section
#      exists.
#   5. Make `axirLowered` answer 0 for every declaration: the round trip
#      is perfect and only the body floor fires. An emitter that stopped
#      emitting is invisible to `emit | read | emit == emit`.
#   6. Stop `axirWrite` putting the `%` back on a `blk` parameter: the
#      `--mir` round trip breaks on the first join block (`blk bb3 %5`
#      comes back as `blk bb3 5`).
#   7. Remove the `blk` arm from `axirDecompose` and the `%` from
#      `axirWrite` together: every section stays green except the
#      refusal of `blk-param-without-sigil.bad`, the only evidence for
#      that reader arm.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

# `--axir` is a flag, and the driver's flag table is closed: an unknown
# flag exits 2 before printing anything. Probe it first, or the gate
# would die on its first call under `set -e` and report nothing, which
# looks the same as a gate that did not run.
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
# the tree and covers a module as soon as it lands, as in
# `check-agent-calls.sh`.
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

# peak_kb <report> <command...>: run the command with its own stdout and
# stderr, and write its peak memory in KiB to <report>. Darwin's
# "peak memory footprint" counts compressed pages, which its resident
# set does not, so it is preferred where `time` prints it. `ru_maxrss`
# is bytes on Darwin and KiB elsewhere, as in `max_rss_kb`.
peak_kb() {
  local rep="$1"; shift
  if /usr/bin/time -l true >/dev/null 2>&1; then
    local div=1
    if [[ "$(uname -s)" == Darwin ]]; then div=1024; fi
    /usr/bin/time -l -o "$rep.time" "$@" || return
    awk -v div="$div" '
      /peak memory footprint/ { fp = int($1 / 1024) }
      /maximum resident set size/ { rss = int($1 / div) }
      END { print (fp > 0 ? fp : rss) }' "$rep.time" > "$rep"
  elif /usr/bin/time -v true >/dev/null 2>&1; then
    /usr/bin/time -v -o "$rep.time" "$@" || return
    awk -F: '/Maximum resident set size/ { print int($2) }' "$rep.time" > "$rep"
  else
    echo "FAIL: no usable time(1), so the --mir stream's memory cannot be measured"
    exit 1
  fi
}

records=0
bodies=0
# Both streams, because they are different files: `--mir` adds the
# `region` line and the whole body. `--mir` is the slow one, because it
# forces the region-facts fixpoint.
for src in "$work/probe.ax" self_host/main.ax; do
  name="$(basename "$src" .ax)"
  ( cd "$(dirname "$src")" && export AXIOM_STDLIB="$repo_root/stdlib" && \
      peak_kb "$work/$name.a.kb" "$axc" symbols --axir "$(basename "$src")" ) > "$work/$name.a.axir"
  "$axc" symbols --axir "$work/$name.a.axir" > "$work/$name.b.axir"
  if ! cmp -s "$work/$name.a.axir" "$work/$name.b.axir"; then
    echo "FAIL: $src does not round-trip; first difference:"
    diff "$work/$name.a.axir" "$work/$name.b.axir" | head -10 | sed 's/^/     /'
    exit 1
  fi
  ( cd "$(dirname "$src")" && export AXIOM_STDLIB="$repo_root/stdlib" && \
      peak_kb "$work/$name.m.kb" "$axc" symbols --axir --mir "$(basename "$src")" ) > "$work/$name.m.axir"
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
# The memory bound the header states, per input.
for name in probe main; do
  a_kb="$(cat "$work/$name.a.kb")"; m_kb="$(cat "$work/$name.m.kb")"
  if ! [[ "$a_kb" =~ ^[0-9]+$ && "$m_kb" =~ ^[0-9]+$ ]] || (( a_kb == 0 )); then
    echo "FAIL: no peak memory was read for $name (plain '$a_kb' KiB, --mir '$m_kb' KiB)."
    echo "      A bound over an empty measurement holds for anything."
    exit 1
  fi
  if (( m_kb > 4 * a_kb )); then
    echo "FAIL: the --mir stream for $name peaked at $(( m_kb / 1024 )) MiB, more than four"
    echo "      times the plain stream's $(( a_kb / 1024 )) MiB. Something the bodies or the"
    echo "      region facts keep grows faster than the program does."
    exit 1
  fi
  echo "ok   $name: --mir peaked at $(( m_kb / 1024 )) MiB against $(( a_kb / 1024 )) MiB for the plain stream (bound: four times)"
done

# A floor, because an emitter that wrote only the magic line would
# round-trip flawlessly.
if (( records < 400 )); then
  echo "FAIL: only $records records over the whole corpus; the floor is 400"
  echo "      (4,862 on 2026-09-03). An empty file round-trips perfectly."
  exit 1
fi

echo
echo "== the body lines are written under --mir and nowhere else =="
# Three claims, and the third is one a round trip cannot make.
#
# 1. The default stream carries no body. Tools that do not want to pay
#    for the region fixpoint read `--axir`, and a body there would move
#    a file nobody asked to move.
# 2. `--mir` is additive at the byte level: delete every `blk`, `op` and
#    `term` line and the default stream is left, apart from the `region`
#    line. This is check-mir-projection.sh's silence property for this
#    stream.
# 3. A floor and an opcode census. An emitter that writes no bodies
#    passes the round trip, which cannot tell a working lowering from
#    one that refuses everything. The census comes from `mir.ax`'s
#    operator table and `axir.ax`'s terminator writer, so the corpus
#    must reach any opcode added to either.
for name in probe main; do
  if grep -qE '^(blk|op|term) ' "$work/$name.a.axir"; then
    echo "FAIL: the default \`--axir\` stream for $name carries body lines. They cost"
    echo "      a lowering of every function in the program, and --mir is the flag"
    echo "      documented as the slow one:"
    grep -nE '^(blk|op|term) ' "$work/$name.a.axir" | head -3 | sed 's/^/     /'
    exit 1
  fi
  grep -vE '^(blk|op|term) ' "$work/$name.m.axir" > "$work/$name.stripped"
  # `--mir` also adds the region line. This claim is only about the
  # body, so region lines come out of both sides.
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
# The opcode census, derived from the sources. `mBinOp` answers the MIR
# spelling of an Axiom binary operator on its own line; `axirOpLine`
# spells the two non-operator opcodes and `axirTermLine` the five
# terminators. The corpus must reach every spelling they produce.
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
# because the grammar is a format independent of any one lowering.
# `lowered.axir` is the emitted shape verbatim.
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
# Kept apart from `$bodies`, which counts the emitted corpus, so the
# summary line reports that count and not the fixtures'.
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
# The normal form must hold the same facts, not a shorter file.
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
# The magic line selects the reader, not the extension: an `.axir` file
# named `.ax` must still read back, and a source file must compile
# whatever it is called.
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
