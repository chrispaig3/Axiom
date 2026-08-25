#!/usr/bin/env bash
# What an arena reset costs, and the comparison nothing in this
# repository made.
#
# MM-LIFE-2a, docs/memory-model.md's open-issue table, in its own
# words: "the withdrawn strategy's landed half charges every arena
# reset 4,097 slab-head stores - on the once-per-request path of
# MM-ALLOC-22's workload - because releases file blocks into those
# heads. No gate measures it, and with the strategy withdrawn the cost
# belongs to no plan." And at :1712: "no gate anywhere in this
# repository compares a reset carrying the scrub against one without
# it ... not that the cost is unknown, but that nothing would notice it
# changing."
#
# This is that comparison. It is also the roadmap's P8 - "performance
# is defended by a gate" - which was ungated for a reason worth
# restating: every timing gate here asserts a RATIO, deliberately, so
# that a slow runner cannot fail it, and a rate is not a ratio. The way
# out is to make the rate a ratio anyway, by measuring the same program
# twice in two spellings ONE WORD apart and asserting they disagree -
# which is `check-container-reclaim.sh`'s pattern applied to a clock
# instead of to RSS.
#
# THREE ARMS, so the cost is ATTRIBUTED rather than merely observed:
#
#   live      `(let ((m __axiom_arena_mark)) { ... (__axiom_arena_reset m) })`
#   noreset   the same, with the reset spelled `(+ 0 0)` - one word
#   nomark    the same again, with the mark spelled `0`
#
# `live - noreset` is the reset. `noreset - nomark` is the mark. Two
# subtractions rather than one ratio, because a single pair cannot say
# whether the difference it sees is the thing it named.
#
# AND A HALF WITH NO CLOCK IN IT AT ALL. The timing arms say the reset
# is expensive; they do not say WHY, and a gate that only timed things
# would go green if the scrub were replaced by something equally slow.
# So the emitted IR is read directly: the reset opens with a
# `slabclear` loop bounded at 4,097 doing exactly one store per
# iteration. That is the number `docs/memory-model.md` states in five
# places, asserted against the emitter rather than against prose.
#
# THE NEGATIVE PROBE ABLATES THE CAUSE, not the measurement. The
# `slabclear` block is deleted from the emitted IR and the binary
# rebuilt from the mutation with the same `llc` and `cc` - so the only
# difference between the two executables is the scrub - and the live
# arm's cost must collapse to the ablated arm's. Without it, "live is
# 45x noreset" is a fact about two programs and not about the scrub.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

command -v llc >/dev/null || { echo "FAIL: llc is not on PATH"; exit 1; }
command -v cc  >/dev/null || { echo "FAIL: cc is not on PATH"; exit 1; }
command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH"; exit 1; }

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# One million iterations. Derived, not guessed: the reset costs about
# 1.3 us, so a million of them is over a second - three orders of
# magnitude above the ~2 ms of process start-up that every arm pays
# equally, and far enough above scheduler noise that the best of five
# runs is stable to within a percent. At 200,000 the same measurement
# put the ratio at 12x rather than 45x, because start-up had not
# become negligible; that is the number this one exists not to report.
N=1000000
REPS=5

probe() {  # <name> <mark-expr> <reset-expr>
  cat > "$work/$1.ax" <<AX
(import IO)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let (
    (mut i 0)
    (mut acc 0)
  )
    {
      (while (< i $N)
        (let ((m $2))
          {
            (set acc (+ acc 1))
            $3
            (set i (+ i 1))
          }
        )
      )
      (println "{acc}")
      0
    }
  )
)
AX
  if ! "$axc" build --input "$work/$1.ax" --output "$work/$1" >"$work/$1.build" 2>&1; then
    echo "FAIL: could not build the $1 probe"; sed 's/^/     /' "$work/$1.build" | head -10; exit 1
  fi
}

# Best of REPS. The distribution is one-sided - interference only ever
# makes a run slower - so the minimum is the closest estimate of the
# cost itself. This is `check-name-scale.sh`'s methodology and
# `bench-datastructures.sh`'s before it.
#
# AND IT IS THE FIFTH COPY OF THAT LOOP, which is worth saying out loud
# rather than leaving for someone to notice. `scripts/lib/gate.sh`
# exists to remove exactly this kind of duplication, and it does not
# take this one on purpose: its own header says what it deliberately
# does NOT hold - "anything that runs the compiler, counts cases or
# reports results" - and a timer runs things and reports a number. The
# four copies differ in what they run and in what they refuse (this one
# refuses a non-zero exit; `check-name-scale.sh` also refuses a run
# that printed no `OK`), which is the case that file makes for leaving
# what differs where the reader will find it.
# The answer travels through a FILE and not a variable: this runs
# inside `$( )`, which is a subshell, and a variable set there does not
# reach the caller. The first version set `ANSWER` and read it back as
# an unbound variable on the very next line.
best_ms() {  # <binary> -> milliseconds; the program's answer lands in $work/answer
  local bin="$1" i s e t best="" out rc
  for (( i = 0; i < REPS; i++ )); do
    s=$(python3 -c 'import time;print(time.monotonic())')
    out="$( "$bin" )"; rc=$?
    e=$(python3 -c 'import time;print(time.monotonic())')
    if (( rc != 0 )); then
      echo "FAIL: $bin exited $rc - this gate measured a failure, not a workload" >&2
      exit 1
    fi
    t=$(python3 -c "print(($e - $s) * 1000)")
    if [[ -z "$best" ]] || (( $(python3 -c "print(1 if $t < $best else 0)") )); then best="$t"; fi
  done
  printf '%s' "$out" > "$work/answer"
  printf '%s' "$best"
}

# --------------------------------------------------------------------
echo "== three spellings of one program, $N iterations =="
# --------------------------------------------------------------------
probe live    '__axiom_arena_mark' '(__axiom_arena_reset m)'
probe noreset '__axiom_arena_mark' '(+ 0 0)'
probe nomark  '0'                  '(+ 0 0)'

t_live="$(best_ms "$work/live")";       a_live="$(cat "$work/answer")"
t_nores="$(best_ms "$work/noreset")";   a_nores="$(cat "$work/answer")"
t_nomark="$(best_ms "$work/nomark")";   a_nomark="$(cat "$work/answer")"
printf '     live    %10.2f ms\n     noreset %10.2f ms\n     nomark  %10.2f ms\n' \
  "$t_live" "$t_nores" "$t_nomark"

# THE ARMS MUST BE THE SAME PROGRAM. Three spellings that answered
# different numbers would be three workloads, and the differences
# between them would mean nothing.
if [[ "$a_live" == "$a_nores" && "$a_nores" == "$a_nomark" && "$a_live" == "$N" ]]; then
  ok "all three arms answer $a_live, so they are the same workload"
else
  bad "the arms answered '$a_live', '$a_nores', '$a_nomark' - wanted $N from each"
fi

# --------------------------------------------------------------------
echo
echo "== the reset costs, and the mark does not =="
# --------------------------------------------------------------------
ratio="$(python3 -c "print($t_live / max($t_nores, 0.001))")"
per_us="$(python3 -c "print(($t_live - $t_nores) * 1000 / $N)")"
mark_ns="$(python3 -c "print(($t_nores - $t_nomark) * 1000000 / $N)")"
printf '     reset %s us each, mark %s ns each, live/noreset %s x\n' \
  "$(printf '%.3f' "$per_us")" "$(printf '%.1f' "$mark_ns")" "$(printf '%.1f' "$ratio")"

# A FLOOR OF 10, against a measured 45. The margin is deliberate: this
# gate must not go red because a runner is busy, and the failure it is
# for - the scrub becoming free, or becoming ten times worse - moves
# this number by more than a factor of four.
if (( $(python3 -c "print(1 if $ratio >= 10 else 0)") )); then
  ok "a reset costs $(printf '%.1f' "$ratio")x the same loop without one (floor 10)"
else
  bad "live/noreset is $(printf '%.1f' "$ratio")x, below the floor of 10"
  echo "     Either the scrub stopped happening, or this measurement stopped working."
fi
# And the mark is NOT the cost, which is the attribution the two
# subtractions buy. If this ever failed, `per_us` above would be
# measuring the wrong half.
if (( $(python3 -c "print(1 if $mark_ns < $per_us * 1000 / 10 else 0)") )); then
  ok "the mark is under a tenth of the reset, so the reset is what was measured"
else
  bad "the mark costs $(printf '%.1f' "$mark_ns") ns against the reset's $(printf '%.3f' "$per_us") us"
fi

# --------------------------------------------------------------------
echo
echo "== with no clock in it: the scrub the emitter writes =="
# --------------------------------------------------------------------
"$axc" emit-llvm "$work/live.ax" -o "$work/live.ll" >/dev/null 2>&1
if ! grep -q '^slabclear:' "$work/live.ll"; then
  bad "the emitted IR has no \`slabclear\` block"
else
  body="$(sed -n '/^slabclear:/,/^resetbody:/p' "$work/live.ll")"
  stores="$(printf '%s' "$body" | grep -c 'store i64 0, ptr %sp' || true)"
  bound="$(printf '%s' "$body" | grep -oE 'icmp eq i64 %si1, [0-9]+' | grep -oE '[0-9]+$' || true)"
  width="$(grep -oE '@__axiom_slabs = internal global \[[0-9]+ x i64\]' "$work/live.ll" | grep -oE '[0-9]+' | head -1 || true)"
  if [[ "$stores" == 1 && "$bound" == 4097 && "$width" == 4097 ]]; then
    ok "the scrub is one store per iteration, bounded at $bound, over a [$width x i64] array"
  else
    bad "the scrub reads: $stores store(s), bound '$bound', array width '$width'"
    echo "     docs/memory-model.md states 4,097 in five places; this is the emitter's answer."
  fi
fi

# --------------------------------------------------------------------
echo
echo "== negative probe: delete the scrub from the IR, and the cost goes =="
# --------------------------------------------------------------------
# The mutation is on the EMITTED IR rather than on the compiler, so the
# two binaries differ in the scrub and in nothing else - same emitter,
# same `llc`, same `cc`. A rebuild of the compiler would also work and
# would cost a hundred seconds.
python3 - "$work/live.ll" "$work/noscrub.ll" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
# `br label %slabclear` ... through the end of the slabclear block:
# replace the whole thing with a direct branch to what follows.
out, n = re.subn(
    r"  br label %slabclear\n slabclear:.*?br i1 %sdone, label %resetbody, label %slabclear\n",
    "  br label %resetbody\n",
    src, flags=re.S)
if n == 0:
    out, n = re.subn(
        r"  br label %slabclear\nslabclear:.*?br i1 %sdone, label %resetbody, label %slabclear\n",
        "  br label %resetbody\n",
        src, flags=re.S)
open(sys.argv[2], "w").write(out)
if n != 1:
    sys.exit("the slabclear ablation matched %d times, wanted 1" % n)
PY
if ! grep -q '^slabclear:' "$work/noscrub.ll"; then
  llc -filetype=obj -relocation-model=pic "$work/noscrub.ll" -o "$work/noscrub.o" 2>"$work/llc.err" \
    && cc "$work/noscrub.o" -o "$work/noscrub" -e _main 2>"$work/cc.err"
  if [[ -x "$work/noscrub" ]]; then
    t_nos="$(best_ms "$work/noscrub")"; a_nos="$(cat "$work/answer")"
    printf '     noscrub %10.2f ms  answer=%s\n' "$t_nos" "$a_nos"
    if [[ "$a_nos" != "$N" ]]; then
      bad "the ablated binary answered '$a_nos' - it is not the same program"
    else
      collapse="$(python3 -c "print($t_live / max($t_nos, 0.001))")"
      if (( $(python3 -c "print(1 if $collapse >= 10 else 0)") )); then
        ok "deleting the scrub makes it $(printf '%.1f' "$collapse")x faster, so the scrub is the cost"
      else
        bad "deleting the scrub changed the cost by only $(printf '%.1f' "$collapse")x"
        echo "     Then something other than the scrub is what the arms above measured."
      fi
    fi
  else
    bad "could not build the ablated binary"
    head -3 "$work/llc.err" "$work/cc.err" 2>/dev/null | sed 's/^/     /'
  fi
else
  bad "the ablation did not remove the slabclear block - its shape has moved"
fi

# --------------------------------------------------------------------
echo
echo "== what it costs a request =="
# --------------------------------------------------------------------
# docs/memory-model.md:1691 says "under one percent" against a
# per-connection budget it states as 77 us. This derives the figure
# rather than asserting it, and it is a REPORT rather than a floor: the
# budget is a property of a workload, not of this gate.
pct="$(python3 -c "print($per_us / 77.0 * 100)")"
printf '     %s%% of the 77 us per-connection budget docs/memory-model.md states\n' "$(printf '%.2f' "$pct")"
if (( $(python3 -c "print(1 if $pct < 10 else 0)") )); then
  ok "the reset is under a tenth of a request (ceiling 10%, measured $(printf '%.2f' "$pct")%)"
else
  bad "the reset is $(printf '%.2f' "$pct")% of a request, over the ceiling of 10%"
fi

echo
if (( failed > 0 )); then
  echo "check-arena-reset-rate: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-arena-reset-rate: $checks checks - the reset costs"
echo "                        $(printf '%.3f' "$per_us") us, the scrub is what costs it, and"
echo "                        deleting it from the IR takes the cost away"
