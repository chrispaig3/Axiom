#!/usr/bin/env bash
# THE MID-LEVEL IR: WHAT IT PRINTS, WHAT IT MEANS, AND HOW MUCH OF
# THE TREE GOES THROUGH IT.
#
# `self_host/mir.ax` is an IR between the checked AST and
# `codegen.ax`: a representation, a lowering, a printer and a
# verifier. `self_host/mireval.ax` is a reference evaluator over it.
# `codegen.ax` EMITS FROM the IR for one measured subset of functions
# (slice 2, §6); the evaluator is still test-only, because it is what
# §4 compares the compiler against.
#
# THE HOLLOW VERSION OF THIS GATE, which is what every assertion
# below is shaped against: compile the fixtures, print their IR,
# compare against the checked-in goldens, exit 0. That version
# passes with a lowering that means nothing at all - the goldens are
# whatever the lowering last printed, and `AXIOM_BLESS=1` here
# rewrites them. A printer gate pins the FORM of the IR and says
# nothing about its MEANING.
#
# So the anchor is §4, a differential the goldens cannot satisfy:
#
#   for each fixture, the REAL COMPILER builds and runs it, the
#   EVALUATOR runs the lowered IR of the same file, and the two
#   stdouts must be byte-identical.
#
# The reference there is the 97,680 lines of compiler this change did
# not touch - `cat self_host/*.ax | wc -l` less `mir.ax` and
# `mireval.ax`, which nothing in that compiler imports. A lowering rule that quietly means something other than the
# source it came from fails §4 with §2's goldens freshly blessed and
# every other check green - and that is drilled rather than asserted:
# ABLATION 1 below is exactly such a rule.
#
# THE SECTIONS.
#
#   1. THE DRIVER BUILDS. `tests/mir/mirtool.ax` imports `mir`,
#      `mireval` and the whole frontend, and is compiled by the
#      compiler under test. `mir` is inside `self_host/main.ax`'s
#      import graph now and would be noticed breaking; `mireval` is
#      not, and this is the only thing that would.
#
#   2. THE PRINTER, against `tests/mir/NAME.mir`, byte for byte. The
#      regenerable half, and it is here for the reason a golden is
#      ever here: it is the only check that sees the TEXT, which is
#      the contract the `.mir` tooling reads.
#
#   3. THE VERIFIER IS SILENT on every fixture. `mirVerify` checks
#      block identity, exactly one terminator per block, single
#      assignment, every register defined before use, every branch
#      target real, block-argument arity, and DOMINANCE. Silence is
#      the passing answer, which is the shape most easily faked - so
#      ABLATION 2 breaks the IR and requires it to speak, and
#      requires it to stay silent about the one fixture the break
#      does not reach.
#
#   4. THE DIFFERENTIAL. Described above.
#
#   5. POSITIVE CONTROLS, so §4 cannot pass on two empty files.
#      Every fixture must print exactly 20 non-empty lines, and the
#      outputs must be as many DISTINCT files as there are fixtures
#      - a suite that all printed the same twenty lines would
#      satisfy §4 against a lowering that ignored its input.
#      One fixture, `090-callargs`, is there for a hole the other
#      eight left: every one of them calls a ONE-argument function,
#      so a lowering that reversed a call's argument list, or an
#      evaluator that bound the callee's parameters backwards,
#      would print the same lines on both sides of §4 and match
#      its golden.
#
#   6. THE COMPILER EMITS FROM THE IR. This section used to assert
#      the opposite - that nothing imported `mir`, so `emit-llvm`
#      could not have moved. `codegen.ax` imports it now, and
#      `mirEmitOrWalk` emits the single-block arithmetic subset FROM
#      the IR. The claim that nothing moved is therefore made where
#      it can still be checked: the routing has an OFF switch, and
#      `AXIOM_MIR_EMIT=0` against the default must be byte-identical
#      over `self_host/main.ax`, every stdlib module and every
#      `tests/selfhost` and `tests/stdlib` program.
#
#      With a FLOOR on how many functions took the IR path, printed
#      every run, because a routing that fell back to the walk for
#      everything answers "identical" too. The count is read off the
#      emitted text (`AXIOM_MIR_EMIT=mark`), and stripping the marks
#      must reproduce the unmarked emission - so it is a measurement
#      of that text and not a report about it. ABLATION 3 breaks one
#      emission rule and requires the comparison to go red.
#
#   6b. THE COVERAGE FLOOR. The lowering handles a SUBSET, and
#      refuses anything else outright, so a rule that narrowed itself
#      to keep §4 green would leave every other check passing. This
#      lowers every module in `self_host/` and `stdlib/` and requires
#      the count not to fall; it PRINTS the live number, so drift is
#      visible long before it is a failure. It also requires the
#      count to be a strict subset of the corpus, because "everything
#      lowered" would mean the counter, not the lowering, is what
#      changed.
#
#   7. THE OPERATOR TABLE, against `codegen.ax`'s. `mir.ax` cannot
#      import `codegen.ax` - the arrow runs the other way now, and a
#      cycle is what the two tables exist to avoid - so it carries
#      its own copy of `binopToLLVM` + `cmpToLLVM`.
#      `mirtool optable` is the one place in the tree that imports
#      both, and all eleven operators must agree. The twelfth row
#      must DISAGREE: `codegen.ax` answers "add" for a name it never
#      expects to be handed, and `mir.ax` answers "", which is what
#      makes the lowering refuse rather than emit a wrong opcode.
#
#   8. THE ABLATIONS, each in a shadow tree with the driver - or, for
#      the third, the whole compiler - rebuilt from it, and each
#      chosen so that they are ORTHOGONAL: each must turn its own
#      checks red and leave the others' green, because two ablations
#      that fire the same check are one ablation written twice.
#
#      ABLATION 1 swaps a binary operator's operands in
#      `mLowerApp`. The IR stays well formed - so §3 must stay
#      SILENT - and its meaning changes, so §2 and §4 must go red.
#      Measured on 010-arith: the first line goes from 25 to 2.
#
#      ABLATION 2 drops every `br` terminator in `mlcTerm`. Every
#      fixture whose golden contains a `condbr` must then be reported
#      as `has 0 terminators, want exactly 1`, and every fixture
#      whose golden does not must stay SILENT - a verifier that
#      shouted about everything would pass the first half and fail
#      the second. Which fixtures are which is read off the goldens
#      rather than listed here.
#
#      ABLATION 3 removes the CONSTANT FOLD from `mirEmitInsts` in
#      `codegen.ax` and rebuilds the compiler from the shadow tree.
#      §6's byte comparison must then go red - and, in the same
#      breath, the ablated compiler must still emit the reference
#      text with the routing OFF, or the red would be about something
#      other than the IR path.
#
# AXIOM_BLESS=1 rewrites the §2 goldens and nothing else. It cannot
# write `self_host/mir.ax`, the fixtures, `codegen.ax` or the corpus,
# which is why §3 to §9 survive a bless.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $1"; checks=$((checks + 1)); }
bad() { echo "FAIL $1"; checks=$((checks + 1)); failed=$((failed + 1)); }

# How many values each fixture's `probe` is asked for. The fixtures'
# own `emit` counts to the same number; if the two ever disagreed §5
# would report the line counts before §4 compared the bytes.
PROBES=20

# ---------------------------------------------------------------
echo "--- 1. the driver, and the two modules it imports ---"
# ---------------------------------------------------------------
# A `while read` rather than `mapfile`: the macOS runner's bash is
# 3.2, which has neither `mapfile` nor `readarray`.
fixtures=()
while IFS= read -r line; do
  fixtures+=("$line")
done < <(ls tests/mir/*.ax | grep -v '/mirtool\.ax$' | sort)
n_fix="${#fixtures[@]}"
if (( n_fix >= 9 )); then
  ok "tests/mir/ holds $n_fix fixtures"
else
  bad "tests/mir/ holds $n_fix fixtures; this gate expects at least 9"
fi

tool="$work/mirtool"
if "$axc" build --input tests/mir/mirtool.ax --output "$tool" > "$work/tool.log" 2>&1; then
  ok "tests/mir/mirtool.ax builds against self_host/mir.ax and self_host/mireval.ax"
else
  bad "tests/mir/mirtool.ax would not build - the IR modules do not compile"
  sed 's/^/     /' "$work/tool.log" | head -20
  echo
  echo "check-mir: $failed of $checks checks failed"
  exit 1
fi

# ---------------------------------------------------------------
echo
echo "--- 2. the printer, against tests/mir/NAME.mir ---"
# ---------------------------------------------------------------
for f in "${fixtures[@]}"; do
  n="$(basename "$f" .ax)"
  golden="tests/mir/$n.mir"
  got="$work/$n.mir"
  if ! "$tool" lower "$f" > "$got" 2> "$work/$n.lower.err"; then
    bad "$n: mirtool lower exited nonzero"
    sed 's/^/     /' "$work/$n.lower.err" | head -5
    continue
  fi
  if [[ -n "${AXIOM_BLESS:-}" ]]; then
    cp "$got" "$golden"
    echo "     blessed $golden"
  fi
  if [[ ! -f "$golden" ]]; then
    bad "$n: no golden at $golden"
  elif cmp -s "$got" "$golden"; then
    ok "$n: the printed IR equals $golden"
  else
    bad "$n: the printed IR differs from $golden"
    diff "$golden" "$got" | head -12 | sed 's/^/     /'
  fi

  # The fixture convention, checked rather than assumed: every
  # function named probe* is in the subset and lowers, and `emit` is
  # not and does not. The second half is what keeps the refusal path
  # live - a lowering that lowered EVERYTHING would be a lowering
  # that had stopped refusing, and no golden would say so.
  if grep -q '^fn probe(' "$got"; then
    ok "$n: probe lowered"
  else
    bad "$n: probe did not lower"
  fi
  if grep -q '^; not lowered: probe' "$got"; then
    bad "$n: a probe* function refused - the fixture has left the subset"
  else
    ok "$n: no probe* function refused"
  fi
  if grep -qx '; not lowered: emit' "$got"; then
    ok "$n: emit refused, as an IO function must"
  else
    bad "$n: emit did not refuse - the lowering is no longer refusing anything"
  fi
done

# ---------------------------------------------------------------
echo
echo "--- 3. the verifier is silent on every fixture ---"
# ---------------------------------------------------------------
for f in "${fixtures[@]}"; do
  n="$(basename "$f" .ax)"
  "$tool" verify "$f" > "$work/$n.verify" 2>&1
  st=$?
  if (( st == 0 )) && [[ ! -s "$work/$n.verify" ]]; then
    ok "$n: mirVerify reports nothing"
  else
    bad "$n: mirVerify complained (exit $st)"
    sed 's/^/     /' "$work/$n.verify" | head -10
  fi
done

# ---------------------------------------------------------------
echo
echo "--- 4. the differential: the native run against the IR run ---"
# ---------------------------------------------------------------
for f in "${fixtures[@]}"; do
  n="$(basename "$f" .ax)"
  if ! "$axc" build --input "$f" --output "$work/$n.bin" > "$work/$n.build" 2>&1; then
    bad "$n: the fixture would not compile natively"
    sed 's/^/     /' "$work/$n.build" | head -10
    continue
  fi
  # A TRAPPING FIXTURE EXITS NONZERO ON PURPOSE, so the status is
  # compared rather than refused. Refusing it - which this did - meant
  # a fixture whose whole point is the trap failed here with a message
  # about the wrong thing.
  #
  # THREE equalities, not two. `NAME.exit` states the status the
  # fixture is supposed to reach, and native and evaluator are each
  # checked against IT as well as against each other: two sides alone
  # would agree happily if both drifted together, which is the shape
  # this repository refuses elsewhere.
  want_exit=0
  [[ -f "${f%.ax}.exit" ]] && want_exit="$(tr -d ' \n' < "${f%.ax}.exit")"
  "$work/$n.bin" > "$work/$n.native" 2>"$work/$n.native.err"; nst=$?
  "$tool" run "$f" "$PROBES" > "$work/$n.evald" 2>"$work/$n.evald.err"; est=$?
  if [[ "$nst" != "$want_exit" ]]; then
    bad "$n: the native run exited $nst, and ${n}.exit says $want_exit"
    sed 's/^/     /' "$work/$n.native.err" | head -5
    continue
  fi
  if [[ "$est" != "$want_exit" ]]; then
    bad "$n: the IR evaluator exited $est, and ${n}.exit says $want_exit"
    sed 's/^/     /' "$work/$n.evald.err" | head -5
    continue
  fi
  if cmp -s "$work/$n.native" "$work/$n.evald"; then
    ok "$n: the IR evaluates to what the compiled program prints, and both exit $nst"
  else
    bad "$n: the IR and the compiled program disagree"
    diff "$work/$n.native" "$work/$n.evald" | head -10 | sed 's/^/     /'
  fi
done

# ---------------------------------------------------------------
echo
echo "--- 5. positive controls: §4 compared something ---"
# ---------------------------------------------------------------
short=""
blank=""
for f in "${fixtures[@]}"; do
  n="$(basename "$f" .ax)"
  [[ -f "$work/$n.native" ]] || { short="$short $n(missing)"; continue; }
  lines="$(wc -l < "$work/$n.native" | tr -d ' ')"
  # A fixture that traps stops early on purpose, and says how early in
  # `NAME.lines`; everything else prints the bank's $PROBES.
  want_lines="$PROBES"
  [[ -f "${f%.ax}.lines" ]] && want_lines="$(tr -d ' \n' < "${f%.ax}.lines")"
  [[ "$lines" == "$want_lines" ]] || short="$short $n($lines want $want_lines)"
  grep -q '^$' "$work/$n.native" && blank="$blank $n"
done
if [[ -z "$short" ]]; then
  ok "every fixture printed the number of lines it declares"
else
  bad "these fixtures printed an unexpected number of lines:$short"
fi
if [[ -z "$blank" ]]; then
  ok "no fixture printed an empty line"
else
  bad "these fixtures printed an empty line:$blank"
fi

# Fixtures that all print the same twenty lines would satisfy
# §4 against a lowering that ignored its input entirely.
n_distinct="$(for f in "${fixtures[@]}"; do
    n="$(basename "$f" .ax)"
    [[ -f "$work/$n.native" ]] && shasum -a 256 < "$work/$n.native"
  done | sort -u | wc -l | tr -d ' ')"
if [[ "$n_distinct" == "$n_fix" ]]; then
  ok "the $n_fix fixtures print $n_distinct distinct outputs"
else
  bad "the $n_fix fixtures print only $n_distinct distinct outputs - some pair proves nothing"
fi

# ---------------------------------------------------------------
echo
echo "--- 6. the compiler emits from the IR, and how much of it ---"
# ---------------------------------------------------------------
# THE ASSERTION THAT USED TO BE HERE said that no module imported
# `mir`, and that `axiom emit-llvm self_host/main.ax` was identical
# with `mir.ax` deleted. Slice 2 deletes it on purpose: `codegen.ax`
# imports `mir` now, and `mirEmitOrWalk` emits a measured subset of
# functions FROM the IR rather than from the AST walk.
#
# What replaces it is the same claim, made where it can still be
# checked. The routing has an OFF switch - `AXIOM_MIR_EMIT=0` - so
# the comparison is ONE compiler against ITSELF over ONE tree, which
# is what isolates the routing from everything else the import
# brought with it. Byte for byte, on the largest Axiom program there
# is and on 325 smaller ones.
#
# Then a FLOOR, printed every run, because "identical" is also what a
# routing that had fallen back to zero functions would answer, and
# every other check here would still pass - which is this
# repository's most common defect. The count is read off the EMITTED
# TEXT rather than claimed: `AXIOM_MIR_EMIT=mark` writes one
# `  ; mir` comment inside each function the IR emitted, and
# stripping those comments back out must reproduce the unmarked
# emission exactly. So the number cannot be a report about a path
# nothing took, and the marks cannot be moving anything themselves.
if grep -q '^(import mir)$' self_host/codegen.ax; then
  ok "codegen.ax imports mir - the seam is live"
else
  bad "codegen.ax does not import mir; slice 2's routing is not wired in"
fi
if grep -q 'mirEmitOrWalk' self_host/codegen.ax; then
  ok "emitFnDef routes through mirEmitOrWalk"
else
  bad "codegen.ax has no mirEmitOrWalk - the import is there and the routing is not"
fi
# THE IMPORTER SET IS EXACT, not merely non-empty. Slice 2 replaced
# "nothing imports mir" with "these things do", and an exact set is the
# only version of that which still says something: a third consumer
# arriving silently is what a `grep -q` would miss, and each consumer
# is a place the IR's shape becomes load-bearing.
#
#   codegen.ax   emits from it (slice 2)
#   axir.ax      projects it into the `.axir` record file
#   mireval.ax   evaluates it, and is §4's independent reference
want_mir="axir.ax codegen.ax mireval.ax"
got_mir="$(grep -l -E '^\(import mir\)$' self_host/*.ax | xargs -n1 basename | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
if [[ "$got_mir" == "$want_mir" ]]; then
  ok "exactly three modules import mir: $got_mir"
else
  bad "the importers of mir have moved: want [$want_mir], got [$got_mir]"
fi

# `mireval` is the reference evaluator and is still test-only: it is
# what §4 compares the compiler against, and a compiler that imported
# its own reference would be comparing one walk with itself.
ev_importers="$(grep -l -E '^\(import mireval\)' self_host/*.ax | grep -v '^self_host/mireval\.ax$' | tr '\n' ' ')"
if [[ -z "$ev_importers" ]]; then
  ok "no compiler module imports mireval - §4's reference is still independent"
else
  bad "these modules import the evaluator §4 compares against: $ev_importers"
fi

# The corpus: the compiler itself, every stdlib module, and every
# `tests/selfhost` and `tests/stdlib` program. The stdlib modules
# contribute no routed functions of their own - compiled as an entry
# file a library keeps only what its `main` reaches - and they are
# here for the other half of the claim, that nothing moved.
mir_corpus=()
while IFS= read -r line; do
  mir_corpus+=("$line")
done < <(ls self_host/main.ax stdlib/*.ax stdlib/*/*.ax tests/selfhost/*.ax tests/stdlib/*.ax)

MARK_FLOOR=1600
MAIN_FLOOR=240
n_same=0
n_moved=0
n_marks=0
n_markbad=0
n_defs=0
main_marks=0
moved=""
for f in "${mir_corpus[@]}"; do
  AXIOM_MIR_EMIT=0 "$axc" emit-llvm --input "$f" > "$work/mir.off" 2>/dev/null; s_off=$?
  "$axc" emit-llvm --input "$f" > "$work/mir.on" 2>/dev/null; s_on=$?
  if [[ "$s_off" != "$s_on" ]]; then
    n_moved=$((n_moved + 1))
    moved="$moved $f(exit $s_off/$s_on)"
    continue
  fi
  # A file the compiler refuses either way says nothing about the
  # routing and is not counted as agreement.
  (( s_off != 0 )) && continue
  if cmp -s "$work/mir.off" "$work/mir.on"; then
    n_same=$((n_same + 1))
  else
    n_moved=$((n_moved + 1))
    moved="$moved $f"
    diff "$work/mir.off" "$work/mir.on" | head -8 | sed 's/^/     /'
  fi
  AXIOM_MIR_EMIT=mark "$axc" emit-llvm --input "$f" > "$work/mir.mark" 2>/dev/null
  m="$(grep -c '^  ; mir$' "$work/mir.mark" || true)"
  n_marks=$((n_marks + m))
  n_defs=$((n_defs + $(grep -c '^define ' "$work/mir.mark" || true)))
  [[ "$f" == "self_host/main.ax" ]] && main_marks="$m"
  grep -v '^  ; mir$' "$work/mir.mark" > "$work/mir.strip"
  cmp -s "$work/mir.strip" "$work/mir.on" || n_markbad=$((n_markbad + 1))
done
echo "     $n_marks of $n_defs emitted functions took the IR path across ${#mir_corpus[@]} files"
echo "     ($main_marks of them in self_host/main.ax, the compiler itself)"
if (( n_same >= 300 )); then
  ok "$n_same files emit byte-identical text with the routing on and off"
else
  bad "only $n_same files were compared - the corpus glob found nothing to measure"
fi
if (( n_moved == 0 )); then
  ok "no file moved a byte"
else
  bad "the routing moved bytes in:$moved"
fi
if (( n_markbad == 0 )); then
  ok "stripping the marks reproduces the unmarked emission everywhere"
else
  bad "$n_markbad files differ once the marks are stripped - the count is not about the text emitted"
fi
if (( n_marks >= MARK_FLOOR )); then
  ok "$n_marks functions took the IR path (floor $MARK_FLOOR)"
else
  bad "only $n_marks functions took the IR path, under the floor of $MARK_FLOOR"
  echo "     A routing that silently fell back to the walk for everything looks"
  echo "     exactly like this, with the byte comparison above still green."
fi
if (( main_marks >= MAIN_FLOOR )); then
  ok "$main_marks of the compiler's own functions took it (floor $MAIN_FLOOR)"
else
  bad "only $main_marks of the compiler's own functions took the IR path (floor $MAIN_FLOOR)"
fi
if (( n_marks < n_defs )); then
  ok "the routed set is a strict subset: $((n_defs - n_marks)) functions stayed on the walk"
else
  bad "every emitted function routed - the marker, not the router, is what changed"
fi

# ---------------------------------------------------------------
echo
echo "--- 6b. the coverage floor: how much of the corpus lowers ---"
# ---------------------------------------------------------------
# The lowering handles a SUBSET and refuses anything else outright,
# so a rule that narrowed itself to keep §4 green would leave every
# other check passing. This lowers every module in `self_host/` and
# `stdlib/` and requires the count not to fall; it PRINTS the live
# number, so drift is visible long before it is a failure. It also
# requires the count to be a strict subset of the corpus, because
# "everything lowered" would mean the counter, not the lowering, is
# what changed.
FLOOR=1900
CORPUS_FLOOR=4700
tot_l=0
tot_t=0
n_mod=0
for m in self_host/*.ax stdlib/*.ax stdlib/*/*.ax; do
  read -r l t <<<"$("$tool" count "$m" 2>/dev/null)"
  [[ -n "${t:-}" ]] || continue
  tot_l=$((tot_l + l))
  tot_t=$((tot_t + t))
  n_mod=$((n_mod + 1))
done
echo "     lowered $tot_l of $tot_t top-level functions across $n_mod modules"
if (( n_mod >= 40 )); then
  ok "the sweep opened $n_mod modules"
else
  bad "the sweep opened only $n_mod modules - the glob found nothing to measure"
fi
if (( tot_t >= CORPUS_FLOOR )); then
  ok "the corpus holds $tot_t top-level functions (floor $CORPUS_FLOOR)"
else
  bad "the corpus holds $tot_t top-level functions, under the floor of $CORPUS_FLOOR"
fi
if (( tot_l >= FLOOR )); then
  ok "$tot_l of them lower end to end (floor $FLOOR)"
else
  bad "only $tot_l lower end to end, under the floor of $FLOOR"
  echo "     A lowering rule that narrowed itself to keep §4 green looks exactly"
  echo "     like this, with every other check still passing."
fi
if (( tot_l < tot_t )); then
  ok "the subset is a strict subset: $((tot_t - tot_l)) functions refuse"
else
  bad "every function lowered - the counter, not the lowering, is what changed"
fi

# ---------------------------------------------------------------
echo
echo "--- 7. the operator table, against codegen.ax's ---"
# ---------------------------------------------------------------
"$tool" optable > "$work/optable" 2>&1
n_rows="$(wc -l < "$work/optable" | tr -d ' ')"
if [[ "$n_rows" == "12" ]]; then
  ok "mirtool optable printed 12 rows"
else
  bad "mirtool optable printed $n_rows rows, expected 12"
  sed 's/^/     /' "$work/optable" | head -14
fi
disagree="$(awk -F'|' 'NR <= 11 && $2 != $3 { print $1 }' "$work/optable" | tr '\n' ' ')"
if [[ -z "$disagree" && "$n_rows" == "12" ]]; then
  ok "all eleven operators carry the spelling codegen.ax already emits"
else
  bad "mir.ax and codegen.ax disagree on: $disagree"
  sed 's/^/     /' "$work/optable"
fi
# Row 12 is a name that is not an operator. The two MUST differ, or
# `mBinOp`'s refusal has been replaced by codegen's fall-through and
# a mistyped call would lower to an `add`.
last_mine="$(awk -F'|' 'NR == 12 { print $2 }' "$work/optable")"
last_cg="$(awk -F'|' 'NR == 12 { print $3 }' "$work/optable")"
if [[ "$n_rows" == "12" && -z "$last_mine" && "$last_cg" == "add" ]]; then
  ok "a non-operator: mir.ax answers nothing where codegen.ax answers 'add'"
else
  bad "the non-operator row reads mir='$last_mine' codegen='$last_cg'; expected mir empty, codegen 'add'"
fi

# ---------------------------------------------------------------
echo
echo "--- 8. the ablations ---"
# ---------------------------------------------------------------
# One shadow tree per ablation, the driver rebuilt from it. Nothing
# below touches the repository.
ablate() {
  local which="$1" root="$work/abl$1"
  rm -rf "$root"
  mkdir -p "$root"
  cp -R "$repo_root/self_host" "$repo_root/stdlib" "$root/"
  mkdir -p "$root/tests"
  cp -R "$repo_root/tests/mir" "$root/tests/"
  python3 - "$root/self_host/mir.ax" "$which" <<'PY'
import re, sys
p, which = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
# THE SEAMS ARE MATCHED WHITESPACE-INSENSITIVELY, and that is not
# tidiness. `axiom fmt` rewrites a file IN PLACE and puts a long
# constructor's arguments on ONE line separated by runs of spaces.
# Ablation 1's seam was written against the unformatted spelling of
# `mLowApp`'s `MO_BIN` emission, `mir.ax` was formatted afterwards,
# and the seam then appeared ZERO times: the ablation could not be
# built, so this gate reported a failure it could not explain in
# place of the evidence it exists to produce. A seam that this
# repository's own formatter can invalidate is a check that stops
# firing, so both are written with `\s+` between atoms - and both
# still assert the seam matches EXACTLY ONCE, which is what makes a
# vanished seam loud instead of silent.
if which == "1":
    # A binary operator's operands, swapped. Well-formed IR, wrong
    # meaning - `sub`, `sdiv`, `srem` and every comparison invert.
    pat = re.compile(r"(MO_BIN\s+\(mlcFresh lc\)\s+)\(vecGet out 0\)(\s+)\(vecGet out 1\)")
    rep = r"\g<1>(vecGet out 1)\g<2>(vecGet out 0)"
elif which == "2":
    # Every unconditional branch dropped. The branchless fixture is
    # untouched; every other block loses its terminator.
    pat = re.compile(r"\(if\s+(\(>\s+\(vecLen lc\.cur\.term\)\s+0\))(\s+0\s+\{\s+\(vecPush lc\.cur\.term n\))")
    rep = r"(if (|| \g<1> (== n.op MT_BR))\g<2>"
elif which == "4":
    # An `if` answers the THEN arm's register instead of the join
    # block's parameter. Every block still has its terminator and
    # every register is still defined exactly once, so ablations 1
    # and 2's checks say nothing; the only thing wrong with the
    # result is that the definition sits in a block which does not
    # DOMINATE the use.
    pat = re.compile(r"\(set lc\.cur bj\)(\s+)pj")
    rep = r"(set lc.cur bj)\g<1>r1"
else:
    sys.stderr.write("no such ablation: %s\n" % which)
    sys.exit(1)
hits = len(pat.findall(s))
if hits != 1:
    sys.stderr.write("seam %s appears %d times, expected 1\n" % (which, hits))
    sys.exit(1)
open(p, "w", encoding="utf-8").write(pat.sub(rep, s, count=1))
PY
  if [[ $? -ne 0 ]]; then
    return 1
  fi
  ( cd "$root" && "$axc" build --input tests/mir/mirtool.ax --output "$root/mirtool" ) \
    > "$root/build.log" 2>&1
}

# --- ABLATION 1: the operands, swapped ---
if ! ablate 1; then
  bad "ABLATION 1 could not be built"
  sed 's/^/     /' "$work/abl1/build.log" 2>/dev/null | head -10
else
  a1="$work/abl1/mirtool"
  n_red_print=0
  n_red_diff=0
  n_verify_noise=0
  n_crashed=0
  for f in "${fixtures[@]}"; do
    n="$(basename "$f" .ax)"
    "$a1" lower "$f" > "$work/abl1.$n.mir" 2>/dev/null
    cmp -s "$work/abl1.$n.mir" "tests/mir/$n.mir" || n_red_print=$((n_red_print + 1))
    # The braces catch the SHELL's own "Segmentation fault" line, which
    # a redirect on the command alone does not: an ablated evaluator
    # that dies is still a red, but the message would be mistaken for
    # this gate crashing.
    { "$a1" run "$f" "$PROBES" > "$work/abl1.$n.out" 2>/dev/null; } 2>/dev/null
    (( $? > 128 )) && n_crashed=$((n_crashed + 1))
    cmp -s "$work/abl1.$n.out" "$work/$n.native" || n_red_diff=$((n_red_diff + 1))
    "$a1" verify "$f" > "$work/abl1.$n.verify" 2>&1
    [[ -s "$work/abl1.$n.verify" ]] && n_verify_noise=$((n_verify_noise + 1))
  done
  if (( n_red_print == n_fix )); then
    ok "ABLATION 1: §2 goes red on all $n_fix fixtures"
  else
    bad "ABLATION 1: §2 goes red on only $n_red_print of $n_fix - the goldens are not pinning the operands"
  fi
  if (( n_red_diff == n_fix )); then
    ok "ABLATION 1: §4 goes red on all $n_fix fixtures"
  else
    bad "ABLATION 1: §4 goes red on only $n_red_diff of $n_fix - the differential is not reading the operands"
  fi
  # Every fixture is written so that the swap answers a WRONG NUMBER
  # rather than diverging. A crash is still a red, but it is a red
  # that would also appear if the machine were broken, so it is not
  # the evidence this ablation is here to produce.
  if (( n_crashed == 0 )); then
    ok "ABLATION 1: every red is a wrong answer, not a crash"
  else
    bad "ABLATION 1: $n_crashed fixtures died instead of answering; see 050-mutual's header"
  fi
  # The whole point of having two ablations: this one produces IR
  # that is WELL FORMED and wrong, so the verifier must have nothing
  # to say. If it complained here, §3 and §4 would be one check.
  if (( n_verify_noise == 0 )); then
    ok "ABLATION 1: §3 stays silent - a well-formed IR with the wrong meaning"
  else
    bad "ABLATION 1: §3 complained about $n_verify_noise fixtures; §3 and §4 are not independent"
  fi
fi

# --- ABLATION 2: every `br` dropped ---
if ! ablate 2; then
  bad "ABLATION 2 could not be built"
  sed 's/^/     /' "$work/abl2/build.log" 2>/dev/null | head -10
else
  a2="$work/abl2/mirtool"
  n_spoke=0
  n_named=0
  n_branchy=0
  wrong=""
  for f in "${fixtures[@]}"; do
    n="$(basename "$f" .ax)"
    # Which fixtures have a branch to drop is derived from the
    # CHECKED-IN golden, not from a list written here: a `condbr` in
    # NAME.mir means the lowering made blocks for that fixture, and
    # dropping `br` must then break it. A hand-written list would go
    # stale the moment a fixture was added, and would silently excuse
    # the very fixture that stopped branching.
    if grep -q 'condbr' "tests/mir/$n.mir"; then
      n_branchy=$((n_branchy + 1))
      expect=speak
    else
      expect=silent
    fi
    "$a2" verify "$f" > "$work/abl2.$n.verify" 2>&1
    if [[ -s "$work/abl2.$n.verify" ]]; then
      n_spoke=$((n_spoke + 1))
      grep -q 'has 0 terminators, want exactly 1' "$work/abl2.$n.verify" && n_named=$((n_named + 1))
      [[ "$expect" == "silent" ]] && wrong="$wrong $n(spoke)"
    else
      [[ "$expect" == "speak" ]] && wrong="$wrong $n(silent)"
    fi
  done
  if (( n_branchy > 0 && n_branchy < n_fix )); then
    ok "$n_branchy of $n_fix goldens carry a condbr, so both expectations are exercised"
  else
    bad "$n_branchy of $n_fix goldens carry a condbr - one of the two expectations is empty"
  fi
  if [[ -z "$wrong" ]]; then
    ok "ABLATION 2: §3 speaks about every branching fixture and is silent about the rest"
  else
    bad "ABLATION 2: §3 answered wrongly for:$wrong"
    sed 's/^/     /' "$work/abl2.020-if.verify" 2>/dev/null | head -6
  fi
  if (( n_named == n_spoke && n_spoke > 0 )); then
    ok "ABLATION 2: all $n_spoke complaints name the missing terminator, not a side effect"
  else
    bad "ABLATION 2: $n_named of $n_spoke complaints named the missing terminator"
    sed 's/^/     /' "$work/abl2.020-if.verify" 2>/dev/null | head -6
  fi
fi


# --- ABLATION 3: the constant fold, removed ---
#
# §6's byte comparison is the acceptance of the whole slice, and a
# comparison of a compiler with itself is exactly the shape that can
# pass while measuring nothing. So one emission rule is broken and
# the comparison must go RED.
#
# The rule is the fold. `MO_CONST` emits no line and consumes no
# register number - `emitExpr`'s `TAG_E_INT` path puts the literal
# straight into the operand of whatever reads it - and the ablation
# makes it take a number instead. Every register after a literal then
# shifts, which is the failure mode this slice is most exposed to.
#
# TWO ASSERTIONS, not one. The comparison must go red WITH the
# routing on, and the ablated compiler must still emit the reference
# text with the routing OFF - otherwise the break would be somewhere
# else in the compiler and the red would prove nothing about the IR
# path.
ablate_codegen() {
  local root="$work/abl3"
  rm -rf "$root"
  mkdir -p "$root"
  cp -R "$repo_root/self_host" "$repo_root/stdlib" "$root/"
  python3 - "$root/self_host/codegen.ax" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
# Whitespace-insensitive between atoms, for the reason ABLATION 1's
# seam records: `axiom fmt` rewrites a file IN PLACE and runs a long
# constructor's arguments together on one line, and a seam its own
# formatter can invalidate is a check that stops firing.
pat = re.compile(r"\(vecSet\s+ops\s+n\.dst\s+\(cast\s+Int\s+\(constStr\s+n\.a\)\)\s*\)")
rep = "(vecSet ops n.dst (cast Int (regStr (allocReg cg))))"
hits = len(pat.findall(s))
if hits != 1:
    sys.stderr.write("seam 3 appears %d times, expected 1\n" % hits)
    sys.exit(1)
open(p, "w", encoding="utf-8").write(pat.sub(rep, s, count=1))
PY
  if [[ $? -ne 0 ]]; then
    return 1
  fi
  ( cd "$root" && "$axc" build --input self_host/main.ax --output "$root/axc" ) \
    > "$root/build.log" 2>&1
}

if ! ablate_codegen; then
  bad "ABLATION 3 could not be built"
  sed 's/^/     /' "$work/abl3/build.log" 2>/dev/null | head -10
else
  a3="$work/abl3/axc"
  AXIOM_MIR_EMIT=0 "$axc"  emit-llvm --input self_host/main.ax > "$work/abl3.ref"    2>/dev/null
  AXIOM_MIR_EMIT=0 "$a3"   emit-llvm --input self_host/main.ax > "$work/abl3.off"    2>/dev/null
  "$a3"                    emit-llvm --input self_host/main.ax > "$work/abl3.on"     2>/dev/null
  if cmp -s "$work/abl3.off" "$work/abl3.ref"; then
    ok "ABLATION 3: with the routing off the ablated compiler emits the reference text"
  else
    bad "ABLATION 3: the break reaches the AST walk too - the red below proves nothing about the IR path"
    diff "$work/abl3.ref" "$work/abl3.off" | head -8 | sed 's/^/     /'
  fi
  if cmp -s "$work/abl3.on" "$work/abl3.off"; then
    bad "ABLATION 3: the byte comparison stayed green with the constant fold removed"
    echo "     §6 is comparing something other than what the IR emitter writes."
  else
    n_lines="$(diff "$work/abl3.off" "$work/abl3.on" | grep -c '^[<>]' || true)"
    ok "ABLATION 3: §6 goes red - $n_lines lines move when the fold is removed"
  fi
fi

# ---------------------------------------------------------------
echo
echo "--- 9. the guard, at the emitted bytes ---"
# ---------------------------------------------------------------
# THE EVALUATOR IS NOT THE ONLY WITNESS, and it must not be. §4 proves
# the IR and the compiled program agree; this proves the compiled
# program still WRAPS EVERY DIVISION, read straight off the compiler's
# own emitted IR with no evaluator in the loop. An emitter that began
# dropping guards while the evaluator dropped them too would satisfy
# §4 and fail here.
#
# The property is an exact correspondence in both directions: every
# `sdiv`/`srem` is the first instruction of a `divok_` block, and every
# `divok_` block starts with one.
"$axc" emit-llvm --input self_host/main.ax > "$work/self.ll" 2>"$work/self.ll.err" || {
  bad "could not emit the compiler's own IR"
}
if [[ -s "$work/self.ll" ]]; then
  n_divzero="$(grep -c '^divzero_' "$work/self.ll" || true)"
  n_divok="$(grep -c '^divok_' "$work/self.ll" || true)"
  # ANCHORED TO THE INSTRUCTION SHAPE, not to the name. A bare grep for
  # the symbol also matches its `declare` line, which made this count 94
  # against 93 divisions on the first run - the same family as the
  # `check-recover` grep that matched a backtrace symbol table.
  n_helper="$(grep -cE '^ *(%[^ ]+ = )?(tail )?call .*@__axiom_div_by_zero\(' "$work/self.ll" || true)"
  n_div="$(grep -cE '= (sdiv|srem) i64' "$work/self.ll" || true)"
  # a division not immediately preceded by its divok_ label
  unguarded="$(awk '/= (sdiv|srem) i64/ { if (prev !~ /^divok_/) n++ } { prev=$0 } END { print n+0 }' "$work/self.ll")"
  # a divok_ label not immediately followed by a division
  empty_ok="$(awk '/^divok_/ { getline nxt; if (nxt !~ /= (sdiv|srem) i64/) n++ } END { print n+0 }' "$work/self.ll")"
  if [[ "$unguarded" == 0 ]]; then
    ok "every sdiv/srem in the compiler's own IR follows a divok_ label"
  else
    bad "$unguarded sdiv/srem in the compiler's own IR are not guarded"
  fi
  if [[ "$empty_ok" == 0 ]]; then
    ok "every divok_ label in the compiler's own IR is followed by an sdiv/srem"
  else
    bad "$empty_ok divok_ labels are not followed by a division"
  fi
  # A floor, so the two zeroes above cannot be satisfied by a tree with
  # no divisions in it at all.
  if (( n_div >= 80 && n_divzero == n_div && n_divok == n_div && n_helper == n_div )); then
    ok "population: $n_div divisions, $n_divzero divzero_, $n_divok divok_, $n_helper trap calls"
  else
    bad "population disagrees: $n_div divisions, $n_divzero divzero_, $n_divok divok_, $n_helper trap calls (floor 80)"
  fi
fi

# --- ABLATION 4: the join's parameter replaced by one arm's register ---
# WITHOUT THIS, THE DOMINANCE CHECK CANNOT FAIL. Ablations 1 and 2
# reach the operand order and the terminator count; neither produces
# an IR whose definitions are all present and all single-assigned and
# still out of reach of their uses. That is the shape block
# parameters exist to make impossible to write by accident - and a
# rule that only ever answers "fine" is not a rule.
if ! ablate 4; then
  bad "ABLATION 4 could not be built"
  sed 's/^/     /' "$work/abl4/build.log" 2>/dev/null | head -10
else
  a4="$work/abl4/mirtool"
  n_spoke4=0
  n_lines4=0
  n_domlines=0
  wrong4=""
  for f in "${fixtures[@]}"; do
    n="$(basename "$f" .ax)"
    if grep -q 'condbr' "tests/mir/$n.mir"; then expect=speak; else expect=silent; fi
    "$a4" verify "$f" > "$work/abl4.$n.verify" 2>&1
    if [[ -s "$work/abl4.$n.verify" ]]; then
      n_spoke4=$((n_spoke4 + 1))
      n_lines4=$((n_lines4 + $(wc -l < "$work/abl4.$n.verify" | tr -d ' ')))
      n_domlines=$((n_domlines + $(grep -c 'does not dominate the use' "$work/abl4.$n.verify")))
      [[ "$expect" == "silent" ]] && wrong4="$wrong4 $n(spoke)"
    else
      [[ "$expect" == "speak" ]] && wrong4="$wrong4 $n(silent)"
    fi
  done
  if [[ -z "$wrong4" && $n_spoke4 -gt 0 ]]; then
    ok "ABLATION 4: §3 speaks about every branching fixture and is silent about the rest"
  else
    bad "ABLATION 4: §3 answered wrongly for:$wrong4"
    sed 's/^/     /' "$work/abl4.020-if.verify" 2>/dev/null | head -6
  fi
  # Every complaint must be the DOMINANCE one. If the terminator or
  # single-assignment rules fired here too, this ablation and
  # ablation 2 would be reporting the same thing and only one of them
  # would be evidence.
  if (( n_domlines == n_lines4 && n_lines4 > 0 )); then
    ok "ABLATION 4: all $n_lines4 complaints are the dominance rule, not a side effect"
  else
    bad "ABLATION 4: $n_domlines of $n_lines4 complaints named dominance"
    sed 's/^/     /' "$work/abl4.020-if.verify" 2>/dev/null | head -6
  fi
fi

echo
if (( failed > 0 )); then
  echo "check-mir: $failed of $checks checks failed"
  exit 1
fi
echo "check-mir: $checks checks - $n_fix fixtures lower to SSA with block"
echo "           parameters, print what their goldens say, verify clean,"
echo "           and EVALUATE to what the compiled program prints;"
echo "           $tot_l of $tot_t corpus functions lower, and codegen.ax"
echo "           EMITS $n_marks of $n_defs functions from the IR - the same"
echo "           bytes it emits with the routing switched off."
