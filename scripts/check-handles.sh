#!/usr/bin/env bash
# Typed handles and the runtime's handle table (docs/memory-model.md
# MM-VAL-10a, MM-PAR-8, MM-PAR-16).
#
# A spawn handle is the builtin `Spawn`, a slot in a handle table the
# emitted runtime owns, and the unsafe layer makes slots of its own with
# `__handle_new`. Every join and every get asks the table first, so a
# rejoined, freed or forged handle traps with status 85 before the page
# it named is touched. A channel, a mutex and a cancellation token are
# owners instead (MM-PAR-16): sealed heap structs whose page lives while
# any holder does, so there is no free to check. The diagnostics corpus
# holds the static half (1060 to 1066: an `Int` for a channel or a spawn
# handle, a mutex as a channel, the seal, the capture rule and the
# markers; 1260: a cast to `Spawn` is a forging cast); this gate holds
# the rest.
#
# NINE SECTIONS.
#
#   1. The table and spawn handles at every `--opt`.
#      tests/stdlib/571-handle-table.ax the table itself: 65,536 live
#      handles, the 65,537th refused, a slot reused under a new
#      generation; tests/stdlib/572-spawn-joined-twice.ax a second
#      join, the pid of a joined binding, and forged and other-kind
#      spawn handles; and tests/stdlib/850-spawn-cast-trusted.ax a
#      handle carried as a word and turned back by a trusted cast,
#      a status refused by its precondition (80) and a forged word
#      (85). Each must exit 85 at --opt 0 to 3 with its golden's
#      stdout.
#   2. Misuse in both lowerings. A get of a freed handle, a second free
#      and a second join exit 85, processes and threads; so do the pid
#      of a thread's handle and a forked binding's handle joined as a
#      thread.
#   3. The table under concurrency, both lowerings. Four bindings make,
#      check and free 20,000 handles each at once, and every handle must
#      answer its own address. Two bindings free one handle at once,
#      2,000 times: under threads exactly one free per round returns;
#      forked bindings each free their own copy, so both return, and a
#      sibling's free leaves the parent's handle live.
#   4. The capture rule in both lowerings. `axiom build` and `axiom
#      build --threads` refuse tests/diagnostics/1064-parallel-capture-
#      handle.ax with the same AX3064 rows its golden holds, and
#      examples/concurrency/pipeline.ax, whose bindings borrow two
#      channels, builds and answers `ok` in both.
#   5. What is emitted. A program that names no handle primitive emits
#      no table; `Chan$chanAt` reads the channel's owner and not the
#      table, and `Chan$chanSend` allocates nothing and reads its ring's
#      address once.
#   6. Ablations, each required to go red:
#        get    - a compiler whose `@__axiom_handle_get` skips both state
#                 compares: the get of a freed handle, and a second
#                 join, take whatever the retired slot holds for the
#                 object's address.
#        free   - a compiler whose `@__axiom_handle_free` retires without
#                 comparing: a double free returns, and the race frees
#                 twice a round.
#   7. A single-bit fault in a live handle word, at every bit and at
#      --opt 0 and 2 (`tests/litmus/handle-bitflip.ax`): each of the 64
#      flips of a live handle's word either traps 85 before the page is
#      touched, or spells the other live handle, which no check can
#      tell from the real one. The gate predicts which bits do the
#      latter from the two words and requires exactly those: none,
#      since each slot's first generation is drawn from the table's
#      salt, so two live words differ in many bits. With the `get`
#      ablation's compiler some flip does neither, and with the `salt`
#      ablation's the two words differ in one bit, which then aliases.
#
#   8. Owned descriptors: 300 pollers and 300 key readers made and
#      dropped under `ulimit -n 256` leave no descriptor behind
#      (tests/stdlib/786-poller-owned.ax).
#   9. A guessed word is not a live handle, and a cast to `Spawn`
#      forges one (MM-PAR-8, MM-EXEC-9d). tests/litmus/spawn-scan.ax
#      casts every word from 0 to 400,000 to `Spawn` in a trusted
#      declaration while one child runs: the table must answer none of
#      them, the child's own word must be outside that range, and its
#      owner must still join it with 42. Ablation `salt`: a compiler
#      whose slots start at generation 1 again makes the child's word
#      65,536, which the scan finds. The
#      compiler under test refuses tests/diagnostics/1260-spawn-forging-
#      cast.ax with one AX3073 at each untagged cast whose source is not
#      already a `Spawn`, which the gate finds in the fixture's own
#      bytes, and none at the controls. The standard library's two such
#      casts, `taskHandleOf` and `taskHandleOf`, are trusted
#      encapsulations (`#unsafe=trusted`). Ablation `forge`: a compiler
#      whose forging rule no longer names `Spawn` draws no AX3073 on the
#      fixture, only `trusted`'s AX3010 for a claim it no longer needs.
#
# LIMITS. A load that passed is evidence on the runs made. A free that
# races another binding's use of the same handle is a data race
# (MM-PAR-9) and is not checked: the table catches every use ordered
# after the free. Section 7 injects faults at the table only: a flip in
# memory the runtime doesn't check, such as a `Vec`'s length, a count
# word, a channel's reference or the object a handle names, isn't
# detected, and only one flip at a time is tried.
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

echo "== 1. freed and forged handles trap 85 at every --opt =="
for name in 571-handle-table 572-spawn-joined-twice 850-spawn-cast-trusted; do
  src="$repo_root/tests/stdlib/$name.ax"
  golden="$repo_root/tests/stdlib/$name.out"
  for lvl in 0 1 2 3; do
    bin="$work/$name-O$lvl"
    if ! (cd "$repo_root" && gate_fixture_axc "$axc" build --opt "$lvl" --input "$src" --output "$bin") > "$bin.build" 2>&1; then
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
echo "== 2. misuse traps 85 in both lowerings =="
for lowering in processes threads; do
  flags=(); [[ "$lowering" == threads ]] && flags=(--threads)
  bin="$work/load-$lowering"
  if ! (cd "$repo_root" && gate_fixture_axc "$axc" build ${flags[@]+"${flags[@]}"} --opt 2 --input "$load" --output "$bin") > "$bin.build" 2>&1; then
    bad "$lowering: the handle load did not build"; sed 's/^/    /' "$bin.build" | head -6; continue
  fi
  for mode in freed-get double-free double-join; do
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
    ok "$lowering sibling: '$out' - the free is the address space's, as the table is"
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
  (cd "$repo_root/tests/diagnostics" && gate_fixture_axc "$axc" --diagnostic-format=ai build ${flags[@]+"${flags[@]}"} --input 1064-parallel-capture-handle.ax --output "$work/cap-$lowering") > "$work/cap-$lowering.log" 2>&1 || rc=$?
  got_rows="$(rows "$work/cap-$lowering.log")"
  if [[ "$rc" != 0 && ! -e "$work/cap-$lowering" && "$n_want" -ge 4 && "$got_rows" == "$want_rows" ]]; then
    ok "$lowering: build refused with the golden's $n_want AX3064 rows (unshared word, alias, Vec, __thread_spawn)"
  else
    bad "$lowering: build exit $rc, rows [$(printf '%s' "$got_rows" | tr '\n' ';')] against the golden's [$(printf '%s' "$want_rows" | tr '\n' ';')]"
  fi
  bin="$work/pipeline-$lowering"
  if (cd "$repo_root" && gate_fixture_axc "$axc" build ${flags[@]+"${flags[@]}"} --input examples/concurrency/pipeline.ax --output "$bin") > "$bin.build" 2>&1; then
    rc=0; out="$(gate_timeout 60 "$bin" 400 2>&1)" || rc=$?
    if [[ "$rc" == 0 && "$(printf '%s\n' "$out" | tail -1)" == ok ]]; then
      ok "$lowering: pipeline.ax lends two channels to its bindings and answers ok"
    else
      bad "$lowering: pipeline.ax exit $rc, last line '$(printf '%s\n' "$out" | tail -1)'"
    fi
  else
    bad "$lowering: pipeline.ax did not build - a shared handle was refused"; sed 's/^/    /' "$bin.build" | head -6
  fi
done

echo "== 5. what is emitted =="
printf '(fn (main)\n  0)\n' > "$work/plain.ax"
(cd "$work" && gate_fixture_axc "$axc" emit-llvm plain.ax -o "$work/plain.ll") > /dev/null 2>&1
if [[ -s "$work/plain.ll" ]] && ! grep -q '__axiom_htab\|__axiom_handle_' "$work/plain.ll"; then
  ok "a program that names no handle primitive emits no table ($(wc -l < "$work/plain.ll" | tr -d ' ') lines)"
else
  bad "the plain program's IR is missing or names the handle table"
fi
(cd "$repo_root" && gate_fixture_axc "$axc" emit-llvm --opt 0 tests/litmus/chan-load.ax -o "$work/chan0.ll") > /dev/null 2>&1
body() { awk -v f="$2" '$0 ~ "^define " && index($0, f"(") {on = 1} on {print} on && /^}/ {exit}' "$1"; }
at_owner="$(body "$work/chan0.ll" '@Chan$chanAt' | grep -c 'call i64 @__axiom_resource_get(' || true)"
at_table="$(body "$work/chan0.ll" '@Chan$chanAt' | grep -c '@__axiom_handle_' || true)"
send="$(body "$work/chan0.ll" '@Chan$chanSend')"
send_at="$(printf '%s\n' "$send" | grep -c 'call i64 @Chan$chanAt(' || true)"
send_alloc="$(printf '%s\n' "$send" | grep -c '@axiom_alloc' || true)"
send_lines="$(printf '%s\n' "$send" | grep -c . || true)"
if [[ "$at_owner" == 1 && "$at_table" == 0 && "$send_at" == 1 && "$send_alloc" == 0 && "$send_lines" -gt 10 ]]; then
  ok "Chan\$chanAt reads the owner once and not the table; Chan\$chanSend ($send_lines lines) reads its ring once and allocates nothing"
else
  bad "chanAt reads the owner $at_owner time(s) and names the table $at_table time(s); chanSend calls chanAt $send_at time(s) and axiom_alloc $send_alloc time(s) in $send_lines lines"
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
  (Box :a $2 :s "t" :n i))

(:: main Int)
(fn (main)
  { (let b (mk 3))
    b.n})
AX
  (cd "$work" && gate_fixture_axc "$axc" emit-llvm --opt 0 shape.ax -o "$work/shape.ll") > /dev/null 2>&1 || return 1
  awk '/^define .*@mk\(/ {on = 1} on && /@axiom_alloc\(i64 24\)/ {seen = 1; next}
       seen && /store i64 [0-9]+, ptr/ {print $3; exit}' "$work/shape.ll" | tr -d ','
}
word_shape="$(shape_of W '(W :slot i)')"
int_shape="$(shape_of Int i)"
str_shape="$(shape_of String '"u"')"
if [[ -n "$word_shape" && "$word_shape" == "$int_shape" && -n "$str_shape" && "$str_shape" != "$word_shape" ]]; then
  ok "a record holding a handle maps as one holding an Int (shape word $word_shape); a String there maps $str_shape"
else
  bad "shape words: handle '$word_shape', Int '$int_shape', String '$str_shape'"
fi

echo "== 6. ablations: each turns its check red =="
# A compiler built from core/ with each <old> seam replaced by its
# <new>, aborting when a seam is not there exactly once, so a drill that
# silently did not apply cannot pass as one that could not fail.
# `ablate_file` names the compiler source the seams are in.
ablate_file=codegen.ax
ablate_cc() {  # <tag> <old> <new> [<old> <new> ...]
  local tag="$1" dir="$work/cc-$1"; shift
  rm -rf "$dir"; mkdir -p "$dir"
  cp -R "$repo_root/core" "$dir/core"
  python3 - "$dir/core/$ablate_file" "$@" <<'PY' || return 1
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
  (cd "$repo_root" && gate_fixture_axc "$work/cc-get/axc" build --opt 2 --input "$load" --output "$work/cc-get/load") > "$work/cc-get/load.build" 2>&1
  rc=0; out="$(gate_timeout 30 "$work/cc-get/load" freed-get 2>/dev/null)" || rc=$?
  rc2=0; out2="$(gate_timeout 30 "$work/cc-get/load" double-join 2>/dev/null)" || rc2=$?
  if signal_or_ran "$rc" "$out" && signal_or_ran "$rc2" "$out2"; then
    ok "get: red - with the state compares gone, the get of a freed handle exits $rc and a second join $rc2, instead of 85"
  else
    bad "get: the ablated compiler's freed get exits $rc and second join $rc2 - the check cannot see the missing compare"
  fi
else
  bad "get: the compiler ablation did not apply or build"; tail -4 "$work/cc-get/build.log" 2>/dev/null | sed 's/^/    /'
fi

if ablate_cc free '        (emitLine cg "  %mine = extractvalue { i64, i1 } %cx, 1")' '        (emitLine cg "  store atomic i64 %freed, ptr %sp seq_cst, align 8")
        (emitLine cg "  %mine = icmp eq i64 0, 0")'; then
  (cd "$repo_root" && gate_fixture_axc "$work/cc-free/axc" build --threads --opt 2 --input "$load" --output "$work/cc-free/load") > "$work/cc-free/load.build" 2>&1
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
  if ! (cd "$repo_root" && gate_fixture_axc "$axc" build --opt "$lvl" --input "$bitflip" --output "$bin") > "$bin.build" 2>&1; then
    bad "bitflip --opt $lvl did not build"; sed 's/^/    /' "$bin.build" | head -8; continue
  fi
  rc=0; ctl="$(gate_timeout 30 "$bin" -1 2>/dev/null | tail -1)" || rc=$?
  if [[ $rc -ne 0 || "$ctl" != a ]]; then
    bad "bitflip -O$lvl control: the unflipped handle answered '$ctl', exit $rc, not 'a'"; continue
  fi
  IFS='|' read -r det alias wrong <<<"$(flips "$bin")"
  if [[ -z "$wrong" && $(( det + $(wc -w <<<"$alias") )) -eq 64 ]]; then
    ok "bitflip -O$lvl: $det of 64 single-bit faults trap 85; the two words predict ${alias:-no} flip that spells the other live handle"
  else
    bad "bitflip -O$lvl: $det trapped 85, aliased [$alias], wrong [$wrong]"
  fi
done
if [[ -x "$work/cc-get/axc" ]]; then
  bin="$work/cc-get/bitflip"
  (cd "$repo_root" && gate_fixture_axc "$work/cc-get/axc" build --opt 2 --input "$bitflip" --output "$bin") > "$bin.build" 2>&1
  IFS='|' read -r det alias wrong <<<"$(flips "$bin")"
  if [[ -n "$wrong" ]]; then
    ok "bitflip ablated: red - with the state compares gone, $(( $(wc -w <<<"$wrong") )) flips neither trap nor alias"
  else
    bad "bitflip ablated: every flip still traps or aliases, so section 7 cannot see the table's compares"
  fi
else
  bad "bitflip ablated: the get ablation's compiler is missing, so section 7 has no negative"
fi

echo "== 8. owned descriptors: no poller or key reader leaks one under ulimit -n 256 =="
# tests/stdlib/786-poller-owned.ax makes and drops 300 pollers and 300
# key readers. Under a limit of 256 descriptors, a leak of one per owner
# runs out before either loop ends, and the counts it prints go wrong.
owned="$repo_root/tests/stdlib/786-poller-owned.ax"
bin="$work/poller-owned"
if (cd "$repo_root" && gate_fixture_axc "$axc" build --input "$owned" --output "$bin") > "$bin.build" 2>&1; then
  rc=0; got="$( (ulimit -n 256 && "$bin" </dev/null) 2>/dev/null)" || rc=$?
  if [[ $rc -eq 85 && "$got" == "$(cat "$repo_root/tests/stdlib/786-poller-owned.out")" ]]; then
    ok "300 pollers and 300 key readers under ulimit -n 256 leave no descriptor, and a closed poller traps 85"
  else
    bad "owned descriptors under ulimit -n 256: exit $rc, output '$(tr '\n' ' ' <<<"$got")'"
  fi
else
  bad "tests/stdlib/786-poller-owned.ax did not build"; sed 's/^/    /' "$bin.build" | head -8
fi

echo "== 9. a guessed word is not a live handle, and safe code may not forge one =="
# The fixture's own bytes say where the refusals belong: every line
# holding `(cast Spawn` or `(cast Job` (its alias) inside a declaration
# with no `effect(unsafe)` tag, except a cast of a value that already is
# a `Spawn` - `same`'s, whose parameter the signature types `Spawn`.
forge_fx="$repo_root/tests/diagnostics/1260-spawn-forging-cast.ax"
want_forge="$(python3 - "$forge_fx" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
tagged, sig, out = False, "", []
for i, line in enumerate(lines, 1):
    if line.startswith("(::"):
        tagged, sig = False, line
    elif line.startswith(";@axiom:effect(unsafe)"):
        tagged = True
    if re.search(r"\(as .* (Spawn|Job)\)", line) and not tagged and "(-> Spawn Spawn)" not in sig:
        out.append(str(i))
print(" ".join(out))
PY
)"
rc=0
(cd "$repo_root/tests/diagnostics" && "$axc" --diagnostic-format=ai check 1260-spawn-forging-cast.ax) > "$work/forge.log" 2>&1 || rc=$?
got_forge="$(grep -oE '^E AX3073 [^ :]+:[0-9]+' "$work/forge.log" | sed 's/.*://' | tr '\n' ' ' | sed 's/ $//')"
others="$(grep -cE '^[EW] ' "$work/forge.log" | tr -d ' ')"
if [[ $rc -ne 0 && -n "$want_forge" && "$got_forge" == "$want_forge" && "$others" == "$(wc -w <<<"$want_forge" | tr -d ' ')" ]]; then
  ok "1260: AX3073 at exactly lines $got_forge, the untagged forging casts the fixture holds, and nothing at the controls"
else
  bad "1260: check exit $rc, AX3073 at lines [$got_forge], wanted [$want_forge], $others diagnostic line(s)"
  head -4 "$work/forge.log" | sed 's/^/    /'
fi
printf '(import Task)\n\n(fn (main)\n  0)\n' > "$work/libforge.ax"
(cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" "$axc" --diagnostic-format=ai symbols libforge.ax) > "$work/libforge.axsym" 2>&1 || true
lib_rows="$(grep -cE '^F [A-Za-z:]*taskHandleOf .*#unsafe=trusted' "$work/libforge.axsym" || true)"
lib_casts="$(grep -cE '\(as .* Spawn\)' "$repo_root/stdlib/Task.ax")"
if [[ "$lib_rows" == 1 && "$lib_casts" == 1 ]]; then
  ok "the library's cast to Spawn is in taskHandleOf, marked #unsafe=trusted"
else
  bad "the library holds $lib_casts cast(s) to Spawn and $lib_rows trusted row(s) for taskHandleOf"
  grep -E 'HandleOf' "$work/libforge.axsym" | head -4 | sed 's/^/    /'
fi
# The scan: no guessed word names the live child, and its owner still
# joins it.
scan="$repo_root/tests/litmus/spawn-scan.ax"
scan_bin="$work/spawn-scan"
scan_want="scanned 400000 found 0
own word in range 0
joined 42"
if (cd "$repo_root" && gate_fixture_axc "$axc" build --opt 2 --input "$scan" --output "$scan_bin") > "$scan_bin.build" 2>&1; then
  rc=0; got="$(gate_timeout 120 "$scan_bin" 400000 2>/dev/null)" || rc=$?
  if [[ $rc -eq 0 && "$got" == "$scan_want" ]]; then
    ok "spawn-scan: none of the words 0 to 400,000 names the live child, and its owner joins it with 42"
  else
    bad "spawn-scan: exit $rc, '$(tr '\n' ';' <<<"$got")'"
  fi
else
  bad "spawn-scan did not build"; sed 's/^/    /' "$scan_bin.build" | head -6
fi
if ablate_cc salt '        (emitLine cg "  %g = select i1 %unused, i64 %gfirst, i64 %gnext")' '        (emitLine cg "  %g = add i64 %g0, 1")'; then
  (cd "$repo_root" && gate_fixture_axc "$work/cc-salt/axc" build --opt 2 --input "$scan" --output "$work/cc-salt/scan") > "$work/cc-salt/scan.build" 2>&1
  got="$(gate_timeout 120 "$work/cc-salt/scan" 400000 2>/dev/null)"
  (cd "$repo_root" && gate_fixture_axc "$work/cc-salt/axc" build --opt 2 --input "$bitflip" --output "$work/cc-salt/bitflip") > "$work/cc-salt/bitflip.build" 2>&1
  IFS='|' read -r det alias wrong <<<"$(flips "$work/cc-salt/bitflip")"
  if [[ "$(sed -n 2p <<<"$got")" == "own word in range 1" && -n "$alias" && -z "$wrong" ]]; then
    ok "salt: red - with every slot starting at generation 1, the scan finds the child's own word and bit $alias of one live word spells the other"
  else
    bad "salt: the ablated compiler's scan says '$(tr '\n' ';' <<<"$got")', aliased [$alias], wrong [$wrong] - the checks cannot see the salt"
  fi
else
  bad "salt: the compiler ablation did not apply or build"; tail -4 "$work/cc-salt/build.log" 2>/dev/null | sed 's/^/    /'
fi
ablate_file=typecheck.ax
if ablate_cc forge '      (if (strEq n "Spawn")
        1
        ; `evScalarName`' '      (if (strEq n "SpawnAblated")
        1
        ; `evScalarName`'; then
  rc=0
  (cd "$repo_root/tests/diagnostics" && "$work/cc-forge/axc" --diagnostic-format=ai check 1260-spawn-forging-cast.ax) > "$work/cc-forge/forge.log" 2>&1 || rc=$?
  # With the rule gone, `trusted`'s tag claims an operation its body no
  # longer performs, which is AX3010; what must vanish is every AX3073.
  if grep -q 'AX3010' "$work/cc-forge/forge.log" && ! grep -q 'AX3073' "$work/cc-forge/forge.log"; then
    ok "forge: red - with Spawn gone from the forging rule, the fixture draws no AX3073 (exit $rc) and section 9 would fail"
  else
    bad "forge: the ablated compiler still refuses the fixture (exit $rc) - section 9 cannot see the rule"
    head -4 "$work/cc-forge/forge.log" | sed 's/^/    /'
  fi
else
  bad "forge: the compiler ablation did not apply or build"; tail -4 "$work/cc-forge/build.log" 2>/dev/null | sed 's/^/    /'
fi
ablate_file=codegen.ax

echo "== portable resource counts: the ownership probes measure real handles =="
if python3 "$repo_root/tests/platform/resource-count.py" --axiom "$axc"; then
  ok "target-selected resource probes keep ownership goldens and refuse fabricated counts/errors"
else
  bad "portable resource-count probes"
fi

echo
if (( failed > 0 )); then
  echo "check-handles: $failed failed, $checks passed"
  exit 1
fi
echo "check-handles: $checks checks - a freed, forged or rejoined handle traps 85 at every --opt"
echo "               and in both lowerings, the table holds under concurrency, the"
echo "               capture rule holds in both lowerings, and every ablation goes red"
