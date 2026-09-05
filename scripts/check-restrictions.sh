#!/usr/bin/env bash
# Assert that `;@axiom:restrict(...)` is a CHECK and never a
# transformation, that each restriction refuses what it says it
# refuses and nothing else, and that a compiler which stops answering
# the question fails here rather than passing in silence.
#
# The restriction tag turns analysis the checker already performs - the
# effect row, the call graph, the body's own expression tree - into a
# refusal (`docs/reference.md`, AXTAG Keys; `typecheck.ax`,
# `checkRestricts`). Six sections, each with the negative probe that
# proves the section can go red, because `CONTRIBUTING.md`'s rule is
# that a gate can only see what it actually looks at:
#
#   1. NO EMITTED BYTE MOVES. For every program in `tests/selfhost/`
#      that the compiler accepts and that declares no `extern`, a copy
#      is made with `;@axiom:restrict(no-foreign)` written above EVERY
#      top-level `fn` - a restriction every such program satisfies -
#      and the copy must `emit-llvm` byte-for-byte what the original
#      does, print the same `symbols --calls` rows once the
#      `#restrict=` meta the tag adds is dropped, and draw the same
#      diagnostics with one exception that is itself asserted: never
#      an AX3049 or AX3052, and an AX3051 ONLY on a declaration whose
#      own AXSYM row carries `#effects-incomplete` or
#      `#effects-overapprox`. The first run of this section found the
#      exception rather than assumed it - four of the six corpus files
#      `docs/reference.md` names as carrying the incompleteness
#      sentinel drew the warning, and nothing else did - which is the
#      compiler being right about a claim it cannot close, not a
#      change in what the program means. This is the strongest
#      available statement of "a restriction changes nothing about a
#      program that keeps it": it needs no golden, it covers a hundred
#      and sixty real programs, and it is why the default reading of
#      every restriction is a diagnostic and not an emission mode. The
#      probe alters one byte of one copy's body and requires the IR
#      comparison to notice.
#
#   2. THE FIXTURES ANSWER, AND THE CONTROLS ARE SILENT. Each of
#      `tests/diagnostics/371`-`379`, `383`, `393` and `394` must draw
#      the restriction code
#      its header promises, and no diagnostic of any code may name a
#      control declaration - `pureMath`, `delegates`, `native`,
#      `measures` and the rest are the controls that keep each rule
#      from being a blanket refusal (a callee that casts under
#      `no-cast`, a syscall under `no-foreign`, `Alloc,Mut` under
#      `no-io`). `check-diagnostics.sh` pins the same fixtures byte
#      for byte; this section exists so that section 4 has something
#      to watch go red that is not a golden comparison.
#
#   3. A PLANTED VIOLATION IS REFUSED. A clean program carrying every
#      restriction, satisfied, is written here; then seven copies, each
#      with one violation planted - a `println` under `no-io`, a
#      `vecNew` under `no-alloc`, a `cast` under `no-cast`, an `extern`
#      call under `no-foreign`, a self-call under `no-recursion`, a raw
#      `+` under `no-wrap`, a name that is not a restriction - and
#      each copy must draw exactly one restriction diagnostic, of the
#      code and on the declaration the plant names. The `no-cast`
#      plant additionally requires the span to cover the word `cast`
#      and not the declaration: the local rule reports where the fix
#      is.
#
#   4. THE COMPILER THAT STOPS ANSWERING IS CAUGHT. A second compiler
#      is built from a copy of `self_host/` in which `checkAxtags` no
#      longer calls `checkRestricts` - the single hook - and section 2
#      is run against it, and must FAIL. `check-tools-selfhost.sh`'s
#      header records the failure this half exists to prevent: point
#      the reference at the thing under test and every comparison
#      becomes a compiler against itself, "214 files swept, zero
#      differences, exit 0, and nothing tested".
#
#   5. THE MANIFEST. Every declaration in the tree carrying a
#      `restrict` tag, with the restrictions it claims and the verdict
#      the compiler gave - `ok`, `violated`, `unverifiable`, `unknown`,
#      or several - is derived from `symbols` (the `#restrict=` meta,
#      which is why `smTags` had to union a signature's tags with the
#      function's) and `check`, and compared against
#      `tests/agent/restrictions.allow`, kept the way
#      `tests/agent/stdlib-effects.allow` is: derived, checked in, and
#      blessed when the diff is what you meant. A restricted
#      declaration appearing, disappearing, or changing its verdict is
#      a line in a diff somebody reads. The probe adds one restricted
#      declaration in a file outside the tree and requires the derived
#      set to differ; a second check asks the file whether it is in C
#      collation order, for the locale reason `check-agent-policy.sh`
#      records.
#
#   6. NO-WRAP'S TWO EXEMPTIONS ARE NARROW. `no-wrap` matches an
#      operator's SPELLING, and two things wearing those spellings
#      cannot wrap: the three on `Float` operands, which lower to
#      `fadd`/`fsub`/`fmul`, and the `for` keyword's own counter bump,
#      which the parser writes beneath a guard that bounds it. Both
#      were refused until 2026-09-04 - the `for` one naming a `+` the
#      source does not contain, at a span covering the word `for` -
#      and neither refusal had a fix that could be taken. A program
#      using both must check OK; the probe builds a compiler with each
#      exemption's predicate scoped to a constant and requires BOTH
#      declarations to draw AX3049 again, which is what says each arm
#      does its own work rather than one covering for the other.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

gate_build_axc axc

failed=0
checks=0
ok()  { checks=$((checks + 1)); echo "ok   $*"; }
bad() { checks=$((checks + 1)); failed=$((failed + 1)); echo "FAIL $*"; }

# Only the AXDL lines: the trailing "compilation failed ..." / "OK" is
# CLI chrome.
axdl_only() { grep -E '^[EW] ' || true; }

# `restriction_lines <stderr>`: the three restriction codes, `E` and
# `W` both - promoting or demoting one must not hide it from a probe.
restriction_lines() {
  awk '($1 == "E" || $1 == "W") && ($2 == "AX3049" || $2 == "AX3051" || $2 == "AX3052")' "$1"
}

# `tag_every_fn <in> <out>`: `;@axiom:restrict(no-foreign)` above
# every top-level `fn` that has a BLANK LINE above it - the tag
# REPLACES the blank line, so the copy has exactly the original's line
# count and every AXSYM position, every diagnostic position, survives
# the comparison unchanged. (Inserting a line instead moved every row
# below it by one, and the first run of this section failed on
# `020-call.ax`'s `main` at 7:5 against 6:5 - a difference in the copy
# and not in the compiler.) A `fn` with no blank line above it is left
# untagged; a program in which no `fn` could be tagged is counted
# rather than swept, because its comparison would be a program against
# itself. Column 0 only: an `impl` member is indented, and this
# section's claim is about the programs as they are, not about every
# declaration shape the tag can reach (373-376 cover the shapes).
tag_every_fn() {
  awk 'NR == 1 { prev = $0; next }
       { if ($0 ~ /^\((pub )?fn / && prev == "") prev = ";@axiom:restrict(no-foreign)"
         print prev; prev = $0 }
       END { print prev }' "$1" > "$2"
}

echo "== 1. a satisfied restriction changes no emitted byte =="
# A shadow of `tests/selfhost/` in which every file is a symlink to
# the original, so an entry's `(import Sibling)` resolves exactly as
# it does in the tree; per program, its own link is replaced by the
# tagged copy and restored afterwards, so no other program ever sees
# a tagged sibling.
shadow="$work/ir/tree/tests/selfhost"
mkdir -p "$shadow" "$work/ir"
for sib in tests/selfhost/*.ax; do ln -s "$repo_root/$sib" "$shadow/$(basename "$sib")"; done
# Module resolution also searches `self_host/` and `stdlib/` relative
# to the working directory (`270-lex.ax` imports `lexer`), so the
# shadow root carries both, as `check-diagnostics.sh`'s work tree does.
ln -s "$repo_root/self_host" "$work/ir/tree/self_host"
ln -s "$repo_root/stdlib" "$work/ir/tree/stdlib"
swept=0; refused=0; unverifiable=0; swept_names=()
for f in tests/selfhost/*.ax; do
  base="$(basename "$f" .ax)"
  # Outside this section's claim, and counted so that a sweep that
  # skipped everything is visible below: a program declaring an
  # `extern` does not satisfy `no-foreign`; one the compiler refuses
  # has no IR; one with no `main` emits nothing to compare.
  if grep -qE '^\((pub )?extern ' "$f"; then refused=$((refused + 1)); continue; fi
  if ! "$axc" --diagnostic-format=ai check "$f" > /dev/null 2> "$work/ir/$base.orig.err"; then
    refused=$((refused + 1)); continue
  fi
  "$axc" --diagnostic-format=ai emit-llvm "$f" > "$work/ir/$base.orig.ll" 2>/dev/null || true
  if ! grep -q '^define .*@main' "$work/ir/$base.orig.ll"; then refused=$((refused + 1)); continue; fi
  "$axc" --diagnostic-format=ai symbols "$f" --calls > "$work/ir/$base.orig.sym" 2>/dev/null || true

  tag_every_fn "$f" "$work/ir/$base.tagged.ax"
  if cmp -s "$f" "$work/ir/$base.tagged.ax"; then refused=$((refused + 1)); continue; fi
  rm "$shadow/$base.ax"; cp "$work/ir/$base.tagged.ax" "$shadow/$base.ax"
  ( cd "$work/ir/tree" && "$axc" --diagnostic-format=ai emit-llvm "tests/selfhost/$base.ax" ) \
    > "$work/ir/$base.tagged.ll" 2>/dev/null || true
  ( cd "$work/ir/tree" && "$axc" --diagnostic-format=ai check "tests/selfhost/$base.ax" ) \
    > /dev/null 2> "$work/ir/$base.tagged.err" || true
  ( cd "$work/ir/tree" && "$axc" --diagnostic-format=ai symbols "tests/selfhost/$base.ax" --calls ) \
    > "$work/ir/$base.tagged.sym" 2>/dev/null || true
  rm "$shadow/$base.ax"; ln -s "$repo_root/$f" "$shadow/$base.ax"

  if ! cmp -s "$work/ir/$base.orig.ll" "$work/ir/$base.tagged.ll"; then
    bad "tests/selfhost/$base.ax: restricting every fn changed the emitted IR"
    # Written to a file and then read: `diff | head` under `pipefail`
    # kills this script with SIGPIPE the first time a diff is longer
    # than the head (check-gate-lib.sh records the same trap).
    diff "$work/ir/$base.orig.ll" "$work/ir/$base.tagged.ll" > "$work/ir/$base.ll.diff" || true
    head -6 "$work/ir/$base.ll.diff" | sed 's/^/     /'
    head -3 "$work/ir/$base.tagged.err" | cut -c1-160 | sed 's/^/     /'
    continue
  fi
  # The diagnostics, minus the restriction family - compared, and then
  # the family itself held to its own rule: a satisfied restriction
  # never REFUSES, and is unverifiable only where the row says so.
  if ! diff <(axdl_only < "$work/ir/$base.orig.err") \
            <(axdl_only < "$work/ir/$base.tagged.err" | awk '$2 != "AX3049" && $2 != "AX3051" && $2 != "AX3052"') > /dev/null; then
    bad "tests/selfhost/$base.ax: restricting every fn changed what check reports"
    head -3 "$work/ir/$base.tagged.err" | cut -c1-160 | sed 's/^/     /'
    continue
  fi
  if awk '$2 == "AX3049" || $2 == "AX3052"' "$work/ir/$base.tagged.err" | grep -q .; then
    bad "tests/selfhost/$base.ax: a satisfied no-foreign was REFUSED"
    awk '$2 == "AX3049" || $2 == "AX3052"' "$work/ir/$base.tagged.err" | head -2 | cut -c1-160 | sed 's/^/     /'
    continue
  fi
  # Every AX3051 names a declaration (first backticked name); each must
  # have a row that JUSTIFIES the word "unverifiable", and there are
  # three ways a row can (`docs/reference.md`, `restrict(...)`):
  #
  #   #effects-incomplete   the walk met a call it could not resolve,
  #                         so an absent effect is not evidence;
  #   #effects-overapprox   an effect is present only as POSSIBLE, so
  #                         its presence is not evidence;
  #   #effect-params=       the body CALLS one of its own parameters,
  #                         so the row is COMPLETE about this body and
  #                         answers the wrong question - what the call
  #                         performs is the caller's argument's.
  #
  # The third arm was added on 2026-08-31 with the reading itself, and
  # this loop is where its absence would have shown: before it, four
  # of this corpus's programs - `520-fn-values`, `972-polymorphic-
  # signature`, `997-let-box-value-escapes`, `999-placeholder-under-
  # arrow` - drew an AX3051 this check called unjustified, on rows
  # that carry `#effect-params=` and neither of the other two marks.
  # That is the check doing its job: a new reading has to be admitted
  # here explicitly, one marker at a time, rather than by widening the
  # test until nothing fails it.
  unverifiable_ok=1
  while read -r name; do
    [[ -z "$name" ]] && continue
    if ! awk -v n="$name" '$1 == "F" && $2 == n && (/#effects-incomplete/ || /#effects-overapprox/ || /#effect-params=/)' "$work/ir/$base.tagged.sym" | grep -q .; then
      bad "tests/selfhost/$base.ax: AX3051 on \`$name\`, whose row carries none of #effects-incomplete, #effects-overapprox or #effect-params="
      unverifiable_ok=0
    else
      unverifiable=$((unverifiable + 1))
    fi
  done < <(awk '$2 == "AX3051"' "$work/ir/$base.tagged.err" | sed -E 's/^[^"]*"`([^`]+)`.*/\1/')
  (( unverifiable_ok )) || continue
  # Stripped on BOTH sides. A declaration this file merely IMPORTS can
  # legitimately carry its own `#restrict=` (once adoption is real,
  # not zero) and that value is identical in `orig.sym` and
  # `tagged.sym` alike - neither run touches the declaring file.
  # Stripping only the tagged side erased it from one and not the
  # other and read the identical value as a change; a real stdlib
  # `#restrict=` on an imported symbol (`vecLen`, reached from a
  # program that merely `(import Vec)`s) turned this false the day
  # adoption stopped being zero. Symmetric stripping keeps this
  # section's actual claim - tagging every fn in THIS file changes no
  # row beyond its own `#restrict=` - true regardless of what
  # elsewhere in the tree already claims a restriction.
  if ! diff <(sed -E 's| #restrict=[^ ]+||' "$work/ir/$base.tagged.sym") \
            <(sed -E 's| #restrict=[^ ]+||' "$work/ir/$base.orig.sym") > /dev/null; then
    bad "tests/selfhost/$base.ax: restricting every fn changed an AXSYM row beyond #restrict="
    diff <(sed -E 's| #restrict=[^ ]+||' "$work/ir/$base.tagged.sym") \
         <(sed -E 's| #restrict=[^ ]+||' "$work/ir/$base.orig.sym") > "$work/ir/$base.sym.diff" || true
    head -4 "$work/ir/$base.sym.diff" | cut -c1-160 | sed 's/^/     /'
    continue
  fi
  if ! grep -q '#restrict=no-foreign' "$work/ir/$base.tagged.sym"; then
    bad "tests/selfhost/$base.ax: the tagged copy's AXSYM carries no #restrict= at all (the tag was not attached)"
    continue
  fi
  swept=$((swept + 1)); swept_names+=("$base")
done
if (( swept < 120 )); then
  bad "only $swept programs were swept ($refused skipped); the floor is 120"
else
  ok "$swept programs emit identical IR, diagnostics and AXSYM rows with every fn restricted ($refused skipped: refused, extern-bearing, no main, or no fn with a blank line above it)"
fi
# The exception must occur, or the rule about it was never exercised:
# `docs/reference.md` names six corpus files carrying the sentinel.
if (( unverifiable < 3 )); then
  bad "only $unverifiable AX3051 across the sweep; the corpus carries the incompleteness sentinel in six files, so a satisfied no-foreign should be unverifiable in several"
else
  ok "$unverifiable declarations drew AX3051, every one on a row carrying #effects-incomplete, #effects-overapprox or #effect-params=, and none was refused"
fi

# The probe: the comparison must be able to fail. One swept program's
# `main` body is moved into a second function and `main` made to
# answer 0, and the IR must differ from the original's.
probe_base=""
for b in "${swept_names[@]}"; do
  if grep -q '^(fn (main)' "tests/selfhost/$b.ax"; then probe_base="$b"; break; fi
done
if [[ -n "$probe_base" ]]; then
  perl -pe 's/^\(fn \(main\)/(fn (main) 0)\n(fn (mainProbe)/' "$work/ir/$probe_base.tagged.ax" > "$shadow/$probe_base.probe.ax"
  ( cd "$work/ir/tree" && "$axc" emit-llvm "tests/selfhost/$probe_base.probe.ax" ) > "$work/ir/$probe_base.probe.ll" 2>/dev/null || true
  rm -f "$shadow/$probe_base.probe.ax"
  if [[ -s "$work/ir/$probe_base.probe.ll" ]] && ! cmp -s "$work/ir/$probe_base.orig.ll" "$work/ir/$probe_base.probe.ll"; then
    ok "negative probe: a changed body in $probe_base is seen by the IR comparison"
  else
    bad "negative probe: a changed body in $probe_base still compared equal to the original IR, or emitted nothing"
  fi
else
  bad "negative probe: no swept program has a column-0 \`(fn (main)\` to alter"
fi

# A run directory shared by sections 2 and 5, mirroring
# `check-diagnostics.sh`'s: helper modules copied flat (a module name
# is its file stem), `stdlib/` and `self_host/` reachable, and each
# case COPIED in, so that a fixture's `(import Mod)` resolves as it
# does under that gate - 377 imports `RestrictLeaf` from `mods/`.
mkdir -p "$work/run"
cp "$repo_root"/tests/diagnostics/mods/*.ax "$work/run/" 2>/dev/null || true
ln -s "$repo_root/stdlib" "$work/run/stdlib"
ln -s "$repo_root/self_host" "$work/run/self_host"

echo
echo "== 2. the fixtures answer, and the controls are silent =="
# `<case> <codes expected, min count> <control names>`
fixture_expectations() {
  cat <<'EXP'
371-restrict-no-io       AX3049 2 pureMath allocates
372-restrict-no-alloc    AX3049 2 sums reads
373-restrict-no-cast     AX3049 3 delegates measures honest unwrap
374-restrict-no-foreign  AX3049 2 native local
375-restrict-unverifiable AX3051 2 clean
376-restrict-unknown-name AX3052 3 twice control
377-restrict-witness-path AX3049 6 quiet
378-restrict-no-cast-deep AX3049 5 deepClean shallow plain
379-restrict-no-recursion AX3049 4 deep looped d1 d2 d3 d4
383-restrict-no-wrap     AX3049 3 delegates compares honest
393-restrict-strict      AX3057 3 provable strictOnly lexStrict
394-restrict-no-wrap-exempt AX3049 3 counts iterates floats
EXP
}

# `fixtures_answer <compiler>`: 0 when every fixture draws its code at
# least the stated number of times and no control is named; 1
# otherwise. A FUNCTION, so section 4 can run the identical assertion
# against the ablated compiler.
fixtures_answer() {
  local axc_="$1" rc=0
  while read -r case code min controls; do
    [[ -z "$case" ]] && continue
    cp "$repo_root/tests/diagnostics/$case.ax" "$work/run/$case.ax"
    ( cd "$work/run" && "$axc_" --diagnostic-format=ai check "$case.ax" ) > /dev/null 2> "$work/$case.err" || true
    rm -f "$work/run/$case.ax"
    local got
    got="$(awk -v c="$code" '$2 == c' "$work/$case.err" | wc -l | tr -d ' ')"
    if (( got < min )); then
      echo "     $case: $got x $code, wanted at least $min"; rc=1
    fi
    for ctl in $controls; do
      if grep -F "\`$ctl\`" "$work/$case.err" > /dev/null; then
        echo "     $case: control \`$ctl\` drew a diagnostic"; rc=1
      fi
    done
  done < <(fixture_expectations)
  return $rc
}

if fixtures_answer "$axc"; then
  ok "371-379, 383, 393 draw their codes and every control is silent"
else
  bad "a restriction fixture did not answer as its header promises (above)"
fi

echo
echo "== 3. a planted violation is refused =="
mkdir -p "$work/plant"
cat > "$work/plant/clean.ax" <<'CLEAN'
(import IO)

(import Vec)

(import Err)

;@axiom:restrict(no-io)
(:: quietIo (-> Int Int))

(fn (quietIo n) (+ n 1))

;@axiom:restrict(no-alloc)
(:: quietAlloc (-> Int Int))

(fn (quietAlloc n) (* n 2))

;@axiom:restrict(no-cast)
(:: quietCast (-> Int Int))

(fn (quietCast n) (- n 3))

;@axiom:restrict(no-foreign)
(:: quietForeign (-> Int Int))

;@axiom:effect(io)
(fn (quietForeign n)
  {
    (println "native")
    n
  }
)

;@axiom:restrict(no-recursion)
(:: quietRec (-> Int Int))

(fn (quietRec n) (quietCast n))

;@axiom:restrict(no-wrap)
(:: quietWrap (-> Int Int))

(fn (quietWrap n) (unwrapOr (addChecked n 1) 0))

;@axiom:restrict(no-io,no-alloc,no-cast,no-foreign,no-recursion,no-wrap)
(:: quietAll (-> Int Int))

(fn (quietAll n) n)

(:: main Int)

;@axiom:effect(io)
(fn (main) (+ (quietIo 1) (+ (quietAlloc 2) (+ (quietCast 3) (+ (quietForeign 4) (+ (quietRec 5) (+ (quietWrap 7) (quietAll 6))))))))
CLEAN

( cd "$work/plant" && "$axc" --diagnostic-format=ai check clean.ax ) > "$work/plant/clean.out" 2> "$work/plant/clean.err" || true
if [[ "$(restriction_lines "$work/plant/clean.err" | wc -l | tr -d ' ')" == 0 && "$(cat "$work/plant/clean.out")" == "OK" ]]; then
  ok "the clean program, every restriction satisfied, checks OK with no restriction diagnostic"
else
  bad "the clean program drew a restriction diagnostic, or did not check OK"
  cat "$work/plant/clean.err" | head -5 | sed 's/^/     /'
fi

# `plant <name> <perl-expr> <code> <decl>`: one violation, one
# diagnostic, of <code>, naming <decl>, and nothing else from the
# family. `perl -pe` and not `sed`: two of the plants insert a line,
# and BSD `sed` does not write a newline from a replacement.
plant() {
  local name="$1" expr="$2" code="$3" decl="$4"
  perl -pe "$expr" "$work/plant/clean.ax" > "$work/plant/$name.ax"
  if cmp -s "$work/plant/clean.ax" "$work/plant/$name.ax"; then
    bad "plant $name: the sed expression changed nothing"; return
  fi
  ( cd "$work/plant" && "$axc" --diagnostic-format=ai check "$name.ax" ) > /dev/null 2> "$work/plant/$name.err" || true
  restriction_lines "$work/plant/$name.err" > "$work/plant/$name.hits"
  local n; n="$(wc -l < "$work/plant/$name.hits" | tr -d ' ')"
  if [[ "$n" != 1 ]]; then
    bad "plant $name: $n restriction diagnostics, wanted exactly 1"
    cat "$work/plant/$name.hits" | cut -c1-140 | sed 's/^/     /'; return
  fi
  if ! awk -v c="$code" '$2 == c' "$work/plant/$name.hits" | grep -q "\`$decl\`"; then
    bad "plant $name: the one diagnostic is not $code naming \`$decl\`"
    cut -c1-160 "$work/plant/$name.hits" | sed 's/^/     /'; return
  fi
  ok "plant $name: exactly one $code, on \`$decl\`"
}

plant no-io      's/^\(fn \(quietIo n\) \(\+ n 1\)\)$/;\@axiom:effect(io)\n(fn (quietIo n) { (println "io") (+ n 1) })/' AX3049 quietIo
plant no-alloc   's/^\(fn \(quietAlloc n\) \(\* n 2\)\)$/(fn (quietAlloc n) (let ((v vecNew)) { (vecPush v n) (* n 2) }))/' AX3049 quietAlloc
plant no-cast    's/^\(fn \(quietCast n\) \(- n 3\)\)$/(fn (quietCast n) (- (cast Int n) 3))/' AX3049 quietCast
plant no-foreign 's/^\(import Vec\)$/(import Vec)\n\n(pub extern "axiom_demo"\n  (add :: (-> Int Int Int) (symbol "axffi_add")))/; s/^    \(println "native"\)$/    (add n 1)/' AX3049 quietForeign
plant unknown    's/^;\@axiom:restrict\(no-cast\)$/;\@axiom:restrict(no-cast,no-fo)/' AX3052 quietCast
plant no-recursion 's/^\(fn \(quietRec n\) \(quietCast n\)\)$/(fn (quietRec n) (if (<= n 0) 0 (quietRec (- n 1))))/' AX3049 quietRec
plant no-wrap    's/^\(fn \(quietWrap n\) \(unwrapOr \(addChecked n 1\) 0\)\)$/(fn (quietWrap n) (+ n 1))/' AX3049 quietWrap

# The local rule's span: the `no-cast` plant's diagnostic must cover
# the word `cast` in the line it points at, not the declaration.
if [[ -f "$work/plant/no-cast.hits" ]]; then
  loc="$(awk '{print $3}' "$work/plant/no-cast.hits" | head -1)"
  line="${loc#*:}"; line="${line%%:*}"
  cols="${loc##*:}"; c1="${cols%-*}"; c2="${cols#*-}"
  src="$(sed -n "${line}p" "$work/plant/no-cast.ax")"
  covered="${src:$((c1 - 1)):$((c2 - c1))}"
  if [[ "$covered" == "cast" ]]; then
    ok "the no-cast plant is reported at the cast: span $loc covers \`cast\`"
  else
    bad "the no-cast plant's span $loc covers '$covered', not \`cast\`"
  fi
fi

echo
echo "== 4. a compiler that stops answering is caught =="
# The ablation is the single hook in `checkAxtags`; with it gone every
# `restrict` tag is metadata again, which is exactly the state before
# this feature existed. Built from a copy so the tree is untouched.
mkdir -p "$work/ablate"
cp -R "$repo_root/self_host" "$work/ablate/self_host"
hook='          (checkRestricts tc d own sig eff)'
if ! grep -qF "$hook" "$work/ablate/self_host/typecheck.ax"; then
  bad "the ablation target \`$hook\` is not in typecheck.ax - this probe no longer ablates anything"
else
  # The call line, at its indentation, so a mention in a comment is not
  # what gets replaced; `count == 1` is asserted so the ablation cannot
  # silently become two.
  python3 - "$work/ablate/self_host/typecheck.ax" "$hook" <<'PY'
import sys
p, hook = sys.argv[1], sys.argv[2]
s = open(p).read()
assert s.count(hook + '\n') == 1, s.count(hook + '\n')
open(p, 'w').write(s.replace(hook + '\n', '          0\n'))
PY
  if "$axiom" build --input "$work/ablate/self_host/main.ax" --output "$work/ablate/axc" > "$work/ablate/build.log" 2>&1; then
    if fixtures_answer "$work/ablate/axc" > "$work/ablate/answer.log" 2>&1; then
      bad "negative probe: a compiler with checkRestricts unhooked still passes section 2 (the section cannot fail)"
    else
      ok "negative probe: with checkRestricts unhooked, section 2 fails ($(grep -c 'wanted at least' "$work/ablate/answer.log" || true) fixtures stop answering)"
    fi
  else
    bad "negative probe: the ablated compiler did not build"
    head -5 "$work/ablate/build.log" | sed 's/^/     /'
  fi
fi

echo
echo "== 5. the manifest: every restricted declaration in the tree, and its verdict =="
allow="tests/agent/restrictions.allow"
mkdir -p "$work/manifest"

# `derive_manifest <file-list> <out>`: one line per restricted
# declaration, `name file restrictions verdict`, C-collated.
derive_manifest() {
  local list="$1" out="$2"
  : > "$out.raw"
  while read -r f; do
    [[ -z "$f" ]] && continue
    local base; base="$(basename "$f")"
    cp "$f" "$work/run/$base"
    ( cd "$work/run" && "$axc" --diagnostic-format=ai symbols "$base" ) > "$work/manifest/sym" 2>/dev/null || true
    ( cd "$work/run" && "$axc" --diagnostic-format=ai check "$base" ) > /dev/null 2> "$work/manifest/err" || true
    # `name restrictions` from the rows carrying the meta, anchored on
    # the field so a value cannot smuggle one in. `%20` is AXSYM's
    # escape of a blank the author wrote around a comma; the checker
    # trims it, and it is not part of any name. `$3` (the location)
    # must open with THIS file's own basename: `symbols` prints a row
    # for every declaration reached transitively, including a
    # restricted one this file merely `(import)`s (`vecLen`, read
    # from `stdlib/Vec.ax` by a program that imports `Vec`), and
    # without this filter that import misattributed the callee's
    # restriction to the importing file - a manifest row this file
    # never declared, once adoption was more than the fixtures.
    awk -v b="$base" '$1 == "F" && index($3, b ":") == 1 { for (i = 5; i <= NF; i++) if ($i ~ /^#restrict=/) { sub(/^#restrict=/, "", $i); gsub(/%20/, "", $i); print $2, $i } }' "$work/manifest/sym"       > "$work/manifest/rows"
    while read -r name rs; do
      [[ -z "$name" ]] && continue
      # The declaration a restriction diagnostic names: the first
      # backticked name, except the LOCAL forms, which lead with the
      # offending token and name the declaration second - "`cast` in
      # the body of `f`" and, since `no-wrap`, "`+` in the body of
      # `f`".
      #
      # The pattern is `[^`]+` and not `cast` because the narrower one
      # was already wrong: every `no-wrap` violation in the tree was
      # attributed to a declaration called `+`, `-` or `*`, which
      # matches nothing, so the manifest recorded `ok` for `wraps` and
      # `nested` in `383-restrict-no-wrap.ax` - two declarations this
      # compiler REFUSES. A derived file reporting less than the
      # compiler knows is the defect section 5 exists to catch in
      # others, and it was in section 5.
      local v=""
      local named
      named="$(awk -v n="$name" '
        ($2 == "AX3049" || $2 == "AX3051" || $2 == "AX3052" || $2 == "AX3057") {
          m = $0; sub(/^[^"]*"/, "", m)
          if (m ~ /^`[^`]+` in the body of `/) { sub(/^`[^`]+` in the body of `/, "", m) } else { sub(/^`/, "", m) }
          sub(/`.*/, "", m)
          if (m == n) print $2 }' "$work/manifest/err" | LC_ALL=C sort -u | tr '\n' ' ')"
      [[ "$named" == *AX3049* ]] && v="${v}violated,"
      [[ "$named" == *AX3051* ]] && v="${v}unverifiable,"
      [[ "$named" == *AX3052* ]] && v="${v}unknown,"
      # AX3057 is a REFUSAL, and without this row the manifest read
      # `ok` for a declaration the compiler rejects - a derived file
      # reporting less than the compiler knows, which is the defect
      # this gate exists to catch in others.
      [[ "$named" == *AX3057* ]] && v="${v}unproven,"
      [[ -z "$v" ]] && v="ok,"
      printf '%s %s %s %s\n' "$name" "${f#$repo_root/}" "$rs" "${v%,}" >> "$out.raw"
    done < "$work/manifest/rows"
    rm -f "$work/run/$base"
  done < "$list"
  LC_ALL=C sort -u "$out.raw" > "$out"
}

# Every tracked `.ax` in the tree carrying a restriction tag - the
# whole tree, not a directory list, so a restricted declaration is
# covered the day it lands. TRACKED, through `git ls-files`, because
# a `grep -r .` also reads whatever else sits under the checkout: on
# 2026-08-29 the agent worktrees under `.claude/worktrees/` each
# carried the six fixtures, and the derived manifest grew from 43 rows
# to 270, all of them the same declarations seven times over.
( cd "$repo_root" && git ls-files -z -- '*.ax' \
    | xargs -0 grep -lE '^[[:space:]]*;@axiom:restrict' 2>/dev/null \
    | LC_ALL=C sort ) > "$work/manifest/files"
nfiles=$(wc -l < "$work/manifest/files" | tr -d ' ')
if (( nfiles < 6 )); then
  bad "only $nfiles files in the tree carry a restrict tag; the fixtures alone are more than that (the sweep found nothing)"
else
  ok "$nfiles files in the tree carry a restrict tag"
fi
sed "s|^|$repo_root/|" "$work/manifest/files" > "$work/manifest/files.abs"
derive_manifest "$work/manifest/files.abs" "$work/manifest/derived"

if [[ "${AXIOM_BLESS:-0}" == 1 ]]; then
  cp "$work/manifest/derived" "$repo_root/$allow"
  echo "blessed $allow"
fi
if [[ ! -f "$repo_root/$allow" ]]; then
  bad "$allow is missing; run with AXIOM_BLESS=1"
elif ! diff -u "$repo_root/$allow" "$work/manifest/derived" > "$work/manifest/diff"; then
  bad "the derived manifest differs from $allow"
  head -40 "$work/manifest/diff" | sed 's/^/     /'
  echo '     a + line is a restricted declaration that appeared or changed'
  echo '     its verdict; a - line is one that vanished or stopped being'
  echo '     checked. Bless with AXIOM_BLESS=1 when the delta is what you meant.'
else
  ok "$(wc -l < "$repo_root/$allow" | tr -d ' ') restricted declarations, each with the verdict $allow says"
fi
if [[ -f "$repo_root/$allow" ]]; then
  if LC_ALL=C sort -c "$repo_root/$allow" 2>/dev/null; then
    ok "$allow is in C collation order, so it reads the same on every runner"
  else
    bad "$allow is not in C collation order"
  fi
  # Every verdict word is one this gate writes; a manifest edited by
  # hand into a word the derivation never produces would otherwise
  # compare equal to nothing and fail nowhere.
  if awk '{ split($4, vs, ","); for (k in vs) if (vs[k] != "ok" && vs[k] != "violated" && vs[k] != "unverifiable" && vs[k] != "unknown" && vs[k] != "unproven") exit 1 }' "$repo_root/$allow"; then
    ok "every verdict in $allow is one of ok, violated, unverifiable, unknown, unproven"
  else
    bad "$allow carries a verdict word this gate never writes"
  fi
  if ! grep -q ' violated' "$repo_root/$allow" || ! grep -q ' unverifiable' "$repo_root/$allow" || ! grep -q ' ok$' "$repo_root/$allow"; then
    bad "$allow does not carry all three of violated, unverifiable and ok - the fixtures produce each, so a derivation missing one is not reading the compiler"
  else
    ok "$allow carries violated, unverifiable and ok verdicts (the fixtures produce each)"
  fi
fi

# The probe: a restricted declaration in a file outside the tree,
# added to the sweep, must change the derived set.
printf ';@axiom:restrict(no-io)\n(:: probeRestricted (-> Int Int))\n\n(fn (probeRestricted n) n)\n\n(:: main Int)\n\n(fn (main) (probeRestricted 1))\n' > "$work/manifest/zz-probe.ax"
{ cat "$work/manifest/files.abs"; echo "$work/manifest/zz-probe.ax"; } > "$work/manifest/files.probe"
derive_manifest "$work/manifest/files.probe" "$work/manifest/derived.probe"
if cmp -s "$work/manifest/derived" "$work/manifest/derived.probe"; then
  bad "negative probe: a restricted declaration added to the sweep left the derived manifest unchanged"
else
  if grep -q '^probeRestricted .* no-io ok$' "$work/manifest/derived.probe"; then
    ok "negative probe: a restricted declaration added to the sweep appears in the derived manifest, verdict ok"
  else
    bad "negative probe: the added declaration appears with the wrong row: $(grep probeRestricted "$work/manifest/derived.probe" || echo '(absent)')"
  fi
fi

echo
echo "== 6. no-wrap's two exemptions are narrow, and each is load-bearing =="
# `no-wrap` matches a SPELLING, and two things wearing those spellings
# cannot wrap: the three operators on `Float` operands, which lower to
# `fadd`/`fsub`/`fmul`, and the `for` keyword's own counter bump, which
# the parser writes beneath a `(< for$i for$n)` guard that bounds it
# below `INT_MAX`. Both were refused until 2026-09-04, each with a fix
# that could not be taken: a loop counter cannot be a `Result`, and
# `addChecked` is `(-> Int Int (Result Int Error))`, which does not
# typecheck against a `Float`. The `for` one additionally named a `+`
# the source does not contain, at a span covering the word `for`.
#
# An exemption is a SILENCE, and a silence is only a claim when
# something can make it speak - so this section is two halves. The
# program below must check OK here; and against a compiler whose two
# exemption arms have been scoped to constants it must draw AX3049 on
# BOTH declarations, which is what says each arm is separately doing
# work rather than one covering for the other.
#
# `tests/diagnostics/394-restrict-no-wrap-exempt.ax` holds the same
# pair beside the cases that keep them narrow - a hand-written loop
# counter, arithmetic in a loop's body, and a `Float` `+` nested inside
# an `Int` one - and section 2 asserts the three that must still fire.
mkdir -p "$work/exempt"
cat > "$work/exempt/exempt.ax" <<'EXEMPT'
(import Err)

(import Vec)

;@axiom:restrict(no-wrap)
(:: loops (-> (Vec Int) Int))

(fn (loops xs)
  (let ((mut acc 0))
    {
      (for i 0 3
        (set acc (unwrapOr (addChecked acc i) 0)))
      (for x xs
        (set acc (unwrapOr (addChecked acc x) 0)))
      acc
    }
  )
)

;@axiom:restrict(no-wrap)
(:: floaty (-> Float Float Float))

(fn (floaty a b) (* (+ a b) (- a b)))

(:: main Int)

(fn (main) (+ (loops (vecPush vecNew 4)) (__floatToInt (floaty 2.0 1.0))))
EXEMPT

( cd "$work/exempt" && "$axc" --diagnostic-format=ai check exempt.ax ) > "$work/exempt/out" 2> "$work/exempt/err" || true
if [[ "$(restriction_lines "$work/exempt/err" | wc -l | tr -d ' ')" == 0 && "$(cat "$work/exempt/out")" == "OK" ]]; then
  ok "a \`for\` of either shape and \`Float\` arithmetic satisfy no-wrap: no restriction diagnostic, checks OK"
else
  bad "the exempt program drew a restriction diagnostic, or did not check OK"
  cut -c1-140 "$work/exempt/err" | head -5 | sed 's/^/     /'
fi

# The negative: both arms scoped to a constant, so neither exemption
# can fire. Built from a copy; the tree is untouched.
mkdir -p "$work/exabl"
cp -R "$repo_root/self_host" "$work/exabl/self_host"
python3 - "$work/exabl/self_host/typecheck.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
# Each arm's PREDICATE becomes a constant that is never 1, so its
# `then` - the skip - is unreachable and every `+`, `-` and `*` the
# scan found is reported again. The count is asserted so the ablation
# cannot silently become two arms, or none.
arms = ['                            (if (== (isForBump e) 1)\n',
        '        (if (== (tcFloatOpIn tc (spineHead w)) 1)\n']
for a in arms:
    assert s.count(a) == 1, (a.strip(), s.count(a))
    indent = a[:len(a) - len(a.lstrip())]
    s = s.replace(a, indent + '(if (== 2 1)\n', 1)
open(p, 'w').write(s)
PY
if grep -q '(if (== 2 1)' "$work/exabl/self_host/typecheck.ax"; then
  if "$axiom" build --input "$work/exabl/self_host/main.ax" --output "$work/exabl/axc" > "$work/exabl/build.log" 2>&1; then
    ( cd "$work/exempt" && "$work/exabl/axc" --diagnostic-format=ai check exempt.ax ) > /dev/null 2> "$work/exempt/abl.err" || true
    restriction_lines "$work/exempt/abl.err" > "$work/exempt/abl.hits"
    got_for=0; got_flt=0
    grep -q '`loops`' "$work/exempt/abl.hits" && got_for=1
    grep -q '`floaty`' "$work/exempt/abl.hits" && got_flt=1
    if (( got_for == 1 && got_flt == 1 )); then
      ok "negative probe: with both exemption arms scoped to a constant, \`loops\` and \`floaty\` each draw AX3049 again ($(wc -l < "$work/exempt/abl.hits" | tr -d ' ') rows)"
    else
      bad "negative probe: the ablated compiler reported for=$got_for float=$got_flt - an exemption that fires nowhere is a check that cannot fail"
      cut -c1-140 "$work/exempt/abl.hits" | sed 's/^/     /'
    fi
  else
    bad "negative probe: the exemption-ablated compiler did not build"
    head -5 "$work/exabl/build.log" | sed 's/^/     /'
  fi
else
  bad "the exemption ablation rewrote nothing - the arms it targets are no longer in typecheck.ax"
fi

echo
if (( failed > 0 )); then
  echo "check-restrictions: $failed of $checks checks failed"
  exit 1
fi
echo "check-restrictions: $checks checks - a restriction changes no emitted"
echo "                    byte, refuses exactly what it names with the path,"
echo "                    a compiler that stops asking is caught, and every"
echo "                    restricted declaration in the tree is on the manifest"
