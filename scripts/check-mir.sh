#!/usr/bin/env bash
# THE MID-LEVEL IR: WHAT IT PRINTS, WHAT IT MEANS, AND HOW MUCH OF
# THE TREE GOES THROUGH IT.
#
# `self_host/mir.ax` is the first slice of an IR between the checked
# AST and `codegen.ax`: a representation, a lowering, a printer and a
# verifier. `self_host/mireval.ax` is a reference evaluator over it.
#
# THE COMPILER NOW IMPORTS `mir`, and §6 has changed from "nobody does"
# to "exactly `axir.ax` does". `axiom symbols --axir --mir` writes the
# `blk`, `op` and `term` lines of every function `mLowerFn` lowers, so
# the IR is inside `self_host/main.ax`'s import closure and the
# self-host build compiles it. `mireval` is still outside, and is still
# run only from here.
#
# THE HOLLOW VERSION OF THIS GATE, which is what every assertion
# below is shaped against: compile eight fixtures, print their IR,
# compare against eight checked-in goldens, exit 0. That version
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
# The reference there is 97,000 lines of compiler this change did not
# touch. A lowering rule that quietly means something other than the
# source it came from fails §4 with §2's goldens freshly blessed and
# every other check green - and that is drilled rather than asserted:
# ABLATION 1 below is exactly such a rule.
#
# THE EIGHT SECTIONS.
#
#   1. THE DRIVER BUILDS. `tests/mir/mirtool.ax` imports `mir`,
#      `mireval` and the whole frontend, and is compiled by the
#      compiler under test. `mir` is now in `self_host/main.ax`'s
#      import graph and the self-host build would notice IT breaking;
#      `mireval` is not, so for that half this is still the only check
#      that it compiles against the current tree at all.
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
#      eight outputs must be eight DISTINCT files - eight fixtures
#      that all print the same twenty lines would satisfy §4 against
#      a lowering that ignored its input.
#
#   6. THE BOUNDARY, and the coverage floor.
#
#      The boundary USED to be "nothing in `self_host/` imports the
#      IR", which made `axiom emit-llvm self_host/main.ax`
#      byte-identical with `mir.ax` present and deleted. That is over:
#      `self_host/axir.ax` imports `mir` to write the `blk`, `op` and
#      `term` lines of the record file, exactly the deliberate
#      deletion the old text promised. What replaces it is an
#      assertion with the same job - saying where the arrow points -
#      rather than a deleted line: the importer set is EXACTLY
#      `axir.ax` for `mir` and `mireval.ax` alone for `mireval`, so a
#      second consumer of either is an edit someone made on purpose
#      and not one that arrived with a copied import block. `mireval`
#      staying out is the load-bearing half now: it is the reference
#      evaluator, it exists to disagree with the compiler, and a
#      compiler that imported it could not.
#
#      Then the floor. The lowering handles a SUBSET, and refuses
#      anything else outright, so a rule that narrowed itself to keep
#      §4 green would leave every other check passing. §6 lowers
#      every module in `self_host/` and `stdlib/` and requires the
#      count not to fall; it PRINTS the live number, so drift is
#      visible long before it is a failure. It also requires the
#      count to be a strict subset of the corpus, because "everything
#      lowered" would mean the counter, not the lowering, is what
#      changed.
#
#   7. THE OPERATOR TABLE, against `codegen.ax`'s. `mir.ax` cannot
#      import `codegen.ax` - slice 2 points that arrow the other way
#      - so it carries its own copy of `binopToLLVM` + `cmpToLLVM`.
#      `mirtool optable` is the one place in the tree that imports
#      both, and all eleven operators must agree. The twelfth row
#      must DISAGREE: `codegen.ax` answers "add" for a name it never
#      expects to be handed, and `mir.ax` answers "", which is what
#      makes the lowering refuse rather than emit a wrong opcode.
#
#   8. THE ABLATIONS, both in a shadow tree with the driver rebuilt
#      from it, and both chosen so that they are ORTHOGONAL - each
#      must turn its own checks red and leave the other's green,
#      because two ablations that fire the same check are one
#      ablation written twice.
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
# AXIOM_BLESS=1 rewrites the §2 goldens and nothing else. It cannot
# write `self_host/mir.ax`, the fixtures, `codegen.ax`'s operator
# table or the corpus, which is why §3 to §8 survive a bless.
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

# Eight fixtures that all print the same twenty lines would satisfy
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
echo "--- 6. the boundary, and the coverage floor ---"
# ---------------------------------------------------------------
# WHO IMPORTS THE IR, spelled as an exact set rather than as "nobody".
# `axir.ax` imports `mir` because `symbols --axir --mir` writes the
# body lines; `mireval.ax` imports `mir` because it evaluates it. Any
# THIRD importer is a widening of the compiler's dependency on an IR
# that is still one slice old, and any importer of `mireval` at all
# would put the reference evaluator inside the thing it is the
# reference for.
mir_importers="$(grep -l -E '^\(import mir\)' self_host/*.ax | LC_ALL=C sort | tr '\n' ' ')"
mir_want="self_host/axir.ax self_host/mireval.ax "
if [[ "$mir_importers" == "$mir_want" ]]; then
  ok "mir is imported by exactly axir.ax (the record writer) and mireval.ax"
else
  bad "mir's importers are [$mir_importers], want [$mir_want]"
  echo "     A module that lowers to this IR is a decision, not a default. If the"
  echo "     new importer is intended, say so here and move the expected set with"
  echo "     it; the point of the set is that it cannot grow in silence."
fi
eval_importers="$(grep -l -E '^\(import mireval\)' self_host/*.ax | tr '\n' ' ')"
if [[ -z "$eval_importers" ]]; then
  ok "no compiler module imports mireval - the reference evaluator is outside the compiler"
else
  bad "these compiler modules import the reference evaluator: $eval_importers"
  echo "     §4's differential compares the compiler against mireval. A compiler"
  echo "     that contains mireval is comparing something with itself."
fi

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
else:
    # Every unconditional branch dropped. The branchless fixture is
    # untouched; every other block loses its terminator.
    pat = re.compile(r"\(if\s+(\(>\s+\(vecLen lc\.cur\.term\)\s+0\))(\s+0\s+\{\s+\(vecPush lc\.cur\.term n\))")
    rep = r"(if (|| \g<1> (== n.op MT_BR))\g<2>"
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

echo
if (( failed > 0 )); then
  echo "check-mir: $failed of $checks checks failed"
  exit 1
fi
echo "check-mir: $checks checks - $n_fix fixtures lower to SSA with block"
echo "           parameters, print what their goldens say, verify clean,"
echo "           and EVALUATE to what the compiled program prints;"
echo "           $tot_l of $tot_t corpus functions lower; mir is imported by"
echo "           axir.ax alone and mireval by nothing."
