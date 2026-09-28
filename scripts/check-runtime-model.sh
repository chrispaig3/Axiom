#!/usr/bin/env bash
# The runtime against an executable model of its own rules.
#
# `scripts/lib/runtime-model.py` is a second, independent statement of
# what the allocator, the arena (mark/reset), lexical regions and the
# block header's count word do - written from docs/memory-model.md
# (MM-ALLOC-3/6/7a/8b/12/14, MM-LIFE-2b/2d/2e/2k/2l, MM-RGN-1/2/6), not
# transliterated from the IR. It drives itself through fixed witness
# traces and seeded random traces and writes each one out as an Axiom
# program whose every step is followed by the model's prediction of
# every observable word: the handle's offset and alignment, its count
# and shape words, its payload, the bump pointer, the mark cell, and
# after a reset the bytes the reset reclaimed. This gate compiles each
# program with the compiler under test, runs it, and requires the
# runtime to agree at every check. Its docstring states the invariants,
# the scope and - at more length - the NON-scope.
#
# SIX SECTIONS.
#
#   1. The model alone: many seeds, every invariant after every step.
#      Says nothing about the runtime; says the generator is valid.
#   2. Every trace at --opt 0 and --opt 3 (all four under --long):
#      stdout `0 0` (first failing check, failures) and the trace's exit
#      status - 0, or for a terminal trace the trap's 70 and its sentence.
#   3. The canary: a trace whose model is deliberately wrong at ONE
#      check must report exactly that check and exactly one failure.
#      Without it, "every check passed" could mean "no check can fail".
#   4. The hand pipeline's control: the witness IR, emitted by the
#      compiler under test and built by THIS script through the
#      driver's own opt/llc/cc steps at -O1, must still pass - so the
#      ablations in 5 are red because of what they change, not because
#      the hand pipeline differs from the driver's.
#   5. Six mutation witnesses, each rewriting ONE rule in the emitted
#      runtime and required to turn its witness trace red at a named
#      check: `dead` (MM-LIFE-2k: a stray release decrements a filed
#      block's link), `reset` (MM-LIFE-2e: no slab scrub), `scrub`
#      (MM-ALLOC-6: no handout wipe), `region` (MM-RGN-1: a region's
#      exit forgets its reset), `exhaust` (MM-LIFE-2l: no count-limit
#      trap, so the count wraps), `classes` (MM-ALLOC-25: requests keep
#      their exact size, so a block born above 1 KiB is off its class).
#      `reset` goes red at the filed-bytes check first: the scrub it
#      deletes is also what zeroes MM-ALLOC-24's count.
#   6. The exhaustion boundary is a terminal trace in section 2.
#
# LIMITS, stated here because a green gate invites reading more into it:
# agreement on the traces run, at the levels run, on this host; one
# thread, one chunk, leaf blocks, valid marks. The model is not a proof
# of the runtime and the runtime passing is not a proof of the model.
#
# Usage: check-runtime-model.sh [--long] [--seeds S,S,...]
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

command -v llc >/dev/null || { echo "FAIL: llc is not on PATH"; exit 1; }
command -v opt >/dev/null || { echo "FAIL: opt is not on PATH"; exit 1; }
command -v cc  >/dev/null || { echo "FAIL: cc is not on PATH"; exit 1; }
command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH"; exit 1; }

long=0
seeds=""
while (( $# )); do
  case "$1" in
    --long) long=1 ;;
    --seeds) seeds="$2"; shift ;;
    *) echo "usage: $0 [--long] [--seeds S,S,...]" >&2; exit 2 ;;
  esac
  shift
done

model="$repo_root/scripts/lib/runtime-model.py"
failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

if (( long )); then levels="0 1 2 3"; selftest=2000; else levels="0 3"; selftest=200; fi

# ---------------------------------------------------------------------
echo "== 1. the model alone =="
if out="$(python3 "$model" selftest --seeds "$selftest" 2>&1)"; then
  ok "$out"
else
  bad "the model broke its own invariants:"; echo "$out" | sed 's/^/    /'
fi

# ---------------------------------------------------------------------
echo "== 2. every trace, compiled by the compiler under test =="
traces="$work/traces"
gen_args=(generate "$traces")
[[ -n "$seeds" ]] && gen_args+=(--seeds "$seeds")
(( long )) && gen_args+=(--long)
if ! summary="$(python3 "$model" "${gen_args[@]}" 2>&1)"; then
  bad "the generator failed:"; echo "$summary" | sed 's/^/    /'
  echo "check-runtime-model: $checks passed, $failed failed"; exit 1
fi
echo "   $summary"

# name expect_exit expect_stderr canary_check, one row per trace
python3 - "$traces/manifest.json" > "$work/rows" <<'PY'
import json, sys
for r in json.load(open(sys.argv[1])):
    print(r["name"], r["expect_exit"], r["canary_check"] or 0, r["expect_stderr"].replace(" ", "_") or "-")
PY

label() { python3 "$model" label "$traces" "$1" "$2"; }

# run_trace <name> <binary> -> sets $r_out (first stdout line), $r_rc, $r_err
run_trace() {
  r_out="" r_rc=0
  gate_timeout 60 "$2" > "$work/$1.out" 2> "$work/$1.err" || r_rc=$?
  r_out="$(head -1 "$work/$1.out")"
  r_err="$(head -1 "$work/$1.err")"
}

# verdict <name> <what> <expect_exit> <expect_stderr> : the trace agreed
verdict() {
  local name="$1" what="$2" want_rc="$3" want_err="${4//_/ }"
  if [[ "$r_out" == "0 0" && "$r_rc" == "$want_rc" ]] &&
     { [[ "$want_err" == "-" && -z "$r_err" ]] || [[ "$r_err" == "$want_err" ]]; }; then
    return 0
  fi
  local first="${r_out%% *}"
  if [[ "$first" =~ ^[0-9]+$ && "$first" != 0 ]]; then
    bad "$what: check $first disagreed ($(label "$name" "$first")); stdout '$r_out', exit $r_rc"
  else
    bad "$what: stdout '$r_out', exit $r_rc (want 0 0 / $want_rc), stderr '$r_err' (want '$want_err')"
  fi
  return 1
}

ntrace=0
while read -r name want_rc canary want_err; do
  [[ "$canary" != 0 ]] && continue
  for lvl in $levels; do
    bin="$work/$name.O$lvl"
    if ! "$axc" build --input "$traces/$name.ax" --output "$bin" --opt "$lvl" > "$work/$name.build" 2>&1; then
      bad "$name --opt $lvl did not build:"; sed 's/^/    /' "$work/$name.build" | head -12; continue
    fi
    run_trace "$name" "$bin"
    verdict "$name" "$name --opt $lvl" "$want_rc" "$want_err" && ntrace=$((ntrace + 1))
  done
done < "$work/rows"
ok "$ntrace trace builds agreed with the model at every check (levels: $levels)"

# ---------------------------------------------------------------------
echo "== 3. the canary: a deliberately wrong prediction is reported =="
read -r _ _ canary _ < <(grep '^canary ' "$work/rows")
if "$axc" build --input "$traces/canary.ax" --output "$work/canary" > "$work/canary.build" 2>&1; then
  run_trace canary "$work/canary"
  if [[ "$r_out" == "$canary 1" && "$r_rc" == 1 ]]; then
    ok "canary: check $canary ($(label canary "$canary")) and nothing else reported, exit 1"
  else
    bad "canary: stdout '$r_out' exit $r_rc, want '$canary 1' exit 1 - the harness cannot report a failure"
  fi
else
  bad "the canary did not build"
fi

# ---------------------------------------------------------------------
# The driver's pipeline, by hand (self_host/driver.ax runOpt and
# assembleAndLink): opt -O<n> -S, llc -filetype=obj -O<n>
# -relocation-model=pic, cc. `$link_entry` is gate.sh's.
hand_build() {  # <ll> <out> <level>
  local ll="$1" out="$2" lvl="$3" in="$1"
  if (( lvl > 0 )); then
    opt "-O$lvl" "$ll" -S -o "$out.opt.ll" 2> "$out.log" || return 1
    in="$out.opt.ll"
  fi
  llc "$in" -filetype=obj -o "$out.o" "-O$lvl" -relocation-model=pic 2>> "$out.log" || return 1
  cc "$out.o" -o "$out" $link_entry 2>> "$out.log"
}

echo "== 4. the hand pipeline's control =="
for w in dead reset scrub region exhaust classes; do
  if ! "$axc" emit-llvm "$traces/$w.ax" -o "$work/$w.ll" > "$work/$w.emit" 2>&1; then
    bad "$w: emit-llvm failed"; continue
  fi
  read -r _ want_rc _ want_err < <(grep "^$w " "$work/rows")
  if hand_build "$work/$w.ll" "$work/$w.hand" 1; then
    run_trace "$w" "$work/$w.hand"
    verdict "$w" "$w through the hand pipeline (unablated)" "$want_rc" "$want_err" \
      && ok "$w: the unablated IR built by hand agrees with the model"
  else
    bad "$w: the hand pipeline could not build the unablated IR"; sed 's/^/    /' "$work/$w.hand.log" | head
  fi
done

# ---------------------------------------------------------------------
echo "== 5. mutation witnesses: each ablated rule turns its trace red =="
# <kind> <the label prefix of the FIRST check that must disagree>
while read -r kind expect; do
  expect="${expect//_/ }"
  if ! python3 "$model" ablate "$kind" "$work/$kind.ll" "$work/$kind.ablated.ll" > "$work/$kind.ablate" 2>&1; then
    bad "$kind: the ablation did not apply: $(cat "$work/$kind.ablate")"; continue
  fi
  if cmp -s "$work/$kind.ll" "$work/$kind.ablated.ll"; then
    bad "$kind: the ablation changed nothing"; continue
  fi
  if ! hand_build "$work/$kind.ablated.ll" "$work/$kind.abl" 1; then
    bad "$kind: the ablated IR did not build"; sed 's/^/    /' "$work/$kind.abl.log" | head; continue
  fi
  run_trace "$kind" "$work/$kind.abl"
  first="${r_out%% *}"; nfail="${r_out##* }"
  if [[ "$kind" == exhaust ]]; then
    second="$(sed -n 2p "$work/$kind.out")"
    if [[ "$r_rc" != 70 && "$second" == "NO TRAP" ]]; then
      ok "exhaust: without the MM-LIFE-2l trap the retain past 2^63-1 returns (exit $r_rc, 'NO TRAP')"
    else
      bad "exhaust: ablated binary exited $r_rc with '$second' - the trace cannot see the trap go"
    fi
    continue
  fi
  if [[ "$first" =~ ^[0-9]+$ && "$first" != 0 ]]; then
    got="$(label "$kind" "$first")"
    if [[ "$got" == "$expect"* ]]; then
      ok "$kind: red at check $first ($got), $nfail checks failing, exit $r_rc"
    else
      bad "$kind: red at check $first ($got), expected the first failure at '$expect'"
    fi
  else
    bad "$kind: the ablated runtime still agreed (stdout '$r_out', exit $r_rc) - the witness is blind"
  fi
done <<'ROWS'
dead b_count_word_after_release
reset reset_outer:_filed_bytes_0
scrub b_zeroed_(MM-ALLOC-6)
region region_r2_exit
exhaust -
classes big_leaf_shape
ROWS

echo
echo "check-runtime-model: $checks passed, $failed failed"
(( failed == 0 ))
