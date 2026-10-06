#!/usr/bin/env bash
# Abort to an arena mark. The three traps recover inside a recovery
# point and still stop the process outside one, and 100,000 aborts do
# not grow memory.
#
# `(__axiom_recover mark thunk)` arms a recovery point at `mark` and
# runs `thunk`. Out of memory (70), an unhandled effect (71) and a
# division by zero (72) then return their status to the arming call
# instead of writing to fd 2 and exiting. With nothing armed they write
# and exit as usual. This is its own gate because two of its checks are not
# golden comparisons: a sweep over optimisation levels, and a memory
# measurement.
#
# Every case builds at all four levels the driver accepts. The arm
# block is a `setjmp` in inline assembly, and its correctness rests on
# a clobber list telling LLVM that nothing survives the block in a
# register. That can hold at -O0 and fail above it: LLVM silently
# ignores `~{x30}` as an AArch64 clobber name, and the resulting
# segfault appears only from -O1 up.
#
# The memory loop exists because jumping past frames with pending
# `axiom_release` calls is sound only if the arena reset reclaims
# everything above the mark (docs/memory-model.md MM-ALLOC-13,
# MM-ALLOC-14) and scrubs the slab heads first, so nothing filed is
# issued twice (MM-LIFE-2e). Any residue shows as growth in max RSS.
# The loop puts a `handle` inside the aborted extent, the one shape that
# argument does not cover: `emitHandleDyn` retains the evidence record
# its push displaces, which may live below the mark, and the matching
# release is at the pop the jump skips.
#
# A broken measurement also reads flat, so the flat run is paired with
# an ablated twin: the same program without the trap, which returns
# normally and never resets. The twin must grow by a wide margin.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

status=0

# Peak RSS comes from `max_rss_kb` in scripts/lib/gate.sh. It keys the
# bytes-or-KiB divisor on the kernel, since FreeBSD's `time` also takes
# `-l` but reports KiB, and it fails rather than skips when no `time`
# answers.

# ------------------------------------------------------------------
# 1. Each trap recovers inside a recovery point and still exits
#    outside one, at every optimisation level.
#
# The three cases are `tests/stdlib/40{1,2,3}-recover-*.ax`. Their
# goldens are the ones `run-stdlib-tests.sh` compares, read here so
# there is one copy. This adds the compiler under test (that runner
# uses `$axiom`, which may predate the change) and all four levels.
#
# Each case carries both halves in one program. With `__axiom_recover`
# unreferenced, no store to `@__axiom_recover_top` survives and
# GlobalOpt folds the armed test in each trap to false, so a case that
# only trapped outside an extent would test a trap with no branch left
# in it.
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
    # Truncate stderr at the backtrace header, as `run-stdlib-tests.sh`
    # does. The frames below it name functions and cannot be a golden.
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
# A sweep that reached nothing would otherwise pass.
if (( checked != 12 )); then
  echo "FAIL only $checked of 12 (3 cases x 4 levels) reached the comparison"
  status=1
fi

# ------------------------------------------------------------------
# 2. Nesting, and the frames in between.
#
# `MM-ALLOC-16a` requires marks to be reset innermost-first, so an
# abort takes the innermost armed point: `inner caught 72 / outer saw
# 0`. The same program then traps with only the outer point armed, and
# again from 5,000 non-tail frames down.
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

;@axiom:effect(io)
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

;@axiom:effect(io)
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
# in two spellings that differ by one line. Both take a single mark
# outside the loop, allocate 4 KiB per iteration, and install a handler
# per iteration inside the extent. `trap` divides by zero at the
# bottom, so every iteration aborts to the mark. `no-trap` answers 0
# there, so the recovery point returns normally and nothing resets.
# `no-trap` is the ablated arm: it shows the measurement can see growth.
#
# `Mut` is in the outer handle list because `AX3011` requires the list
# to be exhaustive, and `println` reaches `__store64`, which carries
# `Mut` (`docs/memory-model.md` MM-EXEC-9a). This heredoc is a corpus
# that a sweep over `tests/**/*.ax` misses, so check effect-inference
# changes against it too.
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
    }    (Console Alloc Unsafe)    (lambda (s) 0)
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

;@axiom:effect(io)
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
    )    (Console Alloc IO Mut Unsafe)    (lambda (s) 0)
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
# Each run is wrapped in `set +e`. Under `set -e`, a bare `got="$(cmd)"`
# whose command fails kills the script at that line, with no verdict.
# A broken recovery point makes these programs do exactly that: they
# exit 72 instead of printing a sum.
#
# The sum asserts that the aborts happened (100,000 x 72). A program
# that silently stopped aborting would otherwise report a flat line.
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

  # Flat, stated two ways. The ceiling is easy to check against the
  # numbers above. The delta survives a machine with a different
  # baseline RSS.
  if (( rss_100k > 32768 )); then
    echo "FAIL 100,000 aborts peaked at ${rss_100k} KiB, over the 32 MiB ceiling"
    status=1
  elif (( rss_100k - rss_10k > 4096 )); then
    echo "FAIL RSS grew ${rss_100k}-${rss_10k} KiB between 10,000 and 100,000 aborts"
    status=1
  else
    echo "ok   100,000 aborts hold RSS flat (${rss_10k} -> ${rss_100k} KiB)"
  fi

  # The ablated arm must grow, or the flat result above proves nothing.
  # It normally grows by a factor of a few hundred. The bar of 8x and
  # 64 MiB sits well below that and well above noise.
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
# Two claims that program output cannot show. Each trap asks the
# recovery point before it writes its message. And a program that
# never arms one pays nothing: with no store to `@__axiom_recover_top`,
# GlobalOpt folds the armed test to its initialiser and drops the arena
# reset in the abort path.
# ------------------------------------------------------------------
echo "== the emitted shape =="
# Use `401-recover-effect.ax`: the unhandled-effect trap is emitted only
# for a module that declares an effect.
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
  # The call is the first line of the trap's entry block, so look only
  # at the three lines after the definition.
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

# The negative half: a program that never arms a recovery point keeps
# no state, no call and no instruction of it after `opt -O1`. Without
# `opt` on PATH the claim cannot be checked, so the gate fails.
#
# The names cannot vanish entirely. The backtrace symbol table
# (`@__axiom_symtab`) takes the address of every function, so
# `@__axiom_recover_abort` and the two slot helpers always survive
# GlobalDCE. A zero count can never pass, and a ceiling on the count
# asserts a number, not a property. So the gate checks three things:
#
#   1. `@__axiom_recover_top` is gone. It is the only mutable state and
#      the arm site is its only writer, so with no arm site GlobalOpt
#      folds the abort's load and deletes the global. A store in the
#      abort would keep it alive in every program with a trap.
#   2. No call to any of the helpers survives. That call would be a
#      cost on the path every dying program takes.
#   3. Every surviving definition is empty: `entry:` then `ret i64 0`.
#      An empty body shows it folded, where a short one only shrank.
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
      { grep -n '__axiom_recover_top' "$work/hello.opt.ll" || true; } | sed 's/^/    /' | head -4
      status=1
    else
      zero=$((zero + 1))
    fi
    # Anchored to an instruction, `[%x = ][tail ]call ... @__axiom_recover`.
    # The symbol table is one line naming every function, and a name
    # such as `usesSyscallAbi` contains "call", so a bare `call[^;]*`
    # would match a table entry.
    calls="$(grep -cE '^[[:space:]]*(%[^ ]+ = )?(tail |musttail |notail )?call .*@__axiom_recover' "$work/hello.opt.ll" || true)"
    if (( calls != 0 )); then
      echo "FAIL $calls call(s) to the recovery point survive in a program that never arms one"
      { grep -n 'call[^;]*@__axiom_recover' "$work/hello.opt.ll" || true; } | sed 's/^/    /' | head -4
      status=1
    else
      zero=$((zero + 1))
    fi
    # An empty body is `define ... {` / `entry:` / `ret i64 0` / `}`.
    # A load, a branch or a second block means the body only shrank.
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
# 5. Every register is accounted for, on every target.
#
# The arm block is sound exactly when it behaves like a call. It
# partitions the register file into three sets:
#
#   clobbered            named in the constraint list
#   saved and restored   written and read back by the block's own body
#   restored explicitly  the frame pointer and the stack pointer, in
#                        the longjmp
#
# A register in none of them can carry a value across the block. `x18`
# is the classic case: reserved on Darwin, but an ordinary caller-saved
# temporary on Linux and FreeBSD, where LLVM prefers it because the
# block does not clobber it. The symptom is a SIGSEGV (exit 139) with
# empty stdout and stderr on those targets only.
#
# The check does not restate the caller-saved set, which is easy to get
# wrong. It walks the whole register file and puts each register in a
# set, so it can only miss one that the list below forgets exists. The
# one legitimate way to be in no set is to be reserved on that target,
# and llc decides that.
# ------------------------------------------------------------------
echo "== every register is accounted for, on every target =="

# `reserved_on <triple> <reg>` asks llc whether a register is reserved.
# The probe needs the compiler's own attribute group and a non-empty
# asm body. With a bare `define` and an empty body, llc warns about no
# register on any target, so the check could never fail. With
# `"frame-pointer"="all"` and a `nop`, llc reports x18 reserved on
# arm64-apple and not on aarch64-linux.
reserved_on() {
  printf 'target triple = "%s"\ndefine void @p() #0 {\n  call void asm sideeffect "nop", "~{%s}"()\n  ret void\n}\nattributes #0 = { "no-builtins" "frame-pointer"="all" }\n' \
    "$1" "$2" > "$work/res.ll"
  llc -O0 "$work/res.ll" -o /dev/null 2>&1 | grep -qi "reserved registers"
}

triple_of() {
  case "$1" in
    darwin-aarch64)  echo "arm64-apple-macosx14.0.0" ;;
    darwin-x86_64)   echo "x86_64-apple-macosx14.0.0" ;;
    linux-aarch64)   echo "aarch64-unknown-linux-gnu" ;;
    linux-x86_64)    echo "x86_64-unknown-linux-gnu" ;;
    freebsd-x86_64)  echo "x86_64-unknown-freebsd14.0" ;;
    freebsd-aarch64) echo "aarch64-unknown-freebsd14.0" ;;
  esac
}

acct_checked=0
acct_targets="darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64 freebsd-x86_64 freebsd-aarch64"
for target in $acct_targets; do
  ir="$work/acct-$target.ll"
  if ! "$axc" --target="$target" emit-llvm tests/stdlib/403-recover-div.ax -o "$ir" >/dev/null 2>&1; then
    echo "FAIL [$target] could not emit IR for the register-accounting check"
    status=1
    continue
  fi
  # The arm block is the one `asm sideeffect` whose body saves the
  # callee-saved set. Match on that body, not on its position.
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
      # x30 must be spelled `lr`. LLVM silently ignores `~{x30}` as an
      # AArch64 clobber name (see `targetRecoverArmAsm` in
      # self_host/codegen.ax).
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
if (( acct_checked != 6 )); then
  echo "FAIL only $acct_checked of 6 targets reached the register-accounting check"
  status=1
fi
# Negative probe: remove `,~{x18}` for one aarch64 target where llc does
# not reserve x18 (the predicate in `targetRecoverArmAsm`), rebuild the
# compiler, and that target alone turns red. darwin-aarch64 stays green
# because llc reserves x18 there. That is why llc, not this file,
# decides what is reserved: a check that flagged x18 everywhere would
# need silencing on Darwin, and then nowhere would catch it.
#
# The check does not rely on a fixture to expose the bug. Whether LLVM
# uses an unaccounted register depends on pressure in one function, and
# with x18 missing only `402-recover-oom` faults on linux-aarch64.

# ------------------------------------------------------------------
# 6. The negative probe, run by hand because it needs a compiler build.
#
# Delete this line from `emitDivTrap` in self_host/codegen.ax and
# rebuild the compiler:
#
#     (emitLine cg "  call i64 @__axiom_recover_abort(i64 72)")
#
# The gate must then fail eight of the twelve golden comparisons, all
# four nesting levels, both abort loops and the shape check. Of the
# golden cases, only `402-recover-oom` passes: it never divides by zero.
# ------------------------------------------------------------------
exit "$status"
