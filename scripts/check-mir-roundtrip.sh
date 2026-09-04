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
# WHAT IS IN THE CORPUS. Every `.ax` under tests/axir/ is compiled and
# its records round-tripped; so is the compiler's own `self_host/`
# entry, which is the largest module this repository has. The
# hand-written `.axir` fixtures cover what nothing can yet emit -
# `blk`, `op` and `term` are in the grammar and in the reader because a
# mid-level IR will write them, and a reader arm nothing exercises is a
# reader arm that is wrong the day something does.
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
  n=$(grep -c '^F ' "$work/$name.a.axir" || true)
  records=$(( records + n ))
  echo "ok   $src: $n records, identical after read-back"
done
# A floor, because an emitter that answered the magic line alone would
# round-trip flawlessly.
if (( records < 400 )); then
  echo "FAIL: only $records records over the whole corpus; the floor is 400"
  echo "      (4,862 on 2026-09-03). An empty file round-trips perfectly."
  exit 1
fi

echo
echo "== the hand-written fixtures round-trip too =="
# These carry `blk`, `op` and `term`, which nothing emits yet.
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
bodies=$(grep -l '^blk ' tests/axir/*.axir 2>/dev/null | wc -l | tr -d ' ')
if (( bodies < 1 )); then
  echo "FAIL: $fixtures fixtures and not one carries a \`blk\` line, so the"
  echo "      reserved half of the grammar is untested."
  exit 1
fi
echo "ok   $fixtures fixtures round-trip, $bodies of them carrying block bodies"

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
if (( bad < 3 )); then
  echo "FAIL: only $bad malformed fixtures under tests/axir/*.bad; there were 5"
  echo "      on 2026-09-03. This assertion is as strong as the corpus behind it."
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
echo "ok   check-mir-roundtrip: $records records and $fixtures fixtures round-trip; $bad malformed files refused"
