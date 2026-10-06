#!/usr/bin/env bash
# The mid-level IR: what it prints, what it means, and how much of the
# tree goes through it.
#
# `self_host/mir.ax` is an IR between the checked AST and `codegen.ax`:
# a representation, a lowering, a printer and a verifier.
# `self_host/mireval.ax` is a reference evaluator over it, used only by
# tests. `codegen.ax` emits a subset of functions from the IR (§6).
#
# Goldens pin the form of the IR, not its meaning: `AXIOM_BLESS=1`
# rewrites them from whatever the lowering prints. So the anchor is §4,
# a differential the goldens cannot satisfy. The real compiler builds and
# runs each fixture, the evaluator runs its lowered IR, and the two
# stdouts must be byte-identical. ABLATION 1 is a lowering rule with the
# wrong meaning, and §4 catches it even with §2's goldens freshly blessed.
#
# The sections:
#
#   1. The driver builds. `tests/mir/mirtool.ax` imports `mir`, `mireval`
#      and the frontend. `mireval` is outside `self_host/main.ax`'s import
#      graph, so this build is the only thing that notices it breaking.
#   2. The printer, against `tests/mir/NAME.mir`, byte for byte. It is the
#      only check that sees the text, which the `.mir` tooling reads.
#   3. The verifier is silent on every fixture. `mirVerify` checks block
#      identity, one terminator per block, single assignment, definition
#      before use, real branch targets, block-argument arity and dominance.
#   4. The differential, described above.
#   5. Positive controls, so §4 cannot pass on empty or identical outputs.
#   6. The compiler emits from the IR, byte-identical to the AST walk, with
#      a floor on how many functions take the IR path.
#   6b. The coverage floor: how much of `self_host/` and `stdlib/` lowers.
#   7. The operator table, against `codegen.ax`'s. `mir.ax` carries its
#      own copy of `binopToLLVM` and `cmpToLLVM`, since `codegen.ax`
#      imports `mir` and importing them back would be a cycle.
#   8. The ablations, each in a shadow tree with the driver (or, for the
#      third, the whole compiler) rebuilt from it. Each must turn its own
#      checks red and leave the others green: two ablations that fire the
#      same check are one ablation written twice.
#   9. The division guard, read off the compiler's own emitted IR.
#
# The ablations:
#
#   1. Swaps a binary operator's operands in `mLowerApp`. The IR stays
#      well formed, so §3 stays silent, and §2 and §4 go red.
#   2. Drops every `br` in `mlcTerm`. §3 reports `has 0 terminators, want
#      exactly 1` on each fixture whose golden has a `condbr`, and stays
#      silent on the rest, so a verifier that complains about everything
#      fails too.
#   3. Removes the constant fold from `mirEmitInsts` in `codegen.ax`. §6's
#      comparison goes red, and the routing-off output must not move, or
#      the red is about something other than the IR path.
#   4. Answers a join block's parameter with one arm's register. Only the
#      dominance rule fires, on every branching fixture and no other.
#   5. Deletes the cast erasure, so a conversion refuses. §2 and §4 go red
#      on the fixtures whose sources cast; §3 stays silent, since a
#      refusal produces no IR.
#   6. Answers the `true` constant as 0. §2 and §4 go red on the fixtures
#      spelling a boolean literal; §3 stays silent.
#   7. Lowers `%` to `srex`, which no rule writes. §3 names it on the
#      fixtures whose goldens carry an `srem`, and stays silent on the rest.
#   8. Rebinds the loop exit to the loop's entry values. §2 and §4 go red
#      on the fixtures whose goldens carry an applied `condbr`; §3 stays
#      silent, since an entry value dominates the exit too.
#
# Which fixtures each ablation must move is derived from the goldens or
# the fixture sources, never listed by hand.
#
# Usage:  scripts/check-mir.sh
#         AXIOM_BLESS=1 scripts/check-mir.sh
#
# A bless rewrites the §2 goldens and nothing else. It cannot write
# `mir.ax`, the fixtures, `codegen.ax` or the corpus, so §3 to §9 still
# hold after one.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

# The tool imports compiler modules through an explicit search root.
export AXIOM_PATH="$repo_root/self_host${AXIOM_PATH:+:$AXIOM_PATH}"
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $1"; checks=$((checks + 1)); }
bad() { echo "FAIL $1"; checks=$((checks + 1)); failed=$((failed + 1)); }

# How many values each fixture's `probe` is asked for. Each fixture's
# own `emit` counts to the same number, and §5 checks that they agree.
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

  # The fixture convention: every `probe*` function lowers, and `emit`
  # refuses. The second half keeps the refusal path live, since a
  # freshly blessed golden would not notice a lowering that stopped
  # refusing.
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
  # A trapping fixture exits nonzero, so the status is compared with
  # `NAME.exit` (0 when absent). The native run and the evaluator are
  # each checked against that file as well as against each other: two
  # sides that drifted together would still agree.
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
  # A fixture that traps stops early, and `NAME.lines` says how early.
  # Every other fixture prints $PROBES lines.
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
# `codegen.ax` imports `mir`, and `mirEmitOrWalk` emits a subset of
# functions from the IR instead of the AST walk. The routing has an off
# switch, `AXIOM_MIR_EMIT=0`, so one compiler is compared with itself
# over one tree. That isolates the routing from everything else, byte
# for byte, on the compiler and on every corpus program.
#
# A floor on routed functions is printed every run, because a routing
# that fell back to the walk everywhere also answers "identical". The
# count is read off the emitted text: `AXIOM_MIR_EMIT=mark` writes one
# `  ; mir` line inside each function the IR emitted. Stripping those
# lines must reproduce the unmarked emission, so the marks move nothing.
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
# The set of importers is exact. A new consumer arriving unnoticed is
# what a `grep -q` would miss, and each consumer makes the IR's shape
# load-bearing somewhere else.
#
#   codegen.ax   emits from it
#   axir.ax      projects it into the `.axir` record file
#   mireval.ax   evaluates it, and is §4's independent reference
want_mir="axir.ax codegen.ax mireval.ax"
got_mir="$(grep -l -E '^\(import mir\)$' self_host/*.ax | xargs -n1 basename | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
if [[ "$got_mir" == "$want_mir" ]]; then
  ok "exactly three modules import mir: $got_mir"
else
  bad "the importers of mir have moved: want [$want_mir], got [$got_mir]"
fi

# `mireval` stays test-only: §4 compares the compiler against it, and a
# compiler that imported its own reference would be compared with itself.
ev_importers="$(grep -l -E '^\(import mireval\)' self_host/*.ax | grep -v '^self_host/mireval\.ax$' | tr '\n' ' ')"
if [[ -z "$ev_importers" ]]; then
  ok "no compiler module imports mireval - §4's reference is still independent"
else
  bad "these modules import the evaluator §4 compares against: $ev_importers"
fi

# The corpus: the compiler itself, every stdlib module, and every
# `tests/selfhost` and `tests/stdlib` program. A stdlib module compiled
# as an entry file keeps only what its `main` reaches, so it routes
# nothing; it is here to show that nothing moved.
mir_corpus=()
while IFS= read -r line; do
  mir_corpus+=("$line")
done < <(ls self_host/main.ax stdlib/*.ax stdlib/*/*.ax tests/selfhost/*.ax tests/stdlib/*.ax)

MARK_FLOOR=1620
MAIN_FLOOR=250
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
# The lowering handles a subset and refuses everything else, so a rule
# that narrowed itself to keep §4 green would leave every other check
# passing. This lowers every module in `self_host/` and `stdlib/`,
# prints the live count so drift shows early, and fails below FLOOR.
# The count must stay a strict subset of the corpus: "everything
# lowered" would mean the counter changed, not the lowering.
FLOOR=2250
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
if [[ "$n_rows" == "17" ]]; then
  ok "mirtool optable printed 17 rows"
else
  bad "mirtool optable printed $n_rows rows, expected 17"
  sed 's/^/     /' "$work/optable" | head -19
fi
# Fields are counted from the end. The `|` operator's own row is
# `||or|or`, four fields, so `$2 != $3` would compare two halves of the
# name. Neither spelling contains a bar, so `mine` is always field NF-1
# and `cg` field NF. The report prints the whole row, since that row's
# `$1` is empty.
disagree="$(awk -F'|' 'NR <= 16 && $(NF-1) != $NF { print $0 }' "$work/optable" | tr '\n' ' ')"
if [[ -z "$disagree" && "$n_rows" == "17" ]]; then
  ok "all sixteen operators carry the spelling codegen.ax already emits"
else
  bad "mir.ax and codegen.ax disagree on: $disagree"
  sed 's/^/     /' "$work/optable"
fi
# Row 17 is a name that is not an operator. The two must differ, or
# `mBinOp`'s refusal has been replaced by codegen's fall-through and
# a mistyped call would lower to an `add`.
last_mine="$(awk -F'|' 'NR == 17 { print $(NF-1) }' "$work/optable")"
last_cg="$(awk -F'|' 'NR == 17 { print $NF }' "$work/optable")"
if [[ "$n_rows" == "17" && -z "$last_mine" && "$last_cg" == "add" ]]; then
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
# Seams match whitespace-insensitively. `axiom fmt` rewrites a file in
# place and can put a long constructor's arguments on one line, separated
# by runs of spaces, so atoms are joined with `\s+`. Each seam must still
# match exactly once, so a vanished seam fails loudly.
if which == "1":
    # A binary operator's operands, swapped. Well-formed IR with the
    # wrong meaning: `sub`, `sdiv`, `srem` and every comparison invert.
    pat = re.compile(r"(MO_BIN\s+\(mlcFresh lc\)\s+)\(vecGet out 0\)(\s+)\(vecGet out 1\)")
    rep = r"\g<1>(vecGet out 1)\g<2>(vecGet out 0)"
elif which == "2":
    # Every unconditional branch dropped. Branchless fixtures are
    # untouched; elsewhere each block that ended in a `br` has no
    # terminator.
    pat = re.compile(r"\(if\s+(\(>\s+\(vecLen lc\.cur\.term\)\s+0\))(\s+0\s+\{\s+\(vecPush lc\.cur\.term n\))")
    rep = r"(if (|| \g<1> (== n.op MT_BR))\g<2>"
elif which == "4":
    # An `if` answers the then arm's register instead of the join
    # block's parameter. Every block keeps its terminator and every
    # register is defined once; the only fault is a definition in a
    # block that does not dominate the use. Scoped to `mLowerIf` by the
    # function head: the `&&`/`||` desugar ends its join the same way.
    pat = re.compile(r"(\(pub fn \(mLowerIf[\s\S]*?\(set lc\.cur bj\)\s+)pj")
    rep = r"\g<1>r1"
elif which == "5":
    # The cast erasure, removed: a conversion refuses instead of
    # answering its value's register. The goldens and the differential
    # move, and the verifier stays silent because nothing ill-formed is
    # produced. Scoped to `mLowerApp` by the function head: the
    # `&&`/`||` desugar lowers its right-hand side through the same call.
    pat = re.compile(r"(\(pub fn \(mLowerApp[\s\S]*?)\(mLower\s+lc\s+env\s+\(vecGet\s+args\s+1\)\)")
    rep = r"\g<1>(- 0 1)"
elif which == "6":
    # `true` lowered as 0: well-formed IR with the wrong meaning, like
    # ablation 1, for the constant an operand swap cannot reach. The
    # replacement builds its quotes with `chr(34)`: a backslash-escaped
    # quote in this quoted heredoc lands in the source as AX1001.
    pat = re.compile(r"\(mlcFresh lc\)\s+1\s+0\s+\"\"")
    rep = "(mlcFresh lc)        0        0        " + chr(34) + chr(34)
elif which == "7":
    # `%` lowers to `srex`, which no rule writes and no consumer reads.
    # The seam names the `mBinOp` row, not the bare spelling: `srem`
    # also appears in `mIsDivOp` and `mIsBinSpelling`, which keep the
    # true set, so the verifier fires. Single-quoted raw strings carry
    # plain quotes through the quoted heredoc untouched.
    pat = re.compile(r'\(strEq nm "%"\)\s+"srem"')
    rep = r'(strEq nm "%")  "srex"'
elif which == "8":
    # The exit rebinds to the entry values instead of the exit
    # parameters, so every read after the loop answers what the `mut`
    # held before the first trip. Well-formed IR with the wrong meaning.
    # Scoped to `mLowerWhile` by the function head; the `px` rebind is
    # the only one of the three that names the exit's parameters.
    pat = re.compile(r"(\(pub fn \(mLowerWhile[\s\S]*?mRebind\s+env\s+names\s+)px(\s+0\))")
    rep = r"\g<1>entryRegs\g<2>"
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
  ( cd "$root" && AXIOM_PATH="$root/self_host${AXIOM_PATH:+:$AXIOM_PATH}" \
    "$axc" build --input tests/mir/mirtool.ax --output "$root/mirtool" ) \
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
    # The braces also catch the shell's own "Segmentation fault" line,
    # which would otherwise read as this gate crashing.
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
  # Every fixture is written so the swap answers a wrong number instead
  # of diverging. A crash is still red, but a broken machine would crash
  # too, so it is not this ablation's evidence.
  if (( n_crashed == 0 )); then
    ok "ABLATION 1: every red is a wrong answer, not a crash"
  else
    bad "ABLATION 1: $n_crashed fixtures died instead of answering; see 050-mutual's header"
  fi
  # This ablation's IR is well formed and wrong, so the verifier must
  # say nothing. If it complained here, §3 and §4 would be one check.
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
    # Which fixtures branch is read from the checked-in golden: a
    # `condbr` in NAME.mir means the lowering made blocks, and dropping
    # `br` must break them. A hand-written list would go stale when a
    # fixture is added, and would excuse a fixture that stopped branching.
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
# A compiler compared with itself could pass while measuring nothing,
# so one emission rule is broken and §6's comparison must go red.
#
# The rule is the fold. `MO_CONST` emits no line and takes no register
# number: like `emitExpr`'s `TAG_E_INT` path, it puts the literal
# straight into its reader's operand. The ablation makes it take a
# number, so every later register shifts, the failure this path is most
# exposed to. With the routing off, the ablated compiler must still emit
# the reference text, or the red proves nothing about the IR path.
ablate_codegen() {
  local root="$work/abl3"
  rm -rf "$root"
  mkdir -p "$root"
  cp -R "$repo_root/self_host" "$repo_root/stdlib" "$root/"
  python3 - "$root/self_host/codegen.ax" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
# Whitespace-insensitive between atoms, for the reason the `ablate`
# seams give: `axiom fmt` can rejoin a long constructor's arguments.
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
  gate_build_tree "$axc" "$root" "$AXIOM_STDLIB" "$root/axc" \
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
# §4 shows the IR and the compiled program agree. This shows the
# compiled program still guards every division, read straight off the
# compiler's own emitted IR with no evaluator involved. An emitter and
# an evaluator that dropped guards together would pass §4 and fail here.
#
# The correspondence is exact both ways: every `sdiv`/`srem` is the first
# instruction of a `divok_` block, and every `divok_` block starts with one.
"$axc" emit-llvm --input self_host/main.ax > "$work/self.ll" 2>"$work/self.ll.err" || {
  bad "could not emit the compiler's own IR"
}
if [[ -s "$work/self.ll" ]]; then
  n_divzero="$(grep -c '^divzero_' "$work/self.ll" || true)"
  n_divok="$(grep -c '^divok_' "$work/self.ll" || true)"
  # Match the call instruction, not the bare symbol, which would also
  # count the symbol's `declare` line.
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
# Without this drill the dominance check is never seen to fail.
# Ablations 1 and 2 reach operand order and terminator count; neither
# produces IR whose definitions are all present and single-assigned yet
# out of reach of their uses, the shape block parameters exist to prevent.
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
  # Every complaint must be the dominance one. If the terminator or
  # single-assignment rules fired too, this would duplicate ablation 2.
  if (( n_domlines == n_lines4 && n_lines4 > 0 )); then
    ok "ABLATION 4: all $n_lines4 complaints are the dominance rule, not a side effect"
  else
    bad "ABLATION 4: $n_domlines of $n_lines4 complaints named dominance"
    sed 's/^/     /' "$work/abl4.020-if.verify" 2>/dev/null | head -6
  fi
fi

# --- ABLATION 5: the cast erasure, removed ---
# Without this drill the cast erasure is unpinned: ablations 1, 2 and 4
# leave conversions alone. With the erasure deleted, every probe that
# casts refuses and nothing else moves. The casting fixtures are read
# from the sources (`(cast ` in NAME.ax), for ablation 2's reason.
if ! ablate 5; then
  bad "ABLATION 5 could not be built"
  sed 's/^/     /' "$work/abl5/build.log" 2>/dev/null | head -10
else
  a5="$work/abl5/mirtool"
  n_cast=0
  wrong5=""
  crashed5=0
  for f in "${fixtures[@]}"; do
    n="$(basename "$f" .ax)"
    if grep -q '(cast ' "tests/mir/$n.ax"; then expect=red; else expect=same; fi
    [[ "$expect" == "red" ]] && n_cast=$((n_cast + 1))
    "$a5" lower "$f" > "$work/abl5.$n.mir" 2>/dev/null
    if cmp -s "$work/abl5.$n.mir" "tests/mir/$n.mir"; then got=same; else got=red; fi
    [[ "$got" != "$expect" ]] && wrong5="$wrong5 $n(print-$got)"
    { "$a5" run "$f" "$PROBES" > "$work/abl5.$n.out" 2>/dev/null; } 2>/dev/null
    (( $? > 128 )) && crashed5=$((crashed5 + 1))
    cmp -s "$work/abl5.$n.out" "$work/$n.native" || {
      [[ "$expect" == "red" ]] || wrong5="$wrong5 $n(eval-red)"
    }
    if cmp -s "$work/abl5.$n.out" "$work/$n.native"; then
      [[ "$expect" == "red" ]] && wrong5="$wrong5 $n(eval-same)"
    fi
    "$a5" verify "$f" > "$work/abl5.$n.verify" 2>&1
    [[ -s "$work/abl5.$n.verify" ]] && wrong5="$wrong5 $n(spoke)"
  done
  if (( n_cast > 0 )); then
    ok "$n_cast fixture(s) cast, so the drill has something to move"
  else
    bad "no fixture casts - ABLATION 5 passes over an empty set"
    wrong5="$wrong5 (empty)"
  fi
  if [[ -z "$wrong5" ]]; then
    ok "ABLATION 5: §2 and §4 go red exactly on the fixtures that cast, and §3 stays silent on all $n_fix"
  else
    bad "ABLATION 5: answered wrongly for:$wrong5"
  fi
  if (( crashed5 == 0 )); then
    ok "ABLATION 5: every red is a wrong answer or a refusal, not a crash"
  else
    bad "ABLATION 5: $crashed5 fixtures died instead of answering"
  fi
fi

# --- ABLATION 6: `true` answers 0 ---
# Without this drill a literal's value is unpinned: an operand swap
# leaves a constant alone. The boolean fixtures are read from the
# sources (a bare `true` or `false` outside comments and strings), for
# ablation 2's reason.
if ! ablate 6; then
  bad "ABLATION 6 could not be built"
  sed 's/^/     /' "$work/abl6/build.log" 2>/dev/null | head -10
else
  a6="$work/abl6/mirtool"
  n_bool=0
  wrong6=""
  crashed6=0
  for f in "${fixtures[@]}"; do
    n="$(basename "$f" .ax)"
    if sed 's/;.*//; s/"[^"]*"//g' "tests/mir/$n.ax" | grep -qwE 'true|false'; then
      expect=red
    else
      expect=same
    fi
    [[ "$expect" == "red" ]] && n_bool=$((n_bool + 1))
    "$a6" lower "$f" > "$work/abl6.$n.mir" 2>/dev/null
    if cmp -s "$work/abl6.$n.mir" "tests/mir/$n.mir"; then got=same; else got=red; fi
    [[ "$got" != "$expect" ]] && wrong6="$wrong6 $n(print-$got)"
    { "$a6" run "$f" "$PROBES" > "$work/abl6.$n.out" 2>/dev/null; } 2>/dev/null
    (( $? > 128 )) && crashed6=$((crashed6 + 1))
    if cmp -s "$work/abl6.$n.out" "$work/$n.native"; then
      [[ "$expect" == "red" ]] && wrong6="$wrong6 $n(eval-same)"
    else
      [[ "$expect" == "same" ]] && wrong6="$wrong6 $n(eval-red)"
    fi
    "$a6" verify "$f" > "$work/abl6.$n.verify" 2>&1
    [[ -s "$work/abl6.$n.verify" ]] && wrong6="$wrong6 $n(spoke)"
  done
  if (( n_bool > 0 )); then
    ok "$n_bool fixture(s) spell a boolean, so the drill has something to move"
  else
    bad "no fixture spells a boolean - ABLATION 6 passes over an empty set"
    wrong6="$wrong6 (empty)"
  fi
  if [[ -z "$wrong6" ]]; then
    ok "ABLATION 6: §2 and §4 go red exactly on the fixtures that spell a boolean, and §3 stays silent on all $n_fix"
  else
    bad "ABLATION 6: answered wrongly for:$wrong6"
  fi
  if (( crashed6 == 0 )); then
    ok "ABLATION 6: every red is a wrong answer, not a crash"
  else
    bad "ABLATION 6: $crashed6 fixtures died instead of answering"
  fi
fi

# --- ABLATION 7: a binop spelling corrupted ---
# Without this drill a binop's spelling is unpinned: ablations 1 and 2
# break operands and terminators, not what a binop is called. The
# `srem` fixtures are read from the checked-in goldens, for ablation
# 2's reason.
if ! ablate 7; then
  bad "ABLATION 7 could not be built"
  sed 's/^/     /' "$work/abl7/build.log" 2>/dev/null | head -10
else
  a7="$work/abl7/mirtool"
  n_srem=0
  n_spoke7=0
  n_named7=0
  wrong7=""
  for f in "${fixtures[@]}"; do
    n="$(basename "$f" .ax)"
    if grep -q 'srem' "tests/mir/$n.mir"; then
      expect=speak
    else
      expect=silent
    fi
    [[ "$expect" == "speak" ]] && n_srem=$((n_srem + 1))
    "$a7" verify "$f" > "$work/abl7.$n.verify" 2>&1
    if [[ -s "$work/abl7.$n.verify" ]]; then
      n_spoke7=$((n_spoke7 + 1))
      grep -q 'srex' "$work/abl7.$n.verify" && n_named7=$((n_named7 + 1))
      [[ "$expect" == "silent" ]] && wrong7="$wrong7 $n(silent-expected)"
    else
      [[ "$expect" == "speak" ]] && wrong7="$wrong7 $n(speak-expected)"
    fi
  done
  if (( n_srem > 0 && n_srem < n_fix )); then
    ok "$n_srem of $n_fix goldens carry an srem, so both expectations are exercised"
  else
    bad "$n_srem of $n_fix goldens carry an srem - one of the two expectations is empty"
  fi
  if [[ -z "$wrong7" ]]; then
    ok "ABLATION 7: §3 names the corrupted spelling on every srem fixture and is silent about the rest"
  else
    bad "ABLATION 7: §3 answered wrongly for:$wrong7"
  fi
  if (( n_named7 == n_spoke7 && n_spoke7 > 0 )); then
    ok "ABLATION 7: all $n_spoke7 complaints name the corrupted spelling, not a side effect"
  else
    bad "ABLATION 7: $n_named7 of $n_spoke7 complaints named the corrupted spelling"
  fi
fi

# --- ABLATION 8: the exit answers the entry values ---
# Without this drill the exit rebind is unpinned: ablations 1 and 6
# move operands and constants, not which registers the names after a
# loop answer. The looping fixtures are read from the goldens (a
# `condbr` line holding a paren, the applied form only the loop lowering
# writes), for ablation 2's reason.
#
# The seam is the exit, not the back-edge: stale values on the back-edge
# make the loop diverge, and a drill must not hang. The loop's own 0
# answer needs no drill: `140-while` binds it as `w` and prints it.
if ! ablate 8; then
  bad "ABLATION 8 could not be built"
  sed 's/^/     /' "$work/abl8/build.log" 2>/dev/null | head -10
else
  a8="$work/abl8/mirtool"
  n_loop=0
  wrong8=""
  crashed8=0
  for f in "${fixtures[@]}"; do
    n="$(basename "$f" .ax)"
    if grep -q 'condbr.*(' "tests/mir/$n.mir"; then
      expect=red
    else
      expect=same
    fi
    [[ "$expect" == "red" ]] && n_loop=$((n_loop + 1))
    "$a8" lower "$f" > "$work/abl8.$n.mir" 2>/dev/null
    if cmp -s "$work/abl8.$n.mir" "tests/mir/$n.mir"; then got=same; else got=red; fi
    [[ "$got" != "$expect" ]] && wrong8="$wrong8 $n(print-$got)"
    { "$a8" run "$f" "$PROBES" > "$work/abl8.$n.out" 2>/dev/null; } 2>/dev/null
    (( $? > 128 )) && crashed8=$((crashed8 + 1))
    if cmp -s "$work/abl8.$n.out" "$work/$n.native"; then
      [[ "$expect" == "red" ]] && wrong8="$wrong8 $n(eval-same)"
    else
      [[ "$expect" == "same" ]] && wrong8="$wrong8 $n(eval-red)"
    fi
    "$a8" verify "$f" > "$work/abl8.$n.verify" 2>&1
    [[ -s "$work/abl8.$n.verify" ]] && wrong8="$wrong8 $n(spoke)"
  done
  if (( n_loop > 0 )); then
    ok "$n_loop fixture(s) loop, so the drill has something to move"
  else
    bad "no fixture loops - ABLATION 8 passes over an empty set"
    wrong8="$wrong8 (empty)"
  fi
  if [[ -z "$wrong8" ]]; then
    ok "ABLATION 8: §2 and §4 go red exactly on the fixtures that loop, and §3 stays silent on all $n_fix"
  else
    bad "ABLATION 8: answered wrongly for:$wrong8"
  fi
  if (( crashed8 == 0 )); then
    ok "ABLATION 8: every red is a wrong answer, not a crash"
  else
    bad "ABLATION 8: $crashed8 fixtures died instead of answering"
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
