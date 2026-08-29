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
# THE FOUR ASSERTIONS, and they fail for different reasons.
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
#   3. COMPLETENESS. No stdlib declaration may carry the
#      `#effects-incomplete` meta.
#
#      Assertions 1 and 2 both key on the `#effects=` substring, and a
#      declaration whose effect walk did not resolve a call HAS NO
#      `#effects=` FIELD AT ALL. `typecheck.ax`'s walk pushes an
#      `effIncomplete` sentinel when it meets a call head it cannot
#      resolve - a struct field, or an opaque local holding a function -
#      and `symbols.ax` renders that as its own meta precisely because
#      "`#effects=` is a lower bound, not the set" (symbols.ax:1028).
#      A row with nothing but the sentinel is, to a check that greps for
#      `#effects=`, INDISTINGUISHABLE FROM ONE PROVEN TO PERFORM
#      NOTHING.
#
#      Measured 2026-08-23, against a module holding
#      `(struct Box (f : (-> Int Int)))`, a `println`-ing `direct`, and
#      a `;@axiom:pure`-claimed `(fn (viaField b n) ((b.f) n))` called
#      as `(viaField (Box direct) 0)`: the built program PRINTS at run
#      time, its row reads
#
#        F viaField probe.ax:14:5-13 "(Box -> (Int -> Int))" @... #pure #effects-incomplete
#
#      and assertions 1 and 2 both passed it. That is the whole hole:
#      the compiler said "I could not check this" and the gate threw the
#      sentence away. A stdlib declaration reached through a struct
#      field or a function-valued local could therefore perform any
#      effect with this gate green.
#
#      So the marker is now a FAILURE, not a silence. `#effects=` is
#      only a lower bound where the sentinel rides; refusing the
#      sentinel outright is what makes assertions 1 and 2 read as the
#      upper bounds they are documented to be.
#
#   4. THE CHECKER'S OWN WARNINGS. The compiler has a second channel for
#      the same doubt - `AX3037` (a claim that cannot be checked),
#      `AX3038` (a handled-effects list that cannot be checked) and
#      `AX3010` (a claim the derivation contradicts) - and all three are
#      WARNINGS on stderr. This script used to send that stderr to
#      `/dev/null`, so the `viaField` module above emitted
#      `W AX3037 ... 'pure' claim cannot be checked` and the gate never
#      saw it. stderr is now captured and any of the three, on a span
#      inside `stdlib/`, fails the gate.
#
#      `AX3010` is in the set even though the finding that prompted this
#      only named 3037/3038: it is the diagnostic that fires on a FORGED
#      claim (see the anchoring note below), and discarding it was the
#      same defect. This does not promote the diagnostic - it is still a
#      warning to the compiler; it is this GATE that refuses it.
#
# `extern` items are exempt from the second assertion and named in the
# manifest for the first. The compiler gives every `extern` item
# `#effects=IO` by construction rather than by inference, so requiring
# an author claim there would be requiring a restatement of a fact the
# compiler already knows.
#
# EVERY FIELD MATCH IN THIS SCRIPT IS ANCHORED, and that is a rule, not
# a style. An AXSYM meta's value can be SOURCE TEXT: `saAxMeta`
# (symbols.ax:448) takes an AXTAG's value as everything from the first
# `(` to the last `)`, so the author writes the bytes that land after
# `#effect=`. This script used to filter claimed-IO rows with
# `grep -v '#effect=io'`, an unanchored substring match on exactly that
# field. Measured 2026-08-23: `;@axiom:effect(iohazard)` above a
# `println`-ing function renders
#
#        F shout forge.ax:3:5-10 "(Int -> Int)" @... #effect=iohazard #effects=IO
#
#   and the gate ACCEPTED it as a declared IO - `iohazard` contains
#   `io`. The compiler had already refused it, as
#   `AX3010 ... 'effect(iohazard)' claim unsupported`, on the stderr
#   this script was discarding. (That line rendered `W` when this was
#   written; AX3010 became an ERROR on 2026-08-25. The severity letter
#   is not what `axerr_hits` matches on, so the ablation still lands.) The filter is now
#   `#effect=io( |$)`, and the path matches are `index($3, prefix) == 1`
#   on the SPAN FIELD rather than `grep 'stdlib/'` on the whole line.
#
#   A residue is left on purpose, because it is not this file's to fix:
#   the same source-controlled value can inject a whole extra meta -
#   `;@axiom:effect(io #effects=IO)` measures as
#   `#effect=io #effects=IO #effects=IO` - and the fix for that is in
#   `symbols.ax`. What this script does about it is cheap and sound: a
#   row carrying more than one `#effects=` is refused as malformed,
#   which catches that measured shape without this gate trying to
#   re-implement the AXTAG grammar.
#
# THE MODULE LIST IS DERIVED FROM THE TREE. The probe below used to
# carry a hand-written 14-import list, and the population assertion was
# documented as covering "the standard library" while it actually
# covered the transitive closure of those fourteen. A module outside the
# closure contributes no AXSYM rows, so a declaration in it that starts
# performing IO appears in NEITHER assertion, and the 300-row floor
# cannot see the gap - 448 rows arrive either way. The list is now
# `stdlib/*.ax` plus `stdlib/*/*.ax`, mapped to module names, so a
# module is covered the day it lands rather than the day someone
# remembers this file. Deriving it added `Mem`, `Pre`, `Show`, `Sys` and
# `Sys.Platform` and changed the derived population by nothing, which is
# the measurement that says the fourteen were right TODAY and says
# nothing about tomorrow.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

allow="tests/agent/stdlib-effects.allow"
[[ -f "$allow" ]] || { echo "FAIL: $allow is missing"; exit 1; }

gate_build_axc axc

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

stdlib_prefix="$repo_root/stdlib/"

# The four matchers every assertion and every negative probe goes
# through. They are functions rather than inline pipelines so that the
# probes at the bottom exercise the SAME code the assertions do: a
# negative probe against a second copy of a regex proves the copy works.
#
# `axsym_rows <axsym> <path-prefix>` - the `F` rows whose span begins
# with <path-prefix>. Anchored at position 1 of field 3, so a row can
# neither smuggle the prefix in through a meta value nor be matched by a
# path that merely contains it.
axsym_rows() {
  awk -v p="$2" '$1 == "F" && index($3, p) == 1' "$1"
}

# `axsym_files <rows> <repo-root>` - the repo-relative source file each
# row came from, deduplicated. `substr` and not `sub`, because a path is
# not a regex.
axsym_files() {
  awk -v p="$2/" '{ s = $3; sub(/:[0-9]+:[0-9]+-[0-9]+$/, "", s); print substr(s, length(p) + 1) }' "$1" \
    | LC_ALL=C sort -u
}

# `axerr_hits <stderr> <path-prefix>` - the AX3010/AX3037/AX3038
# diagnostics reported against a span under <path-prefix>. `W` and `E`
# both, so promoting one of these to an error does not make this check
# stop seeing it.
axerr_hits() {
  awk -v p="$2" '
    ($1 == "W" || $1 == "E") &&
    ($2 == "AX3010" || $2 == "AX3037" || $2 == "AX3038") &&
    index($3, p) == 1' "$1"
}

# `name file` from a row, for reporting and for the exempt lists.
axsym_name_file() {
  sed -E 's|^F ([^ ]+) [^ ]*/([^/ :]+):[0-9].*|\1 \2|' | LC_ALL=C sort -u
}

# Every module in the tree, as `<module> <file>` pairs. `Platform.ax`
# has three platform spellings and one module name, so the basename is
# cut at its FIRST dot: `stdlib/Sys/Platform.darwin.ax` is `Sys.Platform`,
# which is what `stdlib/Sys.ax:20` imports.
: > "$work/modfiles"
for f in stdlib/*.ax stdlib/*/*.ax; do
  [[ -e "$f" ]] || continue
  rel="${f#stdlib/}"
  dir="$(dirname "$rel")"
  base="$(basename "$rel" .ax)"
  base="${base%%.*}"
  if [[ "$dir" == "." ]]; then
    printf '%s %s\n' "$base" "$f" >> "$work/modfiles"
  else
    printf '%s.%s %s\n' "${dir//\//.}" "$base" "$f" >> "$work/modfiles"
  fi
done
awk '{print $1}' "$work/modfiles" | LC_ALL=C sort -u > "$work/modules"

modcount=$(wc -l < "$work/modules" | tr -d ' ')
if (( modcount < 15 )); then
  echo "FAIL: derived only $modcount stdlib modules from the tree; there were 19 on 2026-08-23"
  echo "      (a derivation that finds nothing imports nothing and would pass every check below)"
  exit 1
fi

# The probe imports every stdlib module, so the symbol stream is the
# whole library's. It lives in its own directory because module
# resolution searches the ENTRY FILE'S OWN directory first, and a stray
# `Err.ax` beside the probe would shadow the real one - which is how
# this gate's first run reported 0 symbols.
{
  while read -r m; do
    printf '(import %s)\n\n' "$m"
  done < "$work/modules"
  printf '(:: main Int)\n\n(fn (main) 0)\n'
} > "$work/probe.ax"

( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" "$axc" --diagnostic-format=ai symbols probe.ax ) \
  > "$work/axsym" 2> "$work/axerr"

axsym_rows "$work/axsym" "$stdlib_prefix" > "$work/rows"

rows=$(wc -l < "$work/rows" | tr -d ' ')
if (( rows < 300 )); then
  echo "FAIL: the probe listed only $rows declarations under $stdlib_prefix; the floor is 300"
  echo "      (a probe that resolves nothing lists nothing and would pass every check below)"
  echo "      it imported $modcount modules and the stream held $(grep -c '^F ' "$work/axsym" || true) rows in total,"
  echo "      so a mismatch between those two numbers is a path-prefix problem, not a coverage one"
  exit 1
fi
echo "ok   the probe imports $modcount stdlib modules and lists $rows declarations from them"

# A module that resolves but contributes no row is a hole in assertions
# 1 and 2 the row count cannot show, so each one is named here with the
# reason it is empty. Measured 2026-08-23 with `symbols` over a probe
# importing all 19.
cat > "$work/rowless.exempt" <<'ROWLESS'
Pre    macros only - `when`, `unless`, `cond2`, `deriveShow`. A macro is
Pre    expanded into its caller and has no declaration of its own to
Pre    carry an effect row.
Show   a trait, four impls and one macro, and no top-level `fn`. An impl
Show   METHOD BODY gets no AXSYM row at all: measured with an
Show   `(impl (Show T) ((show (lambda (v) { (println "io") "s" }))))`,
Show   the stream held no `F` row for it and the IO surfaced only on the
Show   caller's row as `#effects=Alloc,IO`. That is a real gap in this
Show   gate's input and it is `symbols.ax`'s to close, not this file's;
Show   until it is, a `Show` instance in the standard library is policed
Show   only through whoever calls it.
ROWLESS
awk '{print $1}' "$work/rowless.exempt" | LC_ALL=C sort -u > "$work/rowless.names"

axsym_files "$work/rows" "$repo_root" > "$work/hitfiles"
while read -r mm ff; do
  if grep -qxF "$ff" "$work/hitfiles"; then echo "$mm"; fi
done < "$work/modfiles" | LC_ALL=C sort -u > "$work/covered"
comm -23 "$work/modules" "$work/covered" | comm -23 - "$work/rowless.names" > "$work/uncovered"
if [[ -s "$work/uncovered" ]]; then
  echo "FAIL: these stdlib modules contributed no declaration to the stream,"
  echo "      so nothing in them is covered by either assertion below:"
  sed 's/^/     /' "$work/uncovered"
  echo '     either the module does not resolve, or it holds no top-level'
  echo '     `fn` - add it to the rowless exempt list in this gate WITH THE'
  echo '     reason, the way `Pre` and `Show` are written.'
  exit 1
fi
echo "ok   every stdlib module either contributes declarations or is exempt with a reason"

# `name effects`, deduplicated: a symbol reachable through two import
# paths is listed twice, which is a property of the stream and not of
# the library.
#
# The `.*#effects=` is greedy and therefore reads the LAST such field on
# the row. That is safe only because the malformed-row check below
# refuses a row carrying two of them; without it, a forged meta appended
# to a claim would be the one this line believes.
# `LC_ALL=C` ON EVERY SORT IN THIS FILE, AND IT IS NOT A STYLE CHOICE.
# The list below is CHECKED IN, so its ORDER is part of a golden, and
# `sort` collates by the runner's locale unless told otherwise. Measured
# 2026-08-25: `en_US.UTF-8` orders `sysEnvp` before `sysEnvSlot` and `C`
# orders them the other way, so a list blessed on a developer machine
# and compared on a CI runner differ by two lines and nothing else. All
# 44 local gates were green and all three CI `Tests` legs went red -
# including darwin, so it is the LOCALE and not the platform.
#
# It was invisible until this commit because no two names in the list
# had ever differed at a letter whose case decides the order. `gate.sh`
# already carries the rule for the seed stamp - "a property of the tree,
# not of where it was checked out or of the runner's locale" - and this
# file simply had not applied it. The `comm` calls need it too: `comm`
# requires both inputs collated the same way, and silently answers
# nonsense when they are not.
grep -oE '^F [^ ]+ [^ ]+ .*#effects=[A-Za-z,]+' "$work/rows" \
  | sed -E 's|^F ([^ ]+) [^ ]*/([^/ :]+):[0-9].*#effects=([A-Za-z,]+)$|\1 \2 \3|' \
  | LC_ALL=C sort -u > "$work/derived"

echo
echo "== population: the effects the standard library performs =="
# A BLESS PATH, which this file lacked while `check-tools-selfhost.sh`
# had one for its sibling golden. The allow list is not a judgement -
# it is what the checker DERIVES, checked in so that a change to it is
# a line in a diff somebody reads rather than a silent drift. Adding a
# standard-library function therefore moves it, and re-deriving it by
# hand meant reproducing this pipeline by hand.
#
# It is still not a rubber stamp: the diff below is what a reviewer
# reads, and the point of the file is that the delta is small enough to
# read. Bless it when the delta is what you meant.
if [[ "${AXIOM_BLESS:-0}" == 1 ]]; then
  cp "$work/derived" "$repo_root/$allow"
  echo "blessed $allow"
fi
if ! diff -u "$allow" "$work/derived" > "$work/popdiff"; then
  echo "FAIL: the derived effect set differs from $allow"
  sed 's/^/     /' "$work/popdiff" | head -40
  echo '     a + line is a declaration that started performing an effect;'
  echo '     a - line is one that stopped, or stopped being inferred.'
  exit 1
fi
echo "ok   $(wc -l < "$allow" | tr -d ' ') declarations, exactly as $allow says"

# AND THE CHECK THAT WOULD HAVE CAUGHT THAT BEFORE CI DID. The
# comparison above cannot: if the derivation's `sort` loses its
# `LC_ALL=C` again, the re-bless and the compare move together, so the
# gate stays green on the machine that blessed it and goes red on every
# other one. This asks the file a question that does not depend on the
# derivation at all - is it in C collation order? - and it is
# meaningful in every locale, which a probe that re-sorts under a NAMED
# second locale would not be: a runner without that locale silently
# falls back to C and the probe passes for the wrong reason.
if ! LC_ALL=C sort -c "$allow" 2>/dev/null; then
  echo "FAIL: $allow is not in C collation order, so its order depends on"
  echo "      whichever locale blessed it. Re-bless with the sorts in this"
  echo "      file pinned to LC_ALL=C - see the comment above \`derived\`."
  failed=$((failed + 1))
else
  echo "ok   $allow is in C collation order, so it reads the same on every runner"
fi

echo
echo "== agreement: every derived IO is a declared IO =="
# A row may carry one derived effect list and one claim. More than one
# `#effects=` is not a library that changed, it is a meta that was
# written by the source - see the anchoring note in the header.
# `gsub` with `&` replaces each match with itself and returns the count.
malformed=$(awk '{ if (gsub(/#effects=/, "&") > 1) print }' "$work/rows" || true)
if [[ -n "$malformed" ]]; then
  echo "FAIL: these rows carry more than one #effects= field, which the"
  echo "      checker does not emit - an AXTAG value forged one:"
  echo "$malformed" | sed 's/^/     /' | head -10
  exit 1
fi
echo "ok   every row carries at most one derived effect list"

# The claim and the derivation on one line. One exemption, and it is
# anchored to the SPAN FIELD so that a path merely containing the name -
# `stdlib/MyFfi.ax`, or a meta value spelling `Ffi.ax` - does not
# inherit it: an `extern` item in `stdlib/Ffi.ax`, whose row is
# constructed rather than inferred, so an author claim there would
# restate what the compiler already knows.
#
# `IO(,| |$)` and not a bare `IO`: the list is comma-joined and sorted,
# and `Mut`, `Pure` and any custom effect sort after `IO`, so `IO` is
# not always last. The right anchor is "IO is a whole element of the
# list", which is all three of those endings and no other.
undeclared=$(grep -E '#effects=([A-Za-z]+,)*IO(,| |$)' "$work/rows" \
  | grep -v -E '#effect=io( |$)' \
  | awk -v p="$stdlib_prefix" 'index($3, p "Ffi.ax:") != 1' \
  | awk '{print $2}' | LC_ALL=C sort -u || true)
if [[ -n "$undeclared" ]]; then
  echo "FAIL: these perform an effect the author did not claim:"
  echo "$undeclared" | sed 's/^/     /'
  echo '     add ;@axiom:effect(io) above the declaration, or add it to'
  echo '     the exempt list in this gate with the reason.'
  exit 1
fi
echo "ok   every stdlib declaration performing an effect also claims it"

echo
echo "== completeness: no effect row is only a lower bound =="
# Declarations allowed to carry `#effects-incomplete`, one `<name>
# <file>` per line with the reason beside it. An entry here is a
# declaration whose effects the compiler admits it cannot enumerate; it
# must say why that is acceptable, and "it looks fine" is not a reason.
#
# THE LIST WAS EMPTY UNTIL 2026-08-25, and that emptiness was the
# finding this assertion was written for: on 2026-08-23 no stdlib
# declaration carried the sentinel, so refusing it outright cost the
# library nothing and bought the property that assertions 1 and 2 are
# upper bounds rather than lower ones.
#
# It cost nothing because the library had no HIGHER-ORDER function that
# calls its argument. `vecSortBy` is the first, and it did not squeak
# past this check - it was refused by it, on the first run, which is
# what the check is for. The entries below are that refusal, examined
# and accepted rather than routed around.
#
# The property those two assertions have for the rest of the library is
# unchanged. What is lost is exactly this: for these two declarations,
# `#effects=Mut` means "at least Mut", because the comparator a caller
# supplies may perform anything at all. That is not a defect in the
# inference (`docs/memory-model.md` MM-EXEC-9a's one remaining row) and
# it is not fixable by naming a function at the call site - the call
# site's whole purpose is that the function is the caller's. A sort
# that could only order words its author anticipated would not be a
# sort.
#
# The row still ANNOUNCES itself: `#effects-incomplete` is on it and a
# `;@axiom:pure` claim over it would draw `AX3037`. A reader is handed
# a lower bound labelled as one, which is the honest half of the
# arrangement and the reason an entry here is acceptable at all.
# `<name> <file>  <reason>` - one line each, the reason being everything
# after the second field, so it has room to say something.
cat > "$work/incomplete.exempt" <<'INCOMPLETE'
vecSortBy     Vec.ax  calls the comparator the CALLER supplies, so its row is a lower bound by construction; the first higher-order function in this library and the first entry here
vecSiftDownBy Vec.ax  the same call one frame down, `vecSortBy`'s own helper
httpCall      Http.ax calls the handler a ROUTE holds - a function value the program registered with `routeAdd`, matched out of an `HttpHandler` cell - so its row is the router's lower bound by construction
routeDispatch Http.ax `httpCall` one frame up: the dispatcher hands the socket to whichever handler the table names
httpServeOne  Http.ax `routeDispatch` one frame up: read, dispatch, or write the parser's refusal
INCOMPLETE
awk 'NF { print $1, $2 }' "$work/incomplete.exempt" | LC_ALL=C sort -u > "$work/incomplete.exempted"
grep -F '#effects-incomplete' "$work/rows" | axsym_name_file > "$work/incomplete" || true
comm -23 "$work/incomplete" "$work/incomplete.exempted" > "$work/incomplete.unexempt"
if [[ -s "$work/incomplete.unexempt" ]]; then
  echo "FAIL: the checker could not enumerate these declarations' effects,"
  echo "      so their #effects= row is a LOWER BOUND and both assertions"
  echo "      above read it as an upper one:"
  sed 's/^/     /' "$work/incomplete.unexempt"
  echo '     the walk hit a call head it could not resolve - a struct'
  echo '     field, or a local holding a function. Name the function at'
  echo '     the call site, or add the declaration to the incomplete'
  echo '     exempt list in this gate WITH THE REASON.'
  exit 1
fi
echo "ok   the only #effects-incomplete rows are the $(awk 'NF{print $1}' "$work/incomplete.exempt" | LC_ALL=C sort -u | grep -c .) exempted by name"

echo
echo "== the checker's own doubt is this gate's failure =="
hits=$(axerr_hits "$work/axerr" "$stdlib_prefix" || true)
if [[ -n "$hits" ]]; then
  echo "FAIL: the compiler reported that it could not check these claims,"
  echo "      and this gate used to send that report to /dev/null:"
  printf '%s\n' "$hits" | sed 's/^/     /' | head -20
  echo '     AX3010 is a claim the derivation contradicts; AX3037 and'
  echo '     AX3038 are claims it could not check at all. Fix the claim'
  echo '     or name the function at the unresolved call.'
  exit 1
fi
echo "ok   the checker raised no AX3010/AX3037/AX3038 against stdlib"

echo
echo "== negative probes: every assertion can go red =="
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
# `shout` is untagged and performs IO, so since 2026-08-25 this file
# does not compile: AX3042 refuses it, and `symbols` exits 1. That is
# the enforcement this probe is about, so the exit status is ASSERTED
# rather than tolerated - a 0 here would mean the compiler stopped
# refusing an undeclared effect, and this probe would go on passing on
# the table alone.
#
# The table is still there to read because `symbols` prints it
# ALONGSIDE its diagnostics rather than instead of them. Both halves
# are checked: the row must carry the derived `#effects=IO`, and it
# must NOT carry a `#effect=` claim, because the source makes none.
#
# The output is captured to a file first. Piping `symbols` straight
# into `grep` under `set -o pipefail` makes the pipeline fail for the
# COMPILER's exit status, not the grep's - which is what this probe did
# when AX3042 landed, reporting "the agreement check cannot see an
# untagged IO function" while the row it wanted was sitting in stdout.
# `|| liar_rc=$?` and not `; liar_rc=$?`: this file runs under `set -e`,
# and a bare failing subshell kills the script BEFORE the assignment -
# which is how the first version of this probe exited 1 having printed
# no failure at all.
liar_rc=0
( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" "$axc" --diagnostic-format=ai symbols liar.ax \
    >"$work/liar.out" 2>/dev/null ) || liar_rc=$?
if [[ "$liar_rc" == 0 ]]; then
  echo "FAIL negative: an untagged IO function compiled (exit 0); AX3042 no longer refuses it"
  exit 1
fi
if ! grep -q -E '^F shout .*#effects=([A-Za-z]+,)*IO(,| |$)' "$work/liar.out"; then
  echo "FAIL negative: the agreement check cannot see an untagged IO function"
  exit 1
fi
if grep '^F shout ' "$work/liar.out" | grep -q '#effect='; then
  echo "FAIL negative: an untagged IO function reported a claim it does not carry"
  exit 1
fi
echo "ok   an untagged IO function is refused (exit $liar_rc) and still visible to the agreement check"

# The shape assertion 3 exists for, from the finding that produced it:
# an effect that reaches the outside world through a struct field, under
# a `pure` claim. Both of the older assertions pass this module.
cat > "$work/partial.ax" <<'PARTIAL'
(import IO)

(struct Box (f : (-> Int Int)))

(:: direct (-> Int Int))

;@axiom:effect(io)
(fn (direct n)
  {
    (println "io")
    n
  }
)

(:: viaField (-> Box (-> Int Int)))

;@axiom:pure
(fn (viaField b n) ((b.f) n))

(:: main Int)

;@axiom:effect(io)
(fn (main) (viaField (Box direct) 0))
PARTIAL
( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" "$axc" --diagnostic-format=ai symbols partial.ax ) \
  > "$work/partial.axsym" 2> "$work/partial.err" || true

if ! grep -q '^F viaField .*#effects-incomplete' "$work/partial.axsym"; then
  echo "FAIL negative: an unresolvable call head no longer marks the row incomplete,"
  echo "               so assertion 3 is asserting nothing"
  sed 's/^/     /' "$work/partial.axsym" | grep viaField || true
  exit 1
fi
if grep '^F viaField ' "$work/partial.axsym" | grep -q '#effects='; then
  echo "FAIL negative: the incomplete row now also carries #effects=, so it"
  echo "               is no longer the case that assertions 1 and 2 are blind"
  echo "               to it - re-read this gate's third assertion before"
  echo "               relaxing anything"
  exit 1
fi
echo "ok   an unresolved call head is invisible to #effects= and visible to the completeness check"

if [[ -z "$(axerr_hits "$work/partial.err" "partial.ax")" ]]; then
  echo "FAIL negative: the compiler raised no AX3037 for an uncheckable 'pure'"
  echo "               claim, or this gate's stderr matcher cannot see it"
  sed 's/^/     /' "$work/partial.err" | head -10
  exit 1
fi
echo "ok   an uncheckable claim reaches the gate through stderr"

# The unanchored-substring shape: a claim that merely BEGINS with `io`.
cat > "$work/forged.ax" <<'FORGED'
(import IO)

(:: shout (-> Int Int))

;@axiom:effect(iohazard)
(fn (shout n)
  {
    (println "io")
    n
  }
)

(:: main Int)

;@axiom:effect(io)
(fn (main) (shout 1))
FORGED
( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" "$axc" --diagnostic-format=ai symbols forged.ax ) \
  > "$work/forged.axsym" 2> "$work/forged.err" || true

forged_row=$(grep '^F shout ' "$work/forged.axsym" || true)
if [[ -z "$forged_row" ]]; then
  echo "FAIL negative: no row for the forged-claim probe"
  exit 1
fi
if ! printf '%s\n' "$forged_row" | grep -q -E '#effect=iohazard( |$)'; then
  echo "FAIL negative: the AXTAG value no longer reaches the meta verbatim,"
  echo "               so this probe is not testing the anchoring any more"
  printf '     %s\n' "$forged_row"
  exit 1
fi
if [[ -z "$(printf '%s\n' "$forged_row" | grep -v -E '#effect=io( |$)')" ]]; then
  echo "FAIL negative: 'effect(iohazard)' was read as a claim of 'io' - the"
  echo "               claim filter is matching an unanchored substring again"
  exit 1
fi
echo "ok   a claim of 'effect(iohazard)' is not read as a claim of 'io'"

if [[ -z "$(axerr_hits "$work/forged.err" "forged.ax")" ]]; then
  echo "FAIL negative: the compiler raised no AX3010 for an unsupported claim,"
  echo "               or this gate's stderr matcher cannot see it"
  sed 's/^/     /' "$work/forged.err" | head -10
  exit 1
fi
echo "ok   an unsupported claim reaches the gate through stderr"

# --------------------------------------------------------------------
echo
echo "== the primitives that PERFORM, against the effect each performs =="
# --------------------------------------------------------------------
# The population assertion above is a whole-library fact and moves for
# many reasons. This is the rule underneath it, one primitive at a time.
#
# `MM-EXEC-9a` says the inferred set is an under-approximation and that
# a conforming implementation SHOULD make it an over-approximation. Six
# of its rows were one defect: a primitive that PERFORMS something,
# registered like `__load64`, which computes. `__alloc` was corrected on
# 2026-08-23; `__store8`/`__store64`, `__argc`/`__argv` and the three
# arena primitives on 2026-08-25. The five atomics of 2026-08-29 are the
# first registered WITH their effects on arrival rather than corrected
# later, and they are asserted here from that day for the same reason
# the corrections are: a registration that is right today is a golden
# tomorrow unless something other than a golden holds it.
#
# A population golden cannot hold that rule. Re-blessing the allow list
# after a regression would make the gate agree with whatever the
# compiler now says - which is exactly what a golden is for, and exactly
# why the rule needs an assertion that is not a golden.
prim_case() {  # <name> <call> <wanted effect>
  printf '(:: probe (-> Int Int))\n\n(fn (probe n) %s)\n\n(:: main Int)\n\n(fn (main) 0)\n' "$2" \
    > "$work/prim.ax"
  # The probe is deliberately UNTAGGED, so the two IO primitives make it
  # a program that does not compile (AX3042) and `symbols` exits 1. That
  # is fine and is not what this measures: the subject is what the
  # INFERENCE reports on the row, and `symbols` prints its table
  # alongside diagnostics rather than instead of them. Tagging the probe
  # would couple it to the answer - the tag would have to name the
  # effect the case is trying to measure.
  #
  # A refusal is tolerated; a CRASH is not. Anything outside 0/1 is a
  # compiler that died, and this reports it rather than reading an empty
  # file as "the primitive performs nothing". Without the `|| rc=$?`
  # form, `set -e` killed the whole gate at the `__argc` case, printing
  # no failure at all.
  local rc=0
  ( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" "$axc" --diagnostic-format=ai symbols prim.ax ) \
    > "$work/prim.axsym" 2>/dev/null || rc=$?
  if [[ "$rc" != 0 && "$rc" != 1 ]]; then
    echo "FAIL primitives: \`$1\` - the compiler exited $rc (not a diagnostic; it died)"
    failed_prim=$((failed_prim + 1)); return
  fi
  local row; row="$(grep '^F probe ' "$work/prim.axsym" || true)"
  if [[ -z "$row" ]]; then
    echo "FAIL primitives: no row at all for \`$1\` - the probe stopped compiling"
    failed_prim=$((failed_prim + 1)); return
  fi
  local got; got="$(printf '%s\n' "$row" | grep -oE '#effects=[A-Za-z,]+' | sed 's/#effects=//' || true)"
  if [[ "$got" == "$3" ]]; then
    echo "ok   \`$1\` performs ${3:-nothing}"
  else
    echo "FAIL primitives: \`$1\` reported '${got:-nothing}', wanted '${3:-nothing}'"
    failed_prim=$((failed_prim + 1))
  fi
}
failed_prim=0
prim_case "__alloc"                     "(__alloc n)"                          "Alloc"
prim_case "__store64"                   "(__store64 n 0 42)"                   "Mut"
prim_case "__store8"                    "(__store8 n 0 42)"                    "Mut"
prim_case "__argc"                      "(__argc)"                             "IO"
prim_case "__argv"                      "(__argv n)"                           "IO"
prim_case "__axiom_arena_mark"          "(__axiom_arena_mark)"                 "Alloc"
prim_case "__axiom_arena_reset"         "(__axiom_arena_reset n)"              "Alloc"
prim_case "__axiom_arena_reset_keeping" "(__axiom_arena_reset_keeping n 0 0)"  "Alloc"
# The atomics that WRITE or ORDER carry `Mut`: a store, an add and a
# compare-and-swap write a word every alias of it sees, and a fence
# exists only to order such writes. The load is a control, below.
prim_case "__atomic_store"              "(__atomic_store n 42)"                "Mut"
prim_case "__atomic_add"                "(__atomic_add n 1)"                   "Mut"
prim_case "__atomic_cas"                "(__atomic_cas n 0 1)"                 "Mut"
prim_case "__fence"                     "(__fence)"                            "Mut"
# THE CONTROLS, and they are what make the eight above mean anything. A
# registration that gave EVERY primitive an effect would satisfy all of
# them and destroy the discrimination the whole mechanism is for. These
# two compute, they are spelled exactly like the ones above, and they
# must report nothing.
prim_case "__load64 (control)"          "(__load64 n 0)"                       ""
prim_case "__load8 (control)"           "(__load8 n 0)"                        ""
# `__atomic_load` is the control among the atomics: it reads a word as
# `__load64` does, and the atomic spelling changes the instruction's
# ordering, not what the function performs. It must stay silent, or
# the four above are measuring the prefix `__atomic` and not the write.
prim_case "__atomic_load (control)"     "(__atomic_load n)"                    ""
# And `__retain`/`__release` are the deliberate omission `MM-EXEC-9a`
# names: their writes are the runtime's own bookkeeping, and giving them
# `Mut` marks every function that touches a reference.
prim_case "__retain (deliberate)"       "(__retain n)"                         ""
if (( failed_prim > 0 )); then
  echo "     $failed_prim primitive(s) disagree with docs/memory-model.md MM-EXEC-9a"
  exit 1
fi

echo
echo "check-agent-policy: the standard library performs what it declares,"
echo "                    the set that performs anything is the one on file,"
echo "                    and the only rows the checker could not finish are"
echo "                    the higher-order ones it is told about by name"
