#!/usr/bin/env bash
# Typed handles and the runtime's handle table (docs/memory-model.md
# MM-VAL-10a, MM-PAR-8).
#
# A channel, a mutex and a cancellation token are word structs: sealed
# types whose word is a slot in a handle table the emitted runtime owns.
# A spawn handle is the builtin `Spawn`, a slot in the same table. Every
# operation and every join asks the table for the object first, so a
# freed or forged handle traps with status 85 before the object's
# unmapped pages are touched. The diagnostics corpus holds the static
# half (1060 to 1066: an `Int` for a channel or a spawn handle, a mutex
# as a channel, the seal, the capture rule and the markers); this gate
# holds the rest.
#
# SIX SECTIONS.
#
#   1. Freed and forged handles, at every `--opt`.
#      tests/stdlib/570-handle-freed.ax runs every channel and mutex
#      operation on a freed handle, a second free, a forged word and a
#      mutex's word used as a channel, each inside a recovery point;
#      tests/stdlib/571-handle-table.ax the table itself: 65,536 live
#      handles, the 65,537th refused, a slot reused under a new
#      generation; and tests/stdlib/572-spawn-joined-twice.ax a second
#      join, the pid of a joined binding, forged and other-kind spawn
#      handles, and a freed cancellation token. Each must exit 85 at
#      --opt 0 to 3 with its golden's stdout, and 570 must print at
#      least nineteen 85s.
#   2. Misuse in both lowerings. A send on a freed channel, a lock of a
#      freed mutex, a second free and a second join exit 85, processes
#      and threads; so do the pid of a thread's handle and a forked
#      binding's handle joined as a thread.
#   3. The table under concurrency, both lowerings. Four bindings make,
#      check and free 20,000 handles each at once, and every handle must
#      answer its own address. Two bindings free one handle at once,
#      2,000 times: under threads exactly one free per round returns;
#      forked bindings each free their own copy, so both return, and a
#      sibling's free leaves the parent's channel live.
#   4. The capture rule in both lowerings. `axiom build` and `axiom
#      build --threads` refuse tests/diagnostics/1064-parallel-capture-
#      handle.ax with the same AX3064 rows its golden holds, and
#      examples/concurrency/pipeline.ax, whose bindings capture two
#      channels, builds and answers `ok` in both.
#   5. What is emitted. A program that names no handle primitive emits
#      no table; `Chan$chanAt` asks the table, and `Chan$chanSend`
#      allocates nothing and takes the handle's check once.
#   6. Ablations, each required to go red:
#        get    - a compiler whose `@__axiom_handle_get` skips both state
#                 compares: the send on a freed channel, and a second
#                 join, take whatever the retired slot holds for the
#                 object's address.
#        retire - a `Chan.ax` whose `chanFree` unmaps without retiring
#                 the handle: the same send reads the unmapped ring.
#        free   - a compiler whose `@__axiom_handle_free` retires without
#                 comparing: a double free returns, and the race frees
#                 twice a round.
#   7. A single-bit fault in a live handle word, at every bit and at
#      --opt 0 and 2 (`tests/litmus/handle-bitflip.ax`): each of the 64
#      flips of a live channel's word either traps 85 before the mapping
#      is touched, or spells the other live channel, which no check can
#      tell from the real one. The gate predicts which bits do the
#      latter from the two words and requires exactly those. With the
#      `get` ablation's compiler, some flip does neither.
#
# LIMITS. A load that passed is evidence on the runs made. A free that
# races another binding's operation on the same handle is a data race
# (MM-PAR-9) and is not checked: the table catches every use ordered
# after the free. Section 7 injects faults at the table only: a flip in
# memory the runtime doesn't check, such as a `Vec`'s length, a count
# word or the object a handle names, isn't detected, and only one flip
# at a time is tried.
#
# Usage: check-handles.sh
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH"; exit 1; }

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

sentence="axiom: not a live handle (freed, or never made)"
load="$repo_root/tests/litmus/handle-load.ax"

echo "== disposal requires a declared lifetime obligation =="
boundary="$repo_root/tests/litmus/shared-free-boundary.ax"
rc=0
"$axc" --diagnostic-format=ai check "$boundary" > "$work/free.out" 2> "$work/free.err" || rc=$?
if [[ "$rc" == 1 ]] && [[ $(grep -c '^E AX3073 ' "$work/free.err") == 6 ]] &&
   [[ $(grep -c '^E AX3049 ' "$work/free.err") == 4 ]] &&
   [[ $(grep -c '^E AX3057 ' "$work/free.err") == 3 ]] &&
   [[ $(grep -c '^E ' "$work/free.err") == 13 ]]; then
  ok "all three frees and their function values require Unsafe; restrictions still refuse tagged calls"
else
  bad "shared disposal boundary: exit $rc or unexpected diagnostics"
  head -16 "$work/free.err"
fi

# Remove only the disposal preconditions. The same compiler and source
# must lose every lifetime-boundary refusal. Strict indirect calls still
# fail closed, and the tagged call's removed Unsafe claim is unsupported.
cp -R "$repo_root/stdlib" "$work/free-lib"
python3 - "$work/free-lib" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
for name in ('Chan.ax', 'Sync.ax', 'Task.ax'):
    p = root / name
    s = p.read_text()
    lines = s.splitlines(keepends=True)
    removed = [line for line in lines if line.startswith(';@axiom:precondition(no binding')
               or line.startswith(';@axiom:precondition(no pool')]
    assert len(removed) == 1, (name, removed)
    p.write_text(''.join(line for line in lines if line not in removed))
PY
rc=0
AXIOM_STDLIB="$work/free-lib" "$axc" --diagnostic-format=ai check "$boundary" \
  > "$work/free-ablated.out" 2> "$work/free-ablated.err" || rc=$?
if [[ "$rc" == 1 ]] && [[ $(grep -c '^E ' "$work/free-ablated.err") == 4 ]] &&
   [[ $(grep -c '^E AX3057 ' "$work/free-ablated.err") == 3 ]] &&
   [[ $(grep -c '^E AX3010 ' "$work/free-ablated.err") == 1 ]]; then
  ok "removing the disposal preconditions removes every lifetime-boundary refusal"
else
  bad "disposal ablation was refused by another rule"
  head -12 "$work/free-ablated.err"
fi

echo "== 1. freed and forged handles trap 85 at every --opt =="
for name in 570-handle-freed 571-handle-table 572-spawn-joined-twice; do
  src="$repo_root/tests/stdlib/$name.ax"
  golden="$repo_root/tests/stdlib/$name.out"
  for lvl in 0 1 2 3; do
    bin="$work/$name-O$lvl"
    if ! (cd "$repo_root" && "$axc" build --opt "$lvl" --input "$src" --output "$bin") > "$bin.build" 2>&1; then
      bad "$name -O$lvl did not build"; sed 's/^/    /' "$bin.build" | head -6; continue
    fi
    rc=0; gate_timeout 60 "$bin" > "$bin.out" 2> "$bin.err" || rc=$?
    if [[ "$rc" == 85 ]] && cmp -s "$golden" "$bin.out" && [[ "$(head -1 "$bin.err")" == "$sentence" ]]; then
      ok "$name -O$lvl: exit 85, the golden's stdout, and the trap's sentence"
    else
      bad "$name -O$lvl: exit $rc, stdout $(cmp -s "$golden" "$bin.out" && echo matches || echo differs), stderr '$(head -1 "$bin.err")'"
    fi
  done
done
# The floor comes from the golden AND the run, so a golden re-blessed
# with fewer traps fails here rather than shrinking the claim.
traps="$(grep -c 'status 85$' "$repo_root/tests/stdlib/570-handle-freed.out" || true)"
ran="$(grep -c 'status 85$' "$work/570-handle-freed-O2.out" 2>/dev/null || true)"
if (( traps >= 19 && ran == traps )); then
  ok "570 answers 85 to $traps misuses, the floor is 19"
else
  bad "570's golden holds $traps 85s and the run printed $ran; the floor is 19"
fi

echo "== 2. misuse traps 85 in both lowerings =="
for lowering in processes threads; do
  flags=(); [[ "$lowering" == threads ]] && flags=(--threads)
  bin="$work/load-$lowering"
  if ! (cd "$repo_root" && "$axc" build ${flags[@]+"${flags[@]}"} --opt 2 --input "$load" --output "$bin") > "$bin.build" 2>&1; then
    bad "$lowering: the handle load did not build"; sed 's/^/    /' "$bin.build" | head -6; continue
  fi
  for mode in freed-send freed-lock double-free double-join; do
    want=freed; [[ "$mode" == double-join ]] && want=42
    rc=0; out="$(gate_timeout 30 "$bin" "$mode" 2>"$work/err")" || rc=$?
    if [[ "$rc" == 85 && "$out" == "$want" && "$(head -1 "$work/err")" == "$sentence" ]]; then
      ok "$lowering $mode: exit 85 after the first use, and nothing past it ran"
    else
      bad "$lowering $mode: exit $rc, stdout '$out', stderr '$(head -1 "$work/err")'"
    fi
  done
done
# The two kinds of spawn handle. Both lowerings are named explicitly
# by the primitives, so one build shows both.
if [[ -x "$work/load-processes" ]]; then
  for mode in thread-pid cross-join; do
    rc=0; out="$(gate_timeout 30 "$work/load-processes" "$mode" 2>"$work/err")" || rc=$?
    if [[ "$rc" == 85 && "$out" == spawned && "$(head -1 "$work/err")" == "$sentence" ]]; then
      ok "$mode: a spawn handle of the other lowering's kind exits 85"
    else
      bad "$mode: exit $rc, stdout '$out', stderr '$(head -1 "$work/err")'"
    fi
  done
fi

echo "== 3. the table under concurrency =="
field() { printf '%s\n' "$1" | awk -v k="$2" '{for (i = 1; i < NF; i++) if ($i == k) print $(i + 1)}'; }
for lowering in processes threads; do
  bin="$work/load-$lowering"
  [[ -x "$bin" ]] || { bad "$lowering: no handle load binary"; continue; }
  rc=0; out="$(gate_timeout 120 "$bin" churn 20000 2>&1)" || rc=$?
  if [[ "$rc" == 0 && "$out" == "churn 80000 checked, 0 wrong" ]]; then
    ok "$lowering churn: 80,000 handles made, checked and freed by four bindings at once, each answering its own address"
  else
    bad "$lowering churn: exit $rc, '$out'"
  fi
  rc=0; out="$(gate_timeout 120 "$bin" race 2000 2>&1)" || rc=$?
  if [[ "$lowering" == threads ]]; then want="race 2000 of 2000 frees returned"; else want="race 4000 of 2000 frees returned"; fi
  if [[ "$rc" == 0 && "$out" == "$want" ]]; then
    ok "$lowering race: '$out'"
  else
    bad "$lowering race: exit $rc, '$out', wanted '$want'"
  fi
  rc=0; out="$(gate_timeout 30 "$bin" sibling 2>&1)" || rc=$?
  if [[ "$lowering" == threads ]]; then want="sibling-free status 85"; else want="sibling-free status 1"; fi
  if [[ "$rc" == 0 && "$out" == "$want" ]]; then
    ok "$lowering sibling: '$out' - the free is the address space's, as the mapping is"
  else
    bad "$lowering sibling: exit $rc, '$out', wanted '$want'"
  fi
done

echo "== 4. the capture rule holds in both lowerings =="
fx="$repo_root/tests/diagnostics/1064-parallel-capture-handle.ax"
rows() { grep -oE '^E AX3064 [^ ]+:[0-9]+:[0-9]+-[0-9]+' "$1" | awk '{print $2, $3}'; }
want_rows="$(rows "$repo_root/tests/diagnostics/1064-parallel-capture-handle.axdl")"
n_want="$(printf '%s\n' "$want_rows" | grep -c . || true)"
for lowering in processes threads; do
  flags=(); [[ "$lowering" == threads ]] && flags=(--threads)
  rc=0
  (cd "$repo_root/tests/diagnostics" && "$axc" --diagnostic-format=ai build ${flags[@]+"${flags[@]}"} --input 1064-parallel-capture-handle.ax --output "$work/cap-$lowering") > "$work/cap-$lowering.log" 2>&1 || rc=$?
  got_rows="$(rows "$work/cap-$lowering.log")"
  if [[ "$rc" != 0 && ! -e "$work/cap-$lowering" && "$n_want" -ge 4 && "$got_rows" == "$want_rows" ]]; then
    ok "$lowering: build refused with the golden's $n_want AX3064 rows (unshared word, alias, Vec, __thread_spawn)"
  else
    bad "$lowering: build exit $rc, rows [$(printf '%s' "$got_rows" | tr '\n' ';')] against the golden's [$(printf '%s' "$want_rows" | tr '\n' ';')]"
  fi
  bin="$work/pipeline-$lowering"
  if (cd "$repo_root" && "$axc" build ${flags[@]+"${flags[@]}"} --input examples/concurrency/pipeline.ax --output "$bin") > "$bin.build" 2>&1; then
    rc=0; out="$(gate_timeout 60 "$bin" 400 2>&1)" || rc=$?
    if [[ "$rc" == 0 && "$(printf '%s\n' "$out" | tail -1)" == ok ]]; then
      ok "$lowering: pipeline.ax captures two channels and answers ok"
    else
      bad "$lowering: pipeline.ax exit $rc, last line '$(printf '%s\n' "$out" | tail -1)'"
    fi
  else
    bad "$lowering: pipeline.ax did not build - a shared handle was refused"; sed 's/^/    /' "$bin.build" | head -6
  fi
done

echo "== 5. what is emitted =="
printf '(fn (main)\n  0)\n' > "$work/plain.ax"
(cd "$work" && "$axc" emit-llvm plain.ax -o "$work/plain.ll") > /dev/null 2>&1
if [[ -s "$work/plain.ll" ]] && ! grep -q '__axiom_htab\|__axiom_handle_' "$work/plain.ll"; then
  ok "a program that names no handle primitive emits no table ($(wc -l < "$work/plain.ll" | tr -d ' ') lines)"
else
  bad "the plain program's IR is missing or names the handle table"
fi
(cd "$repo_root" && "$axc" emit-llvm --opt 0 "$load" -o "$work/load0.ll") > /dev/null 2>&1
body() { awk -v f="$2" '$0 ~ "^define " && index($0, f"(") {on = 1} on {print} on && /^}/ {exit}' "$1"; }
at="$(body "$work/load0.ll" '@Chan$chanAt' | grep -c 'call i64 @__axiom_handle_get(' || true)"
send="$(body "$work/load0.ll" '@Chan$chanSend')"
send_at="$(printf '%s\n' "$send" | grep -c 'call i64 @Chan$chanAt(' || true)"
send_alloc="$(printf '%s\n' "$send" | grep -c '@axiom_alloc' || true)"
send_lines="$(printf '%s\n' "$send" | grep -c . || true)"
if [[ "$at" == 1 && "$send_at" == 1 && "$send_alloc" == 0 && "$send_lines" -gt 10 ]]; then
  ok "Chan\$chanAt asks the table once; Chan\$chanSend ($send_lines lines) checks its handle once and allocates nothing"
else
  bad "chanAt names the table $at time(s); chanSend calls chanAt $send_at time(s) and axiom_alloc $send_alloc time(s) in $send_lines lines"
fi

# A heap record holding a handle maps as the same record holding an
# `Int`: the handle's word is not a reference, so the release walk must
# never follow it. The `String` control must map differently, or the
# probe could not see a map bit at all.
shape_of() {  # <field type> <field value>: the shape word Box's allocation stores
  cat > "$work/shape.ax" <<AX
(struct W word
  (slot : Int))

(struct Box
  (a : $1)
  (s : String)
  (n : Int))

(:: mk (-> Int Box))
(fn (mk i)
  (Box $2 "t" i))

(:: main Int)
(fn (main)
  (let ((b (mk 3)))
    b.n))
AX
  (cd "$work" && "$axc" emit-llvm --opt 0 shape.ax -o "$work/shape.ll") > /dev/null 2>&1 || return 1
  awk '/^define .*@mk\(/ {on = 1} on && /@axiom_alloc\(i64 24\)/ {seen = 1; next}
       seen && /store i64 [0-9]+, ptr/ {print $3; exit}' "$work/shape.ll" | tr -d ','
}
word_shape="$(shape_of W '(W i)')"
int_shape="$(shape_of Int i)"
str_shape="$(shape_of String '"u"')"
if [[ -n "$word_shape" && "$word_shape" == "$int_shape" && -n "$str_shape" && "$str_shape" != "$word_shape" ]]; then
  ok "a record holding a handle maps as one holding an Int (shape word $word_shape); a String there maps $str_shape"
else
  bad "shape words: handle '$word_shape', Int '$int_shape', String '$str_shape'"
fi

echo "== 6. ablations: each turns its check red =="
# A compiler built from self_host/ with each <old> seam replaced by its
# <new>, aborting when a seam is not there exactly once, so a drill that
# silently did not apply cannot pass as one that could not fail.
ablate_cc() {  # <tag> <old> <new> [<old> <new> ...]
  local tag="$1" dir="$work/cc-$1"; shift
  rm -rf "$dir"; mkdir -p "$dir"
  cp -R "$repo_root/self_host" "$dir/self_host"
  python3 - "$dir/self_host/codegen.ax" "$@" <<'PY' || return 1
import sys
p, pairs = sys.argv[1], sys.argv[2:]
s = open(p, encoding="utf-8").read()
for old, new in zip(pairs[0::2], pairs[1::2]):
    if s.count(old) != 1:
        sys.exit("seam %r found %d times, wanted 1" % (old[:60], s.count(old)))
    s = s.replace(old, new)
open(p, "w", encoding="utf-8").write(s)
PY
  gate_build_tree "$axc" "$dir" "$repo_root/stdlib" "$dir/axc" > "$dir/build.log" 2>&1
}
signal_or_ran() {  # <exit> <stdout>: the misuse did something other than trap 85
  [[ "$1" != 85 && "$1" != 124 ]]
}
if ablate_cc get \
  '        (emitLine cg "  %ok1 = icmp eq i64 %s1, %want")' '        (emitLine cg "  %ok1 = icmp eq i64 %want, %want")' \
  '        (emitLine cg "  %ok2 = icmp eq i64 %s2, %want")' '        (emitLine cg "  %ok2 = icmp eq i64 %want, %want")'; then
  (cd "$repo_root" && "$work/cc-get/axc" build --opt 2 --input "$load" --output "$work/cc-get/load") > "$work/cc-get/load.build" 2>&1
  rc=0; out="$(gate_timeout 30 "$work/cc-get/load" freed-send 2>/dev/null)" || rc=$?
  rc2=0; out2="$(gate_timeout 30 "$work/cc-get/load" double-join 2>/dev/null)" || rc2=$?
  if signal_or_ran "$rc" "$out" && signal_or_ran "$rc2" "$out2"; then
    ok "get: red - with the state compares gone, the send on a freed channel exits $rc and a second join $rc2, instead of 85"
  else
    bad "get: the ablated compiler's freed send exits $rc and second join $rc2 - the check cannot see the missing compare"
  fi
else
  bad "get: the compiler ablation did not apply or build"; tail -4 "$work/cc-get/build.log" 2>/dev/null | sed 's/^/    /'
fi

dir="$work/abl-retire"
mkdir -p "$dir"; cp -R "$repo_root/stdlib" "$dir/stdlib"; cp "$load" "$dir/handle-load.ax"
if python3 - "$dir/stdlib/Chan.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = "  (let ((ch (chanRetire c)))\n    (sysUnmapShared ch (chanGet ch 7))))"
if s.count(old) != 1:
    sys.exit("seam found %d times" % s.count(old))
open(p, "w", encoding="utf-8").write(s.replace(old, "  (let ((ch (chanAt c)))\n    (sysUnmapShared ch (chanGet ch 7))))"))
PY
then
  (cd "$dir" && AXIOM_STDLIB="$dir/stdlib" "$axc" build --opt 2 --input handle-load.ax --output "$dir/load") > "$dir/build.log" 2>&1
  rc=0; out="$(gate_timeout 30 "$dir/load" freed-send 2>/dev/null)" || rc=$?
  if signal_or_ran "$rc" "$out"; then
    ok "retire: red - a chanFree that unmaps without retiring leaves the send on the freed channel exiting $rc instead of 85"
  else
    bad "retire: the ablated library's freed send still exits $rc"
  fi
else
  bad "retire: the library ablation did not apply"
fi

if ablate_cc free '        (emitLine cg "  %mine = extractvalue { i64, i1 } %cx, 1")' '        (emitLine cg "  store atomic i64 %freed, ptr %sp seq_cst, align 8")
        (emitLine cg "  %mine = icmp eq i64 0, 0")'; then
  (cd "$repo_root" && "$work/cc-free/axc" build --threads --opt 2 --input "$load" --output "$work/cc-free/load") > "$work/cc-free/load.build" 2>&1
  rc=0; gate_timeout 30 "$work/cc-free/load" double-free > "$work/cc-free/double.out" 2>/dev/null || rc=$?
  rc2=0; race="$(gate_timeout 120 "$work/cc-free/load" race 2000 2>/dev/null)" || rc2=$?
  if [[ "$rc" != 85 && "$race" != "race 2000 of 2000 frees returned" ]]; then
    ok "free: red - with the retiring compare gone, a double free exits $rc and the race says '$race'"
  else
    bad "free: the ablated compiler's double free exits $rc and the race says '$race' - the checks cannot see a free that refuses nothing"
  fi
else
  bad "free: the compiler ablation did not apply or build"; tail -4 "$work/cc-free/build.log" 2>/dev/null | sed 's/^/    /'
fi

echo "== 7. a single-bit fault in a live handle word traps 85, unless it spells another live handle =="
bitflip="$repo_root/tests/litmus/handle-bitflip.ax"
# flips <binary>: "<detected>|<aliased bits>|<wrong k:exit:stdout ...>"
flips() {
  local bin="$1" k rc out words wa wb det=0 alias="" wrong="" want
  words="$(gate_timeout 30 "$bin" -1 2>/dev/null | sed -n 's/^words //p')"
  wa="${words% *}"; wb="${words#* }"
  if [[ ! "$wa" =~ ^[0-9]+$ || ! "$wb" =~ ^[0-9]+$ ]]; then echo "0||no words"; return; fi
  for (( k = 0; k < 64; k++ )); do
    rc=0; out="$(gate_timeout 30 "$bin" "$k" 2>"$work/flip.err")" || rc=$?
    want=85
    (( (wa ^ (1 << k)) == wb )) && want=b
    if [[ "$want" == b && $rc -eq 0 && "$out" == b ]]; then
      alias+=" $k"
    elif [[ "$want" == 85 && $rc -eq 85 ]] && grep -q "not a live handle" "$work/flip.err"; then
      det=$((det + 1))
    else
      wrong+=" $k:$rc:${out:-_}"
    fi
  done
  echo "$det|${alias# }|${wrong# }"
}
for lvl in 0 2; do
  bin="$work/bitflip.O$lvl"
  if ! (cd "$repo_root" && "$axc" build --opt "$lvl" --input "$bitflip" --output "$bin") > "$bin.build" 2>&1; then
    bad "bitflip --opt $lvl did not build"; sed 's/^/    /' "$bin.build" | head -8; continue
  fi
  rc=0; ctl="$(gate_timeout 30 "$bin" -1 2>/dev/null | tail -1)" || rc=$?
  if [[ $rc -ne 0 || "$ctl" != a ]]; then
    bad "bitflip -O$lvl control: the unflipped handle answered '$ctl', exit $rc, not 'a'"; continue
  fi
  IFS='|' read -r det alias wrong <<<"$(flips "$bin")"
  if [[ -z "$wrong" && -n "$alias" && $(( det + $(wc -w <<<"$alias") )) -eq 64 ]]; then
    ok "bitflip -O$lvl: $det of 64 single-bit faults trap 85; bit $alias spells the other live channel, as the words predict"
  else
    bad "bitflip -O$lvl: $det trapped 85, aliased [$alias], wrong [$wrong]"
  fi
done
if [[ -x "$work/cc-get/axc" ]]; then
  bin="$work/cc-get/bitflip"
  (cd "$repo_root" && "$work/cc-get/axc" build --opt 2 --input "$bitflip" --output "$bin") > "$bin.build" 2>&1
  IFS='|' read -r det alias wrong <<<"$(flips "$bin")"
  if [[ -n "$wrong" ]]; then
    ok "bitflip ablated: red - with the state compares gone, $(( $(wc -w <<<"$wrong") )) flips neither trap nor alias"
  else
    bad "bitflip ablated: every flip still traps or aliases, so section 7 cannot see the table's compares"
  fi
else
  bad "bitflip ablated: the get ablation's compiler is missing, so section 7 has no negative"
fi

echo
if (( failed > 0 )); then
  echo "check-handles: $failed failed, $checks passed"
  exit 1
fi
echo "check-handles: $checks checks - a freed, forged or rejoined handle traps 85 at every --opt"
echo "               and in both lowerings, the table holds under concurrency, the"
echo "               capture rule holds in both lowerings, and every ablation goes red"
