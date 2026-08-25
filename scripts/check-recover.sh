#!/usr/bin/env bash
# Abort to an arena mark: the three traps are recoverable inside a
# recovery point and still stop the process outside one, and a hundred
# thousand aborts do not grow memory.
#
# `(__axiom_recover mark thunk)` arms a recovery point at `mark` and
# runs `thunk`. Out of memory (70), an unhandled effect (71) and a
# division by zero (72) then answer the arming call with their status
# instead of writing to fd 2 and exiting; with nothing armed they do
# exactly what they always did. This gate is what says both halves are
# true, and it exists as a separate script rather than as three more
# stdlib cases because two of its claims are not golden comparisons at
# all: one is a sweep over optimisation levels, and one is a
# measurement.
#
# WHY THE OPTIMISATION SWEEP IS NOT OPTIONAL. The mechanism is a
# `setjmp` written out in inline assembly, and the whole of its
# correctness rests on a clobber list telling LLVM that nothing
# survives the arm block in a register. That is exactly the kind of
# claim that is true at -O0 and false above it. Measured on
# darwin-aarch64 while writing the block, on a hand-written LLVM
# prototype of it, with `~{x30}` in the clobber list instead of
# `~{lr}`:
#
#     === -O0 ===   outer st=72 / inner st=72     EXIT=0
#     === -O1 ===   Segmentation fault: 11        EXIT=139
#     === -O2 ===   Segmentation fault: 11        EXIT=139
#     === -O3 ===   Segmentation fault: 11        EXIT=139
#
# LLVM silently ignores `x30` as an AArch64 clobber name and had
# parked `_top@PAGE` in x30 across the block. A gate that only built
# at the default -O1 would have caught that one; a gate that only
# built at -O0 would have shipped it. Every case here is built at all
# four levels the driver accepts.
#
# WHAT THE MEMORY MEASUREMENT IS FOR. The soundness argument for
# jumping past N frames of pending `axiom_release` calls is that the
# arena reset reclaims everything above the mark regardless of counts
# (docs/memory-model.md MM-ALLOC-13, MM-ALLOC-14) and scrubs all 4,097
# slab heads first so nothing filed survives to be double-issued
# (MM-LIFE-2e). If any of that were wrong the residue would show up as
# growth, so the loop below runs the abort a hundred thousand times
# and watches max RSS. It puts a `handle` INSIDE the aborted extent
# deliberately: that is the one shape the harmlessness argument does
# not cover, because `emitHandleDyn` takes a retain on the evidence
# record its push displaces - a record that may live BELOW the mark -
# and the `release` that returns it is at the pop the jump skips.
#
# A FLAT LINE ALSO READS FLAT WHEN THE MEASUREMENT IS BROKEN, so the
# flat run is paired with an ablated twin: the identical program with
# the trap removed, so the recovery point returns normally and nothing
# resets. It has to grow, and by a wide margin, or the flat number
# proves nothing about anything.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

status=0

# The only RSS helper in the tree lives in
# `scripts/measure-memory-baseline.sh`, and this is its shape, kept
# rather than shared for the reason that script gives about its own
# fallback: Darwin's `time -l` reports bytes and GNU's `time -v`
# reports kilobytes, and neither answering is a FAILURE rather than a
# skip - a measurement script that silently measures nothing is how
# the last RSS regression hid.
max_rss_kb() {
  if /usr/bin/time -l true >/dev/null 2>&1; then
    /usr/bin/time -l "$@" 2>&1 >/dev/null \
      | awk '/maximum resident set size/ {print int($1/1024)}'
  elif /usr/bin/time -v true >/dev/null 2>&1; then
    /usr/bin/time -v "$@" 2>&1 >/dev/null \
      | awk -F: '/Maximum resident set size/ {print int($2)}'
  else
    echo "FAIL: no usable time(1) for RSS measurement" >&2
    return 1
  fi
}

# ------------------------------------------------------------------
# 1. Each trap recovers inside a recovery point and still exits
#    outside one - at every optimisation level.
#
# The three cases are `tests/stdlib/40{0,1,2}-recover-*.ax` and their
# goldens are the ones `run-stdlib-tests.sh` already compares against,
# read here rather than restated: a second copy of an expectation is a
# second place for it to drift. What this adds is the compiler under
# test (that runner uses `$axiom`, which may predate the change) and
# the four optimisation levels (that runner uses the default only).
#
# Each case carries BOTH halves in one program on purpose. With
# `__axiom_recover` unreferenced the machinery is dead code - the
# helper is internal and deleted, no store to `@__axiom_recover_top`
# survives, and GlobalOpt folds the armed test in each trap to false -
# so a case that only trapped outside an extent would be testing a
# trap with no branch left in it.
# ------------------------------------------------------------------
echo "== the three traps, both positions, four optimisation levels =="
checked=0
for case_name in 403-recover-div 401-recover-effect 402-recover-oom; do
  src="tests/stdlib/$case_name.ax"
  [[ -f "$src" ]] || { echo "FAIL $case_name: no such case"; status=1; continue; }
  want_out="$(cat "tests/stdlib/$case_name.out")"
  want_err="$(cat "tests/stdlib/$case_name.err")"
  want_exit="$(tr -d '[:space:]' < "tests/stdlib/$case_name.exit")"
  for lvl in 0 1 2 3; do
    bin="$work/$case_name-O$lvl"
    if ! "$axc" build --input "$src" --output "$bin" --opt "$lvl" \
         >"$bin.build" 2>&1; then
      echo "FAIL $case_name -O$lvl: build"
      sed 's/^/    /' "$bin.build" | head -8
      status=1
      continue
    fi
    set +e
    got_out="$("$bin" 2>"$bin.stderr")"
    got_exit=$?
    set -e
    # `run-stdlib-tests.sh` compares stderr TRUNCATED at the backtrace
    # header - `sed '/^axiom: backtrace/q'` - because the frames below
    # it name functions and cannot be a golden. This script said it
    # read that runner's goldens and then compared the raw stream, so
    # every case with a `.err` would have failed on the backtrace it
    # was never meant to compare. Same `sed`, same claim.
    got_err="$(sed '/^axiom: backtrace/q' "$bin.stderr")"
    if [[ "$got_out" != "$want_out" ]]; then
      echo "FAIL $case_name -O$lvl: stdout"
      diff <(printf '%s\n' "$want_out") <(printf '%s\n' "$got_out") | sed 's/^/    /' || true
      status=1
      continue
    fi
    if [[ "$got_err" != "$want_err" ]]; then
      echo "FAIL $case_name -O$lvl: stderr (the trap outside the recovery point)"
      diff <(printf '%s\n' "$want_err") <(printf '%s\n' "$got_err") | sed 's/^/    /' || true
      status=1
      continue
    fi
    if [[ "$got_exit" != "$want_exit" ]]; then
      echo "FAIL $case_name -O$lvl: exit (expected $want_exit, got $got_exit)"
      status=1
      continue
    fi
    checked=$((checked + 1))
  done
done
echo "ok   $checked recovery cases recovered inside and exited outside"
# A sweep over an empty corpus reports the silence it was looking for.
if (( checked != 12 )); then
  echo "FAIL only $checked of 12 (3 cases x 4 levels) reached the comparison"
  status=1
fi

# ------------------------------------------------------------------
# 2. Nesting, and the frames in between.
#
# `MM-ALLOC-16a` requires marks to be reset innermost-first, so an
# abort takes the INNERMOST armed point and not the outermost - which
# is the difference between `inner caught 72 / outer saw 0` and an
# outer point swallowing a fault a nearer one had asked for. The same
# program then traps with only the outer point armed, and again from
# 5,000 non-tail frames down, which is the "jump past N frames" claim
# stated as a number.
# ------------------------------------------------------------------
echo "== nesting, and 5,000 frames abandoned =="
cat > "$work/nest.ax" <<'PROBE'
(import IO)

(import Mem)

(:: zero Int)

(fn (zero) 0)

(:: inner (-> Int Int))

(fn (inner x)
  {
    (memAlloc 512)
    (/ 1 zero)
  }
)

(:: descend (-> Int Int))

(fn (descend n)
  (if (<= n 0)
    (/ 1 zero)
    (+ 1 (descend (- n 1)))
  )
)

(:: middle (-> Int Int))

(fn (middle x)
  (let ((mi __axiom_arena_mark))
    (let ((a (__axiom_recover mi (lambda (y) (inner y)))))
      {
        (println "inner caught {a}")
        0
      }
    )
  )
)

(:: main Int)

(fn (main)
  (let ((mo __axiom_arena_mark))
    (let (
      (b (__axiom_recover mo (lambda (y) (middle y))))
      (c (__axiom_recover mo (lambda (y) (inner y))))
      (d (__axiom_recover mo (lambda (y) (descend 5000))))
    )
      {
        (println "outer saw {b}")
        (println "outer caught {c}")
        (println "deep {d}")
        0
      }
    )
  )
)
PROBE
nest_want='inner caught 72
outer saw 0
outer caught 72
deep 72'
nest_checked=0
for lvl in 0 1 2 3; do
  bin="$work/nest-O$lvl"
  if ! "$axc" build --input "$work/nest.ax" --output "$bin" --opt "$lvl" \
       >"$bin.build" 2>&1; then
    echo "FAIL nesting -O$lvl: build"
    sed 's/^/    /' "$bin.build" | head -8
    status=1
    continue
  fi
  set +e
  nest_got="$("$bin" 2>/dev/null)"
  nest_exit=$?
  set -e
  if [[ "$nest_got" != "$nest_want" || "$nest_exit" != 0 ]]; then
    echo "FAIL nesting -O$lvl (exit $nest_exit)"
    diff <(printf '%s\n' "$nest_want") <(printf '%s\n' "$nest_got") | sed 's/^/    /' || true
    status=1
    continue
  fi
  nest_checked=$((nest_checked + 1))
done
echo "ok   nesting takes the innermost armed point, at $nest_checked levels"
if (( nest_checked != 4 )); then
  echo "FAIL only $nest_checked of 4 optimisation levels reached the nesting comparison"
  status=1
fi

# ------------------------------------------------------------------
# 3. A hundred thousand aborts do not grow memory.
#
# `emit_abort_loop <count> <trap|no-trap> <file>` writes one program
# in two spellings that differ by ONE LINE. Both take a single mark
# outside the loop, allocate 4 KiB per iteration, and install a
# handler per iteration inside the extent - the `handle` is there
# because the retain it takes on the record it displaces is the one
# thing the arena's wholesale reclaim does not cover. `trap` divides
# by zero at the bottom, so every iteration aborts to the mark;
# `no-trap` answers 0 there, so the recovery point returns normally
# and nothing resets.
#
# The second is the ABLATED ARM. Its only purpose is to fail: a flat
# line is worthless evidence unless the same measurement, on the same
# program, can be shown reading a growing one.
# ------------------------------------------------------------------
emit_abort_loop() {
  local count="$1" variant="$2" out="$3" bottom
  case "$variant" in
    trap)    bottom='(/ 1 zero)' ;;
    no-trap) bottom='0' ;;
    *)       echo "FAIL emit_abort_loop: unknown variant $variant" >&2; return 1 ;;
  esac
  cat > "$out" <<PROBE
(import IO)

(import Mem)

(effect Console
  (log :: (-> String Int)))

(:: zero Int)

(fn (zero) 0)

(:: burn (-> Int Int))

(fn (burn x)
  (handle
    {
      (memAlloc 4096)
      (log "inner")
      $bottom
    }    (Console Alloc)    (lambda (s) 0)
  )
)

(:: spin (-> Int Int Int Int))

(fn (spin m n acc)
  (if (<= n 0)
    acc
    (spin m (- n 1) (+ acc (__axiom_recover m (lambda (y) (burn y)))))
  )
)

(:: main Int)

(fn (main)
  (handle
    (let (
      (m __axiom_arena_mark)
      (t (spin m $count 0))
    )
      {
        (println "{t}")
        0
      }
    )    (Console Alloc IO)    (lambda (s) 0)
  )
)
PROBE
}

echo "== 100,000 aborts, with a handle inside the aborted extent =="
build_probe() {
  local src="$1" bin="$2"
  if ! "$axc" build --input "$src" --output "$bin" >"$bin.build" 2>&1; then
    echo "FAIL could not build $(basename "$src")"
    sed 's/^/    /' "$bin.build" | head -8
    status=1
    return 1
  fi
}

emit_abort_loop 10000  trap    "$work/loop-10k.ax"
emit_abort_loop 100000 trap    "$work/loop-100k.ax"
emit_abort_loop 100000 no-trap "$work/loop-ablated.ax"

rss_10k=""; rss_100k=""; rss_ablated=""
# `set +e` around every one of these, and it is not caution. This
# script runs under `set -e`, and a bare `got="$(cmd)"` whose command
# exits non-zero takes the WHOLE SCRIPT down at that line - which is
# precisely what a broken recovery point makes these programs do: they
# exit 72 instead of printing a sum. Measured while ablating this
# gate: it died here with status 72, having printed its first two
# sections and no verdict at all, which reads as a broken gate rather
# than the red it is. `check-freestanding.sh` carries the same note
# over the same hazard.
#
# The sum is the assertion that the aborts HAPPENED: 100,000 x 72.
# Without it a program that silently stopped aborting would report a
# beautifully flat line.
sum_of() {
  local bin="$1" want="$2" label="$3" got rc
  set +e
  got="$("$bin" 2>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" != 0 || "$got" != "$want" ]]; then
    echo "FAIL $label summed to '$got' (exit $rc), not $want"
    status=1
    return 1
  fi
}

rss_of() {
  local bin="$1" kb
  set +e
  kb="$(max_rss_kb "$bin")"
  set -e
  printf '%s' "$kb"
}

if build_probe "$work/loop-10k.ax" "$work/loop-10k"; then
  sum_of "$work/loop-10k" 720000 "10,000 aborts" && rss_10k="$(rss_of "$work/loop-10k")"
fi
if build_probe "$work/loop-100k.ax" "$work/loop-100k"; then
  sum_of "$work/loop-100k" 7200000 "100,000 aborts" && rss_100k="$(rss_of "$work/loop-100k")"
fi
if build_probe "$work/loop-ablated.ax" "$work/loop-ablated"; then
  sum_of "$work/loop-ablated" 0 "the ablated twin" && rss_ablated="$(rss_of "$work/loop-ablated")"
fi

if [[ -z "$rss_10k" || -z "$rss_100k" || -z "$rss_ablated" ]]; then
  echo "FAIL one of the three RSS measurements produced no number"
  status=1
else
  echo "     10,000 aborts:  ${rss_10k} KiB"
  echo "     100,000 aborts: ${rss_100k} KiB"
  echo "     ablated (no abort, no reset, same allocations): ${rss_ablated} KiB"

  # FLAT, stated two ways. The ceiling is what a reader can check
  # against the numbers above; the delta is what survives a machine
  # whose baseline RSS is different from this one's. Measured on
  # darwin-aarch64 2026-08-24: 1376 KiB at both counts, byte for byte.
  if (( rss_100k > 32768 )); then
    echo "FAIL 100,000 aborts peaked at ${rss_100k} KiB, over the 32 MiB ceiling"
    status=1
  elif (( rss_100k - rss_10k > 4096 )); then
    echo "FAIL RSS grew ${rss_100k}-${rss_10k} KiB between 10,000 and 100,000 aborts"
    status=1
  else
    echo "ok   100,000 aborts hold RSS flat (${rss_10k} -> ${rss_100k} KiB)"
  fi

  # THE ABLATED ARM. Same program, same allocations, one line
  # different - and it must grow, or the flatness above is a claim
  # about a measurement that cannot see anything. Measured on
  # darwin-aarch64 2026-08-24: 406080 KiB against 1376, a factor of
  # 295. The bar is 8x and 64 MiB, far below what was seen and far
  # above any noise.
  if (( rss_ablated <= 65536 )) || (( rss_ablated < rss_100k * 8 )); then
    echo "FAIL the ablated twin peaked at ${rss_ablated} KiB against ${rss_100k} KiB:"
    echo "FAIL the measurement cannot see the growth it is supposed to refuse"
    status=1
  else
    echo "ok   ablated arm: the same program without the abort grows to ${rss_ablated} KiB"
  fi
fi

# ------------------------------------------------------------------
# 4. The emitted shape, at both ends.
#
# Two claims that are invisible in program output. First, that each of
# the three traps really does ask the recovery point before it writes
# its sentence - a trap that lost that call would still pass every
# comparison above in a program that never armed anything. Second,
# that a program which never arms one pays NOTHING: the helper is
# internal and unreferenced, so it is deleted, and with no store left
# to `@__axiom_recover_top` GlobalOpt folds the armed test to its
# initialiser and takes the arena reset in the abort path with it.
# ------------------------------------------------------------------
echo "== the emitted shape =="
# `401-recover-effect.ax` and not `400`: the unhandled-effect trap is
# emitted only for a module that DECLARES an effect, so a module
# without one would report that trap missing rather than unwired.
ir="$work/shape.ll"
"$axc" emit-llvm tests/stdlib/401-recover-effect.ax -o "$ir" >/dev/null \
  || { echo "FAIL could not emit IR for 401-recover-effect"; status=1; }
for fn in __axiom_out_of_memory __axiom_unhandled_effect __axiom_div_by_zero; do
  grep -q "define internal i64 @$fn()" "$ir" \
    || { echo "FAIL @$fn is not defined in the module at all"; status=1; }
done
traps_wired=0
for pair in "__axiom_out_of_memory:70" "__axiom_unhandled_effect:71" "__axiom_div_by_zero:72"; do
  fn="${pair%%:*}"; code="${pair##*:}"
  # The call is the first line of the trap's entry block, so the
  # window is small and fixed rather than "somewhere in the module".
  if awk -v f="define internal i64 @$fn()" '
        index($0, f) { seen = NR }
        seen && NR > seen && NR <= seen + 3 { print }' "$ir" \
       | grep -q "call i64 @__axiom_recover_abort(i64 $code)"; then
    traps_wired=$((traps_wired + 1))
  else
    echo "FAIL @$fn does not ask the recovery point before it exits $code"
    status=1
  fi
done
if (( traps_wired == 3 )); then
  echo "ok   all three traps ask the recovery point first"
else
  echo "FAIL only $traps_wired of 3 traps are wired to the recovery point"
  status=1
fi

# The negative half of the same check: a program that never arms a
# recovery point must carry no STATE, no CALL and no INSTRUCTION of
# this after `opt`. If `opt` is not on PATH the claim cannot be made,
# and saying so beats reporting a silence.
#
# THIS ASSERTION IS NOT "grep answers 0", and the first draft of it
# was. P1's symbol table takes the ADDRESS of every function the
# module defines, so `@__axiom_recover_abort` and the two slot helpers
# are address-taken by construction and GlobalDCE cannot delete them -
# their names sit in `@__axiom_symtab` and in three name constants
# beside it, in every program, whether or not it arms anything. A
# `left == 0` test can therefore never pass, and the honest repair is
# not to relax it to `left <= 7`, which asserts a count and not a
# property.
#
# What the mechanism costing nothing actually means, and what is
# asserted here, is three separable things, each with its own line:
#
#   1. `@__axiom_recover_top` is GONE. It is the mechanism's only
#      mutable state, and the arm site is its only writer, so with no
#      arm site GlobalOpt folds the load in the abort to the
#      initialiser and deletes the global. This is the check that
#      would catch a future change putting a store in the abort - the
#      shape the first implementation had, and the one that keeps the
#      global alive in every program that owns a trap.
#   2. No CALL to any of the three survives. That is the per-trap cost
#      the three `call i64 @__axiom_recover_abort` lines would
#      otherwise be, on the path every dying program takes.
#   3. Every surviving definition is EMPTY - `entry:` then `ret i64 0`.
#      Not "small": empty, which is what says the whole body folded
#      rather than shrank.
#
# Measured on `010-hello.ax`, darwin-aarch64, 2026-08-24: 14 lines
# mention the mechanism at -O0 and 7 at -O1, and all 7 are the symbol
# table's - three name constants, the `@__axiom_symtab` line, and the
# three one-instruction definitions it names.
if command -v opt >/dev/null 2>&1; then
  "$axc" emit-llvm tests/stdlib/010-hello.ax -o "$work/hello.ll" >/dev/null \
    || { echo "FAIL could not emit IR for 010-hello"; status=1; }
  raw="$(grep -c '__axiom_recover' "$work/hello.ll" || true)"
  opt -O1 "$work/hello.ll" -S -o "$work/hello.opt.ll" >/dev/null 2>&1 \
    || { echo "FAIL \`opt -O1\` refused the module"; status=1; }
  left="$(grep -c '__axiom_recover' "$work/hello.opt.ll" || true)"
  if (( raw < 5 )); then
    echo "FAIL the unoptimised module carries only $raw recovery lines - nothing to delete"
    status=1
  else
    zero=0
    state="$(grep -c '__axiom_recover_top' "$work/hello.opt.ll" || true)"
    if (( state != 0 )); then
      echo "FAIL @__axiom_recover_top survives in a program that never arms one ($state line(s))"
      grep -n '__axiom_recover_top' "$work/hello.opt.ll" | sed 's/^/    /' | head -4
      status=1
    else
      zero=$((zero + 1))
    fi
    calls="$(grep -c 'call[^;]*@__axiom_recover' "$work/hello.opt.ll" || true)"
    if (( calls != 0 )); then
      echo "FAIL $calls call(s) to the recovery point survive in a program that never arms one"
      grep -n 'call[^;]*@__axiom_recover' "$work/hello.opt.ll" | sed 's/^/    /' | head -4
      status=1
    else
      zero=$((zero + 1))
    fi
    # An empty body is `define ... {` / `entry:` / `ret i64 0` / `}`.
    # Anything else - a load, a branch, a second block - is a body
    # that shrank rather than folded, and this reads the three lines
    # after each definition rather than the whole module.
    bodies=0
    stubs=0
    while IFS= read -r ln; do
      bodies=$((bodies + 1))
      if [[ "$(awk -v n="$ln" 'NR > n && NR <= n + 2' "$work/hello.opt.ll" | tr -d ' ')" == "entry:
reti640" ]]; then
        stubs=$((stubs + 1))
      else
        echo "FAIL the definition at line $ln is not an empty stub:"
        awk -v n="$ln" 'NR >= n && NR <= n + 3' "$work/hello.opt.ll" | sed 's/^/    /'
        status=1
      fi
    done < <(grep -n '^define .*@__axiom_recover' "$work/hello.opt.ll" | cut -d: -f1)
    if (( bodies == 0 )); then
      echo "FAIL no recovery definition survived at all - this check read nothing"
      status=1
    elif (( stubs == bodies )); then
      zero=$((zero + 1))
    fi
    if (( zero == 3 )); then
      echo "ok   a program that never arms one keeps no state, no call and no instruction"
      echo "     ($raw lines at -O0, $left at -O1, all of them the symbol table's; $bodies empty stubs)"
    fi
  fi
else
  echo "FAIL \`opt\` is not on PATH, so the zero-cost claim cannot be checked"
  status=1
fi

# ------------------------------------------------------------------
# 5. EVERY REGISTER IS ACCOUNTED FOR, ON EVERY TARGET.
#
# The arm block is sound exactly when it behaves like a CALL, and it
# says so by partitioning the register file into three sets:
#
#   clobbered            named in the constraint list
#   saved and restored   written and read back by the block's own body
#   restored explicitly  the frame pointer and the stack pointer, in
#                        the longjmp
#
# A register in NONE of those is a register a value can hide in across
# the block. `x18` was exactly that: reserved on Darwin, where LLVM
# never allocates it and the omission is invisible, and an ordinary
# allocatable caller-saved temporary on Linux, where LLVM PREFERS it
# because the block does not clobber it. The recovered status was read
# back through it and the aborted extent had destroyed it - SIGSEGV,
# `Tests (linux-aarch64)` only, exit 139 with an empty stdout and an
# empty stderr.
#
# THIS SECTION DOES NOT RESTATE THE CALLER-SAVED SET, which is the
# thing I got wrong. It asserts the PARTITION over the whole register
# file, which is only wrong if a register is forgotten to exist. And
# the one legitimate way to be in none of the three sets - being
# reserved on that target - is decided by asking LLVM rather than by
# asserting it here: a register named in a clobber list that llc calls
# reserved is one it will never allocate.
# ------------------------------------------------------------------
echo "== every register is accounted for, on every target =="

# `reserved_on <triple> <reg>` - llc's own answer, not this file's.
# The probe carries the SAME attribute group the compiler emits, and a
# non-empty asm body. Neither is decoration: with a bare `define` and an
# empty body llc is silent for every register on every target, x29
# included, and the probe answers "nothing is reserved anywhere" - a
# check that cannot fail. With `"frame-pointer"="all"` and a `nop` it
# answers x18 reserved on arm64-apple and silent on aarch64-linux,
# which is the ABI difference this section exists for.
reserved_on() {
  printf 'target triple = "%s"\ndefine void @p() #0 {\n  call void asm sideeffect "nop", "~{%s}"()\n  ret void\n}\nattributes #0 = { "no-builtins" "frame-pointer"="all" }\n' \
    "$1" "$2" > "$work/res.ll"
  llc -O0 "$work/res.ll" -o /dev/null 2>&1 | grep -qi "reserved registers"
}

triple_of() {
  case "$1" in
    darwin-aarch64) echo "arm64-apple-macosx14.0.0" ;;
    darwin-x86_64)  echo "x86_64-apple-macosx14.0.0" ;;
    linux-aarch64)  echo "aarch64-unknown-linux-gnu" ;;
    linux-x86_64)   echo "x86_64-unknown-linux-gnu" ;;
  esac
}

acct_checked=0
for target in darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64; do
  ir="$work/acct-$target.ll"
  if ! "$axc" --target="$target" emit-llvm tests/stdlib/403-recover-div.ax -o "$ir" >/dev/null 2>&1; then
    echo "FAIL [$target] could not emit IR for the register-accounting check"
    status=1
    continue
  fi
  # The arm block is the one `asm sideeffect` whose body saves the
  # callee-saved set. Matched on that, not on position.
  block="$(grep -o 'asm sideeffect "[^"]*", "[^"]*"' "$ir" \
           | grep -E 'stp x19, x20|movq %rbx, 48' | head -1)"
  if [[ -z "$block" ]]; then
    echo "FAIL [$target] no recovery arm block in the emitted IR"
    status=1
    continue
  fi

  case "$target" in
    *aarch64)
      regs=""; for i in $(seq 0 28); do regs="$regs x$i"; done
      for i in $(seq 0 31); do regs="$regs v$i"; done
      fp="x29"
      # x30 is spelled `lr`, and this is not a style point: LLVM
      # silently IGNORES `~{x30}` as an AArch64 clobber name, which is
      # the bug this file records at `targetRecoverArmAsm`. Requiring
      # the spelling that works, and refusing the one that does not.
      if [[ "$block" == *'~{lr}'* ]]; then
        : # accounted for
      else
        echo "FAIL [$target] the arm block does not clobber lr (x30)"
        status=1
      fi
      if [[ "$block" == *'~{x30}'* ]]; then
        echo "FAIL [$target] the arm block spells x30 as ~{x30}, which LLVM ignores; it must be ~{lr}"
        status=1
      fi
      ;;
    *x86_64)
      regs="rax rbx rcx rdx rsi rdi r8 r9 r10 r11 r12 r13 r14 r15"
      for i in $(seq 0 15); do regs="$regs xmm$i"; done
      fp="rbp"
      ;;
  esac

  unaccounted=""
  for r in $regs; do
    [[ "$r" == "$fp" ]] && continue
    # named in the constraint list, or moved by the block's own body
    if [[ "$block" == *"~{$r}"* ]] || [[ "$block" == *"$r,"* ]] || [[ "$block" == *"%$r,"* ]] \
       || [[ "$block" == *" $r "* ]] || [[ "$block" == *"%$r"* ]]; then
      continue
    fi
    # or reserved on this target, which llc decides
    if reserved_on "$(triple_of "$target")" "$r"; then
      continue
    fi
    unaccounted="$unaccounted $r"
  done

  if [[ -n "$unaccounted" ]]; then
    echo "FAIL [$target] registers in no set - not clobbered, not saved, not reserved:$unaccounted"
    echo "     a value can live in one of those across the arm block, and the"
    echo "     landing path will not put it back"
    status=1
  else
    echo "ok   [$target] every register is clobbered, saved, or reserved"
    acct_checked=$((acct_checked + 1))
  fi
done
if (( acct_checked != 4 )); then
  echo "FAIL only $acct_checked of 4 targets reached the register-accounting check"
  status=1
fi
# ABLATED 2026-08-25, which is the only thing that makes the four `ok`
# lines above evidence. With `",~{x18}"` in `targetRecoverArmAsm`
# replaced by `""` - the tree exactly as it was when
# `Tests (linux-aarch64)` died of SIGSEGV - and the compiler rebuilt:
#
#     ok   [darwin-aarch64] every register is clobbered, saved, or reserved
#     ok   [darwin-x86_64]  every register is clobbered, saved, or reserved
#     FAIL [linux-aarch64] registers in no set - not clobbered, not saved,
#          not reserved: x18
#     ok   [linux-x86_64]  every register is clobbered, saved, or reserved
#
# One target, the right one, and darwin-aarch64 stays green because llc
# calls x18 reserved there. That discrimination is the whole point: a
# check that flagged x18 everywhere would have to be silenced on Darwin
# and would then be silenced everywhere.
#
# It also catches this class WITHOUT a fixture happening to expose it.
# Whether LLVM parks a value in an unaccounted register depends on the
# pressure in one function: `401-recover-effect` and `403-recover-div`
# pass on linux-aarch64 with the bug present, and only `402-recover-oom`
# faults. A gate that waits for a fixture to get unlucky is a gate that
# reports the bug it already shipped.

# ------------------------------------------------------------------
# 6. The negative probe the gate cannot run for itself.
#
# Everything above asserts that recovery WORKS, and the ablated memory
# arm proves the measurement can see a difference. What is left is the
# question the house rule asks of every check: what input makes THIS
# gate go red? The answer was measured by hand rather than modelled,
# because it costs a compiler build.
#
# ABLATION, 2026-08-24. With `emitDivTrap`'s one added line
#
#     (emitLine cg "  call i64 @__axiom_recover_abort(i64 72)")
#
# deleted from `self_host/codegen.ax` and the compiler rebuilt from
# the ablated tree, this gate printed - verbatim, trimmed only where
# four identical optimisation levels repeat:
#
#     == the three traps, both positions, four optimisation levels ==
#     FAIL 403-recover-div -O0: stdout
#         1c1
#         < recovered 72
#         ---
#         >
#     FAIL 403-recover-div -O1: stdout   (and -O2, -O3, the same diff)
#     FAIL 401-recover-effect -O0: stdout
#         1,2c1
#         < recovered 71
#         < slots 727
#         ---
#         >
#     FAIL 401-recover-effect -O1: stdout  (and -O2, -O3)
#     ok   4 recovery cases recovered inside and exited outside
#     FAIL only 4 of 12 (3 cases x 4 levels) reached the comparison
#     == nesting, and 5,000 frames abandoned ==
#     FAIL nesting -O0 (exit 72)
#         1,4c1
#         < inner caught 72
#         < outer saw 0
#         < outer caught 72
#         < deep 72
#         ---
#         >
#     FAIL nesting -O1 (exit 72)   (and -O2, -O3)
#     ok   nesting takes the innermost armed point, at 0 levels
#     FAIL only 0 of 4 optimisation levels reached the nesting comparison
#     == 100,000 aborts, with a handle inside the aborted extent ==
#     FAIL 10,000 aborts summed to '' (exit 72), not 720000
#     FAIL 100,000 aborts summed to '' (exit 72), not 7200000
#     FAIL one of the three RSS measurements produced no number
#     == the emitted shape ==
#     FAIL @__axiom_div_by_zero does not ask the recovery point before it exits 72
#     FAIL only 2 of 3 traps are wired to the recovery point
#     ok   a program that never arms one keeps no state, no call and no instruction
#
#     ABLATED GATE EXIT=1
#
# Re-run 2026-08-24 against the implementation that landed, rather than
# against the prototype this text was first written from: 19 FAIL lines,
# the same eight golden comparisons, the same four nesting arms, the
# same two abort loops and the same shape check.
#
# Eight of the twelve golden comparisons, all four nesting arms, both
# abort loops and the shape check, from deleting one emitted line. The
# four that still passed are `402-recover-oom` at its four levels -
# the one case that does not divide by zero - which is the
# discrimination this gate is supposed to have rather than a hole in
# it.
#
# THE FIRST RUN OF THAT ABLATION FOUND A DEFECT IN THIS SCRIPT, and it
# is why the memory section is written the way it is. Under `set -e`,
# `got="$("$work/loop-10k")"` on a program that exits 72 killed the
# gate at that line: it printed its first two sections and stopped,
# with status 72 and no verdict, which reads as a broken gate and not
# as the red it was. The `set +e` in `sum_of` is that fix, and the
# three FAIL lines in the memory section above are what it now says
# instead.
# ------------------------------------------------------------------
exit "$status"
