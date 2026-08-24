#!/usr/bin/env bash
# Assert that the standard library performs exactly the effects it
# declares, and that the set of declarations performing them is the one
# checked in.
#
# This is `docs/agent-harness.md` §3.4's Agent.Policy, and it is a GATE
# rather than a compiler mode on purpose. The document gives three
# reasons; the operative one is that the only boundary policy that has
# ever worked in this repository is `check-ffi.sh` comparing a binary's
# symbols against a checked-in manifest, with a negative probe proving
# the manifest can go red. This is that shape, over the AXSYM stream
# instead of over `nm`.
#
# WHAT IT READS. `axiom --diagnostic-format=ai symbols` prints one line
# per declaration carrying, among other things, the effect row the
# CHECKER derived (`#effects=`) and the claim the AUTHOR wrote
# (`#effect=`). A policy is the comparison of the two, which is why
# neither `Agent.Tags` nor any other library does it: a library the
# program under inspection could link against itself is not a boundary.
#
# THE TWO ASSERTIONS, and they fail for different reasons.
#
#   1. POPULATION. The set of stdlib declarations the checker derives an
#      effect for must equal `tests/agent/stdlib-effects.allow`. A new
#      one appearing is the interesting direction - a library function
#      that quietly starts reaching the outside world - and one
#      disappearing is worth a look too, since it usually means an
#      effect stopped being inferred rather than stopped happening.
#
#   2. AGREEMENT. Every stdlib declaration the checker derives IO for
#      must also CLAIM it. This is opt-in for a program - the reference
#      says untagged functions are not policed - but for the standard
#      library it is the property that makes the claims worth reading at
#      all: 60 of the 62 already carried the tag when this gate was
#      written, and the two that did not (`sysReadFile`, `sysReadAll`)
#      were found by running it.
#
#      IO AND NOT EVERY EFFECT, deliberately. Once `__alloc` carries
#      `Alloc` the library derives it for 108 declarations, and none of
#      them claims it - nor should they have to. IO is the effect that
#      crosses the process boundary and the one this library has always
#      declared; requiring a tag for allocation would be requiring 108
#      restatements of a fact the row beside it already carries. The
#      POPULATION check above still covers `Alloc`, so a declaration
#      that starts allocating is still visible - it is only the
#      author-claim requirement that is scoped.
#
# `extern` items are exempt from the second assertion and named in the
# manifest for the first. The compiler gives every `extern` item
# `#effects=IO` by construction rather than by inference, so requiring
# an author claim there would be requiring a restatement of a fact the
# compiler already knows.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

allow="tests/agent/stdlib-effects.allow"
[[ -f "$allow" ]] || { echo "FAIL: $allow is missing"; exit 1; }

gate_build_axc axc

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The probe imports every stdlib module, so the symbol stream is the
# whole library's. It lives in its own directory because module
# resolution searches the ENTRY FILE'S OWN directory first, and a stray
# `Err.ax` beside the probe would shadow the real one - which is how
# this gate's first run reported 0 symbols.
cat > "$work/probe.ax" <<'PROBE'
(import IO)

(import Str)

(import Vec)

(import Map)

(import Json)

(import Rpc)

(import Job)

(import Path)

(import Fmt)

(import Utf8)

(import Intern)

(import Err)

(import Ffi)

(import Agent.Tags)

(:: main Int)

(fn (main) 0)
PROBE

( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" "$axc" --diagnostic-format=ai symbols probe.ax ) \
  > "$work/axsym" 2>/dev/null

rows=$(grep -c '^F ' "$work/axsym" || true)
if (( rows < 300 )); then
  echo "FAIL: the probe listed only $rows declarations; the floor is 300"
  echo "      (a probe that resolves nothing lists nothing and would pass every check below)"
  exit 1
fi
echo "ok   the probe lists $rows declarations across the standard library"

# `name effects`, deduplicated: a symbol reachable through two import
# paths is listed twice, which is a property of the stream and not of
# the library.
grep '^F ' "$work/axsym" \
  | grep 'stdlib/' \
  | grep -oE '^F [^ ]+ [^ ]+ .*#effects=[A-Za-z,]+' \
  | sed -E 's|^F ([^ ]+) [^ ]*/([^/ :]+):[0-9].*#effects=([A-Za-z,]+)$|\1 \2 \3|' \
  | sort -u > "$work/derived"

echo
echo "== population: the effects the standard library performs =="
if ! diff -u "$allow" "$work/derived" > "$work/popdiff"; then
  echo "FAIL: the derived effect set differs from $allow"
  sed 's/^/     /' "$work/popdiff" | head -40
  echo '     a + line is a declaration that started performing an effect;'
  echo '     a - line is one that stopped, or stopped being inferred.' 
  exit 1
fi
echo "ok   $(wc -l < "$allow" | tr -d ' ') declarations, exactly as $allow says"

echo
echo "== agreement: every derived IO is a declared IO =="
# The claim and the derivation on one line. An `extern` item is exempt:
# its row is constructed, not inferred.
undeclared=$(grep '^F ' "$work/axsym" \
  | grep 'stdlib/' \
  | grep -E '#effects=([A-Za-z]+,)*IO' \
  | grep -v '#effect=io' \
  | grep -v 'Ffi.ax' \
  | awk '{print $2}' | sort -u || true)
if [[ -n "$undeclared" ]]; then
  echo "FAIL: these perform an effect the author did not claim:"
  echo "$undeclared" | sed 's/^/     /'
  echo '     add ;@axiom:effect(io) above the declaration, or add it to'
  echo '     the exempt list in this gate with the reason.' 
  exit 1
fi
echo "ok   every stdlib declaration performing an effect also claims it"

echo
echo "== negative probes: both assertions can go red =="
# A gate that has never been seen to fail is a gate nobody has checked.
sed '1d' "$allow" > "$work/short.allow"
if diff -q "$work/short.allow" "$work/derived" >/dev/null 2>&1; then
  echo "FAIL negative: dropping a manifest line did not change the comparison"
  exit 1
fi
echo "ok   dropping one manifest line makes the population check differ"

cat > "$work/liar.ax" <<'LIAR'
(import IO)

(:: shout (-> Int Int))

(fn (shout n)
  {
    (println "io")
    n
  }
)

(:: main Int)

;@axiom:effect(io)
(fn (main) (shout 1))
LIAR
if ( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" "$axc" --diagnostic-format=ai symbols liar.ax 2>/dev/null ) \
     | grep -q '^F shout .*#effects=IO'; then
  if ( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" "$axc" --diagnostic-format=ai symbols liar.ax 2>/dev/null ) \
       | grep '^F shout ' | grep -q '#effect='; then
    echo "FAIL negative: an untagged IO function reported a claim it does not carry"
    exit 1
  fi
  echo "ok   an untagged IO function is visible to the agreement check"
else
  echo "FAIL negative: the agreement check cannot see an untagged IO function"
  exit 1
fi

echo
echo "check-agent-policy: the standard library performs what it declares,"
echo "                    and the set that performs anything is the one on file"
