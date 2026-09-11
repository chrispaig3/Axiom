#!/usr/bin/env bash
# Every trap owns its exit status, and the documents say which.
#
# The contract trap was designed on 75, moved to 76 on a merge, then to
# 77 on another merge - onto `__indexTrap`'s number - so two broken
# invariants shared one status while every party stayed green:
# `check-contracts.sh` asserted 77, `tests/stdlib/464-index-trap.exit`
# asserted 77, and no gate compared one trap's status to another's.
# `docs/error-model.md` and `docs/memory-model.md` stated the two owners
# of 77 in two tables neither of which read the other. The fix moved the
# contract trap to 80 (roadmap item 11, D3); this gate is what stops the
# next merge from moving anything onto anything else.
#
# Three facts, each read from a different artifact so a re-bless of one
# cannot satisfy another:
#
#   1. The emitter's census: every `emitRuntimeExit cg "<n>"` in
#      `self_host/codegen.ax` with a numeric operand is exactly
#      70 71 72 74 75 76 77 78 79 80, each once. `0` (normal exit) and
#      `%status` (the parallel join re-raising a child's status) are
#      dynamic sites, not traps, and are named rather than counted.
#   2. The documents' table: every `| NN |` row of the MM-EXEC-16 table
#      in `docs/memory-model.md` names the same ten statuses. A row
#      edited without its emitter - or an emitter moved without its
#      row - fails here rather than shipping a second collision.
#   3. The live exits: seven small programs each exit their own status
#      (70 OOM, 71 unhandled effect, 72 division by zero, 75 bad mark,
#      76 reset past a live handle, 77 index out of range, 80 violated
#      contract / subtype range). The seven answers must be pairwise
#      distinct - that distinctness IS the cross-trap comparison no
#      gate performed - and each must equal its documented owner.
#
# 74 (no syscall ABI), 78 (spawn refused) and 79 (parallel unsupported)
# are emitted, not executed: no runner reaches them, so section 3 cannot
# run them and section 4 holds their emit sites to the tree instead -
# the `define` lines `codegen.ax` writes - without duplicating the
# emission assertions `check-platform-constants.sh` (74) and
# `check-parallel.sh` (79) already own.
#
# The ablations doctor copies, not the tree: a census with 80 rewritten
# to 77 must fail the uniqueness check, and a docs table with its 80
# row rewritten to 77 must fail the docs-vs-emitter check. Both call
# the same comparison the real sections call, so a check that cannot
# fail would be the same defect one level up.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { checks=$((checks + 1)); echo "ok   $*"; }
bad() { checks=$((checks + 1)); failed=$((failed + 1)); echo "FAIL $*"; }

# stage1 resolves `(import Foo)` against its working directory, so the
# programs below run from a directory that can see the tree's stdlib.
ln -sfn "$repo_root/stdlib" "$work/stdlib"

# The ten trap statuses MM-EXEC-16 reserves. 73 is the FFI's, not the
# emitter's, so it is absent here by decision rather than by omission.
EXPECTED_TRAPS="70 71 72 74 75 76 77 78 79 80"

# Every numeric `emitRuntimeExit cg "<n>"` in a file, one per line,
# excluding the normal-exit `0` (a successful `main`, not a trap).
emitter_trap_list() {
  grep -oE 'emitRuntimeExit cg "[0-9]+"' "$1" \
    | grep -oE '[0-9]+' | grep -vx '0' | LC_ALL=C sort -n | uniq -c | awk '{print $2}'
}

echo "== 1. the emitter's trap census is exactly the ten reserved statuses =="
census="$work/census.txt"
emitter_trap_list "$repo_root/self_host/codegen.ax" > "$census"
# Distinctness first: a reused status shows up here as a missing one,
# because `uniq -c` collapses the pair and the count drops below ten.
got_n="$(wc -l < "$census" | tr -d ' ')"
if [[ "$got_n" != 10 ]]; then
  bad "emitter census found $got_n distinct numeric statuses, not 10: $(tr '\n' ' ' < "$census")"
else
  want="$work/want.txt"
  printf '%s\n' $EXPECTED_TRAPS | LC_ALL=C sort -n > "$want"
  if cmp -s "$want" "$census"; then
    ok "codegen.ax emits exactly $EXPECTED_TRAPS (plus dynamic 0 / %status)"
  else
    bad "emitter census [$(tr '\n' ' ' < "$census")] is not [$EXPECTED_TRAPS]"
  fi
fi
# The two dynamic sites exist and are not counted as traps.
if grep -q 'emitRuntimeExit cg "0"' "$repo_root/self_host/codegen.ax" \
&& grep -q 'emitRuntimeExit cg "%status"' "$repo_root/self_host/codegen.ax"; then
  ok "dynamic sites 0 and %status present and excluded from the trap set"
else
  bad "dynamic emitRuntimeExit sites 0 / %status missing from codegen.ax"
fi

echo "== 2. the MM-EXEC-16 table names the same ten statuses =="
# Rows read `| 70 |`, `| 80 |` at the start of the table. The parse is
# deliberately narrow: a status mentioned in prose elsewhere in the
# document must not satisfy it.
docs_traps="$work/docs.txt"
grep -oE '^\| 7[0-9] \|' "$repo_root/docs/memory-model.md" | grep -oE '[0-9]+' > "$work/docs7.txt" || true
grep -oE '^\| 80 \|' "$repo_root/docs/memory-model.md" | grep -oE '[0-9]+' > "$work/docs80.txt" || true
cat "$work/docs7.txt" "$work/docs80.txt" | LC_ALL=C sort -n -u > "$docs_traps"
if cmp -s <(printf '%s\n' $EXPECTED_TRAPS | LC_ALL=C sort -n) "$docs_traps"; then
  ok "MM-EXEC-16 table names $EXPECTED_TRAPS"
else
  bad "MM-EXEC-16 table names [$(tr '\n' ' ' < "$docs_traps")] not [$EXPECTED_TRAPS]"
fi

echo "== 3. seven traps exit their own statuses, all distinct =="
run_exit() { # <file> -> prints exit status
  local f="$1" rc=0
  ( cd "$work" && "$axc" run --opt 1 --input "$f" >"$work/run.out" 2>"$work/run.err" ) || rc=$?
  printf '%s' "$rc"
}

# Inline probes for the two traps with no dedicated stdlib fixture:
# division by zero (72) and a violated pre (80).
cat > "$work/div-zero.ax" <<'AX'
(fn (main) (/ 10 0))
AX
cat > "$work/pre-violated.ax" <<'AX'
;@axiom:pre((> n 0))
(:: half (-> Int Int))
(fn (half n) (/ n 2))
(fn (main) (half 0))
AX

got70="$(run_exit "$repo_root/tests/stdlib/314-out-of-memory.ax")"
got71="$(run_exit "$repo_root/tests/stdlib/310-effect-unhandled.ax")"
got72="$(run_exit "$work/div-zero.ax")"
got75="$(run_exit "$repo_root/tests/stdlib/166-arena-bad-mark.ax")"
got76="$(run_exit "$repo_root/tests/stdlib/167-arena-live-handle.ax")"
got77="$(run_exit "$repo_root/tests/stdlib/464-index-trap.ax")"
got80a="$(run_exit "$work/pre-violated.ax")"
got80b="$(run_exit "$repo_root/tests/selfhost/135-subtype-violated.ax")"

check_one() { # <want> <got> <name>
  if [[ "$2" == "$1" ]]; then ok "$3 exits $1";
  else bad "$3 exits $2, not $1"; fi
}
check_one 70 "$got70" "out-of-memory (314)"
check_one 71 "$got71" "unhandled effect (310)"
check_one 72 "$got72" "division by zero"
check_one 75 "$got75" "arena reset to an invalid mark (166)"
check_one 76 "$got76" "arena reset past a live handle (167)"
check_one 77 "$got77" "index out of range (464)"
check_one 80 "$got80a" "violated pre"
check_one 80 "$got80b" "subtype range violation (135)"

# The cross-trap comparison no gate performed: the seven answers must
# be seven different numbers. Each `check_one` above is internally
# consistent on its own - the 77 collision proved that is not enough.
seen="$work/seen.txt"
printf '%s\n' "$got70" "$got71" "$got72" "$got75" "$got76" "$got77" "$got80a" | LC_ALL=C sort -n -u > "$seen"
if [[ "$(wc -l < "$seen" | tr -d ' ')" == 7 ]]; then
  ok "seven traps, seven distinct statuses"
else
  bad "trap statuses collide: [$(tr '\n' ' ' < "$seen")]"
fi

echo "== 4. the emitted-only traps still have their emit sites =="
for sym in __axiom_no_syscall __axiom_par_spawn_failed __axiom_par_unsupported; do
  if grep -q "define internal i64 @$sym" "$repo_root/self_host/codegen.ax"; then
    ok "$sym defined in codegen.ax (74/78/79 emitted, not executed)"
  else
    bad "$sym missing from codegen.ax"
  fi
done

echo "== ablations: a reused status must be refused =="
# A. the emitter reuses 77 for the contract trap: 80 vanishes, 77
# appears twice, the distinct census drops to nine.
cp "$repo_root/self_host/codegen.ax" "$work/abl-codegen.ax"
sed -i.bak 's/emitRuntimeExit cg "80"/emitRuntimeExit cg "77"/' "$work/abl-codegen.ax"
emitter_trap_list "$work/abl-codegen.ax" > "$work/abl-census.txt"
if [[ "$(wc -l < "$work/abl-census.txt" | tr -d ' ')" == 10 ]] \
&& cmp -s <(printf '%s\n' $EXPECTED_TRAPS | LC_ALL=C sort -n) "$work/abl-census.txt"; then
  bad "ablation: census with 80->77 still accepted (this gate cannot fail that way)"
else
  ok "ablation: census with 80->77 refused"
fi
# B. the documents accept the collision: the 80 row rewritten to 77.
cp "$repo_root/docs/memory-model.md" "$work/abl-mm.md"
sed 's/^\| 80 \|/| 77 |/' "$repo_root/docs/memory-model.md" > "$work/abl-mm.md"
grep -oE '^\| 7[0-9] \|' "$work/abl-mm.md" | grep -oE '[0-9]+' > "$work/abl7.txt" || true
grep -oE '^\| 80 \|' "$work/abl-mm.md" | grep -oE '[0-9]+' > "$work/abl80.txt" || true
cat "$work/abl7.txt" "$work/abl80.txt" | LC_ALL=C sort -n -u > "$work/abl-docs.txt"
if cmp -s <(printf '%s\n' $EXPECTED_TRAPS | LC_ALL=C sort -n) "$work/abl-docs.txt"; then
  bad "ablation: docs table with 80->77 still accepted (this gate cannot fail that way)"
else
  ok "ablation: docs table with 80->77 refused"
fi

echo
if (( failed )); then
  echo "check-trap-statuses: $checks checks, $failed FAILED"
  exit 1
fi
echo "check-trap-statuses: all $checks checks passed"
