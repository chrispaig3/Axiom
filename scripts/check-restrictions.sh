#!/usr/bin/env bash
# Assert that `;@axiom:restrict(...)` is a CHECK and never a
# transformation, that each restriction refuses what it says it
# refuses and nothing else, and that a compiler which stops answering
# the question fails here rather than passing in silence.
#
# The restriction tag turns analysis the checker already performs - the
# effect row, the call graph, the body's own expression tree - into a
# refusal (`docs/reference.md`, AXTAG Keys; `typecheck.ax`,
# `checkRestricts`). Four sections, each with the negative probe that
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
#      `tests/diagnostics/371`-`376` must draw the restriction code
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
#      restriction, satisfied, is written here; then five copies, each
#      with one violation planted - a `println` under `no-io`, a
#      `vecNew` under `no-alloc`, a `cast` under `no-cast`, an `extern`
#      call under `no-foreign`, a name that is not a restriction - and
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
# What this gate does NOT assert, and where it is asserted instead:
# which declarations in the tree carry a restriction and what each was
# answered - that is a manifest (`tests/agent/restrictions.allow`),
# kept the way `tests/agent/stdlib-effects.allow` is, and it belongs to
# the commit that renders the witness path, because the manifest's
# verdict column is what that path is for.

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
  # have a row marked incomplete or over-approximated.
  unverifiable_ok=1
  while read -r name; do
    [[ -z "$name" ]] && continue
    if ! awk -v n="$name" '$1 == "F" && $2 == n && (/#effects-incomplete/ || /#effects-overapprox/)' "$work/ir/$base.tagged.sym" | grep -q .; then
      bad "tests/selfhost/$base.ax: AX3051 on \`$name\`, whose row is neither incomplete nor over-approximated"
      unverifiable_ok=0
    else
      unverifiable=$((unverifiable + 1))
    fi
  done < <(awk '$2 == "AX3051"' "$work/ir/$base.tagged.err" | sed -E 's/^[^"]*"`([^`]+)`.*/\1/')
  (( unverifiable_ok )) || continue
  if ! diff <(sed -E 's| #restrict=[^ ]+||' "$work/ir/$base.tagged.sym") "$work/ir/$base.orig.sym" > /dev/null; then
    bad "tests/selfhost/$base.ax: restricting every fn changed an AXSYM row beyond #restrict="
    diff <(sed -E 's| #restrict=[^ ]+||' "$work/ir/$base.tagged.sym") "$work/ir/$base.orig.sym" > "$work/ir/$base.sym.diff" || true
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
  ok "$unverifiable declarations drew AX3051, every one on a row marked incomplete or over-approximated, and none was refused"
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
    local f="tests/diagnostics/$case.ax"
    ( cd "$work" && "$axc_" --diagnostic-format=ai check "$repo_root/$f" ) > /dev/null 2> "$work/$case.err" || true
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
  ok "371-376 draw their codes and every control is silent"
else
  bad "a restriction fixture did not answer as its header promises (above)"
fi

echo
echo "== 3. a planted violation is refused =="
mkdir -p "$work/plant"
cat > "$work/plant/clean.ax" <<'CLEAN'
(import IO)

(import Vec)

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

;@axiom:restrict(no-io,no-alloc,no-cast,no-foreign)
(:: quietAll (-> Int Int))

(fn (quietAll n) n)

(:: main Int)

;@axiom:effect(io)
(fn (main) (+ (quietIo 1) (+ (quietAlloc 2) (+ (quietCast 3) (+ (quietForeign 4) (quietAll 5))))))
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
      ok "negative probe: with checkRestricts unhooked, section 2 fails ($(grep -c 'wanted at least' "$work/ablate/answer.log") fixtures stop answering)"
    fi
  else
    bad "negative probe: the ablated compiler did not build"
    head -5 "$work/ablate/build.log" | sed 's/^/     /'
  fi
fi

echo
if (( failed > 0 )); then
  echo "check-restrictions: $failed of $checks checks failed"
  exit 1
fi
echo "check-restrictions: $checks checks - a restriction changes no emitted"
echo "                    byte, refuses exactly what it names, and a compiler"
echo "                    that stops asking is caught"
