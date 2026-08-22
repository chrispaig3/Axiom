#!/usr/bin/env bash
# Compile and RUN the standard-library corpus with the self-hosted
# compiler, and check what the programs actually do - stdout byte for
# byte, and exit status - against two things that were not produced by
# the compiler under test.
#
# WHAT THIS USED TO PIN, AND WHY IT COULD NOT STAY
#
# This gate was a differential: build every `tests/stdlib/` case with
# stage0 (the Rust compiler) and with stage1, run both through the same
# `llc`/`cc` pipeline, and require identical stdout and identical exit
# status. It deliberately took stage0's answer rather than a checked-in
# expected value, on the argument that stage0 was the trusted
# implementation and `run-stdlib-tests.sh` already pinned stage0's own
# answers.
#
# That argument dies with stage0. Worse, it dies SILENTLY: a differential
# does not fail when its reference disappears. Point `$axiom` at a
# self-hosted binary and both sides of every comparison become the same
# compiler - 37 cases swept, zero differences, exit 0, nothing tested.
# The corpus would keep printing `ok` while a miscompile walked in.
#
# WHAT IT PINS NOW
#
#   1. GOLDENS. `tests/stdlib/NAME.out` byte for byte, and `NAME.exit`
#      (default 0), for every case, at `llc -O0` AND `llc -O2`. These are
#      the same goldens `run-stdlib-tests.sh` has always used, and the
#      differential's own premise was that they were trustworthy. Their
#      provenance is that they were written by the Rust compiler before
#      any self-hosted binary had an opinion about this corpus: 32 of the
#      37 are byte-identical to their content at 5f6aaaa (2026-08-06),
#      the commit that first ran `tests/stdlib/` through stage1 at all.
#      The five that have moved since are 160-arena, 165-arena-keep,
#      210-flags-across-syscall, 300-process and 340-json - and the last
#      four of those did not exist at 5f6aaaa, so they never had stage0
#      provenance either.
#
#   2. THE FIXTURES' OWN SOURCE. `tests/stdlib/verify-stdlib-out.py`
#      derives 446 expected output values over 30 of the 37 cases from
#      `NAME.ax`, and 34 of the 37 expected exit statuses, and checks
#      them - in order, as a subsequence - against what the program
#      printed and what it returned. It never opens a `.out` file. Three
#      sources of claim: the expectation the corpus writes beside its own
#      calls (`(println (& 12 10))  ; 8`, `(describe (CInt 7))  ; 7`);
#      a Python model of the literal-only part of `Str`/`Utf8`
#      (`(println (strLen "héllo"))` must print 6 because the literal
#      is six bytes); and, for a case that GRADES ITSELF, the verdict the
#      fixture publishes about each of its own checks. See that file's
#      header for the extraction rules and for why claims are matched as
#      a subsequence.
#
# WHY THAT IS ADEQUATE
#
# A checked-in golden alone is not: if the compiler is wrong and someone
# regenerates `NAME.out` from the wrong compiler, a golden-only gate goes
# green. Check 2 cannot be satisfied that way, because rewriting a golden
# does not change the source the claims come from - the compiler would
# have to be right, or the fixture's comments, its string literals and
# its own pass/fail vocabulary would all have to be edited to agree with
# the wrong answer. Check 2 also runs against the goldens THEMSELVES
# before any compiling happens, so a re-blessed golden is refused even on
# a machine with no toolchain.
#
# Against the differential it replaces, check 2 is stronger in kind:
# agreeing with another implementation says two implementations agree,
# and `330-utf8`'s header makes the same point about a decoder that
# round-trips with its own encoder. Check 2 says the answer is CORRECT.
#
# HOW FAR IT REACHES, MEASURED RATHER THAN ASSERTED
#
# Mutation test, no compiler required: corrupt one line of one golden and
# ask the verifier whether it still accepts the corpus. Of the corpus's
# 546 output lines, 443 are pinned by a derived claim and 103 (18.9%) can
# be corrupted with the verifier silent. Seven cases yield no claim at
# all and are pinned by their golden alone - 040-mem, 050-file-io,
# 100-pre, 210-flags-across-syscall, 300-effect-handlers,
# 310-effect-unhandled, 320-effect-gc-roots - and the largest partly
# unpinned remainders are 330-utf8 (18 of 23 lines), 030-str (12 of 19)
# and 250-field-kinds (11 of 16). Three cases name no exit status in
# their source: 050-file-io and 310-effect-unhandled, whose `main` ends
# in a branch and in a trap, and 340-json, which returns its own failure
# count.
#
# That is the honest number, and it is the number that moved. Before the
# self-grading claims, the derived exit statuses and the two extractor
# repairs below, it was 199 of 546 lines (36.4%) corruptible and 0 of 37
# exit statuses derived - and inside that region a defective compiler was
# re-blessed to a clean pass. See the drill.
#
# DRILLED, TWICE, RATHER THAN ASSUMED
#
# At conversion time: a compiler built from a copy of self_host/ with
# `>>` lowered to `lshr` instead of `ashr` was used to re-bless the whole
# corpus, so every `cmp` in this script passed - "37 of 37 cases match
# their golden" - and the gate still exited 1, twice: once on the goldens
# before compiling, once on what the programs printed.
#
# That drill left a hole this one closes. `340-json` was 56 golden lines
# and NO claim, so it was checked by `cmp` alone. Ablating one token of
# `stdlib/Json.ax` - `jpHexVal`'s lowercase-hex branch, `(- b 97)` to
# `(- b 96)`, so every lowercase digit of a `\uXXXX` escape decodes one
# too high and a surrogate pair stops being one - and re-blessing
# `340-json.out` and `340-json.exit` from that build made this gate print
# "37 of 37 cases match their golden" and "all checks passed", exit 0,
# with a checked-in golden that reads "FAIL surrogate pair length got=6
# want=4" and "failures 2". Measured, in a full-tree copy: EXIT=0.
#
# The same ablation, the same re-blessed corpus, against this script as
# it now stands: EXIT=1, and both halves fire.
#
#   FAIL 340-json: 340-json.ax grades itself, and 2 line(s) of
#        tests/stdlib/340-json.out begin with 'FAIL ': FAIL surrogate
#        pair length got=6 want=4
#   FAIL 340-json: harness at 340-json.ax:111 claims 'ok   surrogate
#        pair length', and no such line remains
#   FAIL goldens: only 0 self-graded check lines claimed; the floor is 50
#   ...
#   37 of 37 cases match their golden; 73 case-and-level runs
#
# `cmp` still passes - it is comparing the wrong compiler with its own
# output - and the fixture's own verdict refuses it, once before any
# compiler is built and once against what the programs printed.
#
# TWO THINGS THAT WERE SILENTLY COUNTING NOTHING
#
#   - The verifier blanked each string or char literal to a SINGLE space
#     and then sliced the RAW line at an offset it had found in the
#     masked one, so every annotation on a line containing a literal was
#     read at the wrong column: `(describe (CChar 'K'))  ; 75` handed
#     back `; 75`, which is not a number, and the claim was dropped.
#     Length-preserving masking, plus accepting any CALL on the line
#     rather than only a `println*` - the value a case documents sits
#     beside the call that produces the line, which for a multi-line
#     print is the closing paren - took the corpus from 351 claims over
#     26 files to 446 over 30: 300-process 0 claims to 9, 250-field-kinds
#     0 to 5, 165-arena-keep 0 to 4, 160-arena 3 to 8, 090-intern 33 to
#     50, and 340-json 0 to 54 from the self-grading class.
#   - The distinct-exit floor counted `42` from one case running into `0`
#     from the next as the distinct status `420`, so it was not counting
#     statuses at all. See `expected_exit_of`. With that fixed the corpus
#     has exactly three - 0, 42 and 71 - and re-blessing
#     `310-effect-unhandled.exit` from 71 to 0, which is what an ablated
#     compiler that stopped trapping unhandled effects wants, leaves two
#     and trips the floor.
#
# PROVENANCE, RECORDED WHILE BOTH COMPILERS STILL EXIST
#
# Measured at conversion time, with stage0 still in the tree: stage0 and
# the self-hosted compiler each reproduce all 37 goldens byte for byte
# through this same raw `llc` pipeline, at -O0 and at -O2, with one
# exception, `320-effect-gc-roots` - see NEEDS_TCO below. No new golden
# was materialized, because none was needed: the corpus already carried
# 37 `.out` files and 2 `.exit` files, and check 2 reads sources.
#
# WHAT LEFT THIS GATE
#
# The old sweep also ran `tests/selfhost/[0-9]*.ax`, purely to make
# `check-self-host.sh`'s `; expect N` check three-way (expect == stage0
# == stage1). With stage0 gone the third leg is gone, and what remains -
# stage1's exit status against the number written in the case's own first
# line - is exactly what `check-self-host.sh` already does. Running it
# here a second time would be repetition, not coverage. The 13 cases the
# old script listed under STAGE0_CANNOT were skipped only because stage0
# could not resolve `self_host/` imports; that list is now meaningless
# and is deleted rather than left to rot.
#
# `llc` carries an explicit relocation model, which the project requires
# of every `llc` invocation. It deliberately does NOT carry -O0 globally:
# both levels are run, because the hazards pull in opposite directions
# and each has hidden a real bug - at -O1 and above an undeclared
# inline-asm clobber broke the bump allocator, and at -O0 there is no
# tail-call elimination, so deep recursion overflows.
#
# Usage:
#   scripts/check-stdlib-selfhost.sh          # every case
#   scripts/check-stdlib-selfhost.sh 080      # one case, by name prefix
#
# A prefix that selects nothing is a failure, not a quiet pass: measured,
# `scripts/check-stdlib-selfhost.sh zzz-no-such-case` used to build a
# compiler, compile nothing, run nothing, verify nothing and exit 0.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

filter="${1:-}"

corpus="tests/stdlib"
verifier="$corpus/verify-stdlib-out.py"
failed=0

# Deep non-tail recursion that only fits on a stack once LLVM has done
# tail-call elimination. `320-effect-gc-roots` churns 200,000 allocations
# through `churn`, whose self call sits in a `let` body - which the
# compiler does not treat as tail position. Through a raw `llc` pipeline
# that is a real 200,000-frame chain: measured at conversion time, the
# self-hosted compiler's binary exits 139 at -O0 and 0 at -O2, and
# stage0's exited 139 at both. `axiom build` runs `opt` and the case is
# fine, which is the configuration users get and the one
# `run-stdlib-tests.sh` covers. Run here at -O2 only, and listed by name
# so that a file joining or leaving the list is a deliberate edit - the
# older spelling of this exemption skipped the case at every level.
NEEDS_TCO="320-effect-gc-roots"

in_list() { case " $2 " in *" $1 "*) return 0;; *) return 1;; esac; }

# One status, one LINE. `tr -d '[:space:]'` also deletes the trailing
# newline, and the only caller that reads more than one status at a time
# pipes them into `sort -u` - where `42` from one case ran into `0` from
# the next and was counted as the distinct status `420`. That is why the
# distinct-exit floor was satisfied by a corpus that had lost a status:
# it was not counting statuses at all.
expected_exit_of() {
  if [[ -f "$corpus/$1.exit" ]]; then
    printf '%s\n' "$(tr -d '[:space:]' < "$corpus/$1.exit")"
  else
    echo 0
  fi
}

# ---------------------------------------------------------------
# the corpus itself, before any compiler is involved
# ---------------------------------------------------------------
echo "== corpus: the goldens are present, distinguishable, and not empty =="
cases=0
for case_file in $corpus/*.ax; do
  name="$(basename "$case_file" .ax)"
  cases=$((cases + 1))
  if [[ ! -f "$corpus/$name.out" ]]; then
    echo "FAIL $name: no $corpus/$name.out - a case with no golden is a case nothing checks"
    failed=$((failed + 1))
    continue
  fi
  # An empty golden is only meaningful for a program that did not reach
  # its first print. A case that exits 0 with nothing on stdout cannot be
  # told apart from a binary that did nothing at all, which is exactly
  # what a failed build leaves behind.
  if [[ ! -s "$corpus/$name.out" && "$(expected_exit_of "$name")" == 0 ]]; then
    echo "FAIL $name: an empty golden with expected exit 0 asserts nothing"
    failed=$((failed + 1))
  fi
  ex="$(expected_exit_of "$name")"
  if [[ ! "$ex" =~ ^[0-9]+$ ]]; then
    echo "FAIL $name: $corpus/$name.exit is not a number ($ex)"
    failed=$((failed + 1))
  fi
done

if [[ "$cases" -lt 35 ]]; then
  echo "FAIL: found only $cases cases in $corpus (expected 37) - a glob or a tree is missing"
  failed=$((failed + 1))
fi

# A corpus of identical goldens would be satisfied by a compiler that
# emits one program, and a corpus with one expected exit status would be
# satisfied by a runner that never reads the status at all.
distinct_goldens="$(shasum $corpus/*.out | awk '{print $1}' | sort -u | wc -l | tr -d ' ')"
distinct_exits="$(for f in $corpus/*.ax; do expected_exit_of "$(basename "$f" .ax)"; done | sort -u | wc -l | tr -d ' ')"
if [[ "$distinct_goldens" -lt 30 ]]; then
  echo "FAIL: the $cases goldens take only $distinct_goldens distinct values"
  failed=$((failed + 1))
fi
# Three, not two: an ablated compiler that stopped trapping unhandled
# effects was re-blessed by rewriting `310-effect-unhandled.exit` from 71
# to 0, and a floor of 2 did not notice a whole expected status leaving
# the corpus. The three are 0, 42 (060-exit-code) and 71 (310).
if [[ "$distinct_exits" -lt 3 ]]; then
  echo "FAIL: the $cases cases expect only $distinct_exits distinct exit statuses (expected 3) - a status left the corpus"
  failed=$((failed + 1))
fi
echo "ok   $cases cases, $distinct_goldens distinct goldens, $distinct_exits distinct expected exit statuses"

# ---------------------------------------------------------------
# the goldens against the sources - no compiler needed
# ---------------------------------------------------------------
echo "== goldens: every value the sources claim is in the golden that claims it =="
[[ -f "$verifier" ]] || { echo "FAIL: $verifier is missing"; exit 1; }
if ! python3 "$verifier" "$corpus" "$corpus" --label goldens --quiet; then
  echo "FAIL: a checked-in golden disagrees with its own source - a re-blessed golden"
  failed=$((failed + 1))
fi

# ---------------------------------------------------------------
# the compiler under test
# ---------------------------------------------------------------
# Built FROM SOURCE by `$axiom`, not `$axiom` itself: this gate exists to
# test the tree, and `$axiom` may be a seed-descended binary that
# predates the change being tested.
#
# It runs from `$work` with `stdlib`, `self_host` and `tests` reachable,
# because a legacy CWD-relative entry in the module search is how the
# compile harnesses resolve `(import Foo)`. Cases are still handed their
# REAL path: the module search directory is derived from the argument,
# and `150-qualified-modules` imports `Q.Inner`, which is
# `tests/stdlib/Q/Inner.ax` and does not exist beside a copy.
echo "== building the compiler under test =="
ln -s "$repo_root/stdlib" "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"
ln -s "$repo_root/tests" "$work/tests"
gate_build_axc axc

mkdir -p "$work/observed" "$work/ir"

# ---------------------------------------------------------------
# the sweep
# ---------------------------------------------------------------
echo "== cases: compiled, run, and checked against the goldens at -O0 and -O2 =="
passed=0; ran=0; runs=0
for case_file in $corpus/*.ax; do
  name="$(basename "$case_file" .ax)"
  [[ -n "$filter" && "$name" != "$filter"* ]] && continue

  golden="$corpus/$name.out"
  [[ -f "$golden" ]] || continue
  want_exit="$(expected_exit_of "$name")"

  levels="-O0 -O2"
  if in_list "$name" "$NEEDS_TCO"; then
    levels="-O2"
  fi

  # A case that does not BUILD fails here. It must never fall through to
  # a comparison, because a build that produced nothing and a program
  # that printed nothing look the same to `cmp` when the golden is empty.
  (cd "$work" && ./axc "$repo_root/$case_file" >"$work/ir/$name.ll" 2>"$work/ir/$name.err")
  emit_status=$?
  if [[ "$emit_status" != 0 ]]; then
    echo "FAIL $name (the compiler refused it; exit $emit_status)"
    head -4 "$work/ir/$name.err" | sed 's/^/     /'
    failed=$((failed + 1))
    continue
  fi
  if [[ ! -s "$work/ir/$name.ll" ]]; then
    echo "FAIL $name (the compiler exited 0 and emitted no IR)"
    failed=$((failed + 1))
    continue
  fi

  ok=1
  why=""
  for opt in $levels; do
    if ! llc "$opt" -filetype=obj -relocation-model=pic "$work/ir/$name.ll" \
         -o "$work/ir/$name$opt.o" 2>"$work/ir/$name$opt.llc.err"; then
      ok=0; why="$why $opt(llc rejected the IR)"
      continue
    fi
    if ! cc "$work/ir/$name$opt.o" -o "$work/ir/$name$opt.bin" -e _main \
         2>"$work/ir/$name$opt.cc.err"; then
      ok=0; why="$why $opt(cc could not link it)"
      continue
    fi

    # Its own directory per level: several cases create files, and a
    # leftover from a previous run would make a failure look like a pass.
    rundir="$work/run/$name$opt"
    mkdir -p "$rundir"
    (cd "$rundir" && "$work/ir/$name$opt.bin" >stdout.txt 2>stderr.txt); got_exit=$?
    runs=$((runs + 1))

    if [[ -s "$golden" && ! -s "$rundir/stdout.txt" ]]; then
      ok=0; why="$why $opt(printed nothing at all)"
    elif ! cmp -s "$golden" "$rundir/stdout.txt"; then
      ok=0; why="$why $opt(stdout differs from $name.out)"
      diff "$golden" "$rundir/stdout.txt" 2>/dev/null | head -6 | sed 's/^/     /'
    fi
    if [[ "$got_exit" != "$want_exit" ]]; then
      ok=0; why="$why $opt(exit $got_exit, expected $want_exit)"
    fi

    # What the derived half will read. Written only after a real run, so
    # a case that failed to build leaves no observed output and is
    # reported by the verifier as unchecked rather than as agreeing. The
    # status goes beside the output, because the verifier derives that
    # from the source too and `NAME.exit` is as re-blessable as `NAME.out`.
    cp "$rundir/stdout.txt" "$work/observed/$name.out"
    printf '%s\n' "$got_exit" > "$work/observed/$name.exit"
  done

  ran=$((ran + 1))
  if [[ "$ok" == 1 ]]; then
    echo "ok   $name"
    passed=$((passed + 1))
  else
    echo "FAIL $name:$why"
    failed=$((failed + 1))
  fi
done

echo
echo "$passed of $ran cases match their golden; $runs case-and-level runs"

# ---------------------------------------------------------------
# the half a re-bless cannot satisfy
# ---------------------------------------------------------------
echo "== output: every value the sources claim, against what the programs printed =="
if [[ -n "$filter" ]]; then
  # One case cannot meet corpus-wide floors; the floors are checked on
  # the goldens above, which a filter does not narrow. `--filter` is what
  # keeps the relaxation from becoming a hole: the verifier then knows
  # which cases were ASKED for, and a case that was asked for and left no
  # output is a failure rather than a note. Before that, mistyping a case
  # name compiled nothing, ran nothing, checked nothing and exited 0.
  python3 "$verifier" "$corpus" "$work/observed" --label filtered --filter "$filter" \
    --min-files 0 --min-claims 0 --min-distinct 0 --min-harness 0 --min-exits 0 \
    || { echo "FAIL: what the program printed disagrees with its own source"; failed=$((failed + 1)); }
else
  if ! python3 "$verifier" "$corpus" "$work/observed" --label output --quiet; then
    echo "FAIL: what the programs printed disagrees with the sources they were compiled from"
    failed=$((failed + 1))
  fi
fi

# A gate that quietly stops comparing reports the same silence as one
# that compares everything and finds nothing wrong. A glob that stops
# matching, a tree that moves, an exemption list that grows - all of them
# look like success.
if [[ -z "$filter" ]]; then
  if [[ "$ran" -lt 35 ]]; then
    echo "FAIL: ran only $ran cases (expected 37) - a glob or a tree is missing"
    failed=$((failed + 1))
  fi
  if [[ "$runs" -lt 70 ]]; then
    echo "FAIL: only $runs case-and-level runs (expected 73) - an optimisation level stopped running"
    failed=$((failed + 1))
  fi
elif [[ "$ran" -lt 1 || "$runs" -lt 1 ]]; then
  echo "FAIL: '$filter' selected no case - nothing was compiled and nothing was run"
  failed=$((failed + 1))
fi

echo
if [[ "$failed" -eq 0 ]]; then
  echo "stdlib-selfhost: all checks passed"
else
  echo "stdlib-selfhost: $failed check(s) failed"
  exit 1
fi
