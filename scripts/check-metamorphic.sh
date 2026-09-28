#!/usr/bin/env bash
# Metamorphic compiler testing: a declaration nothing uses changes
# nothing else the compiler says about a program.
#
#   scripts/check-metamorphic.sh            # the corpora, every push
#   scripts/check-metamorphic.sh --long     # also the compiler and every
#                                           # stdlib module as an entry file
#
# WHY. Every other gate holds the compiler to answers somebody wrote
# down: an exit status, a golden, a fixed point. None of them can see a
# name one part of a program uses leaking into another part, because
# no fixture was written with the colliding name in it. This one
# supplies the collision. For every program the compiler accepts it
# appends top-level functions nobody calls, named like the names
# programs are full of (`a`, `e`, `k`, `t`, ...), each performing IO,
# and requires the compiler's answers about the ORIGINAL program to
# stay put (`scripts/lib/metamorphic.py` states the relation, R1 to R3):
# the verdict and diagnostics, every original declaration's `symbols`
# row, and every original function's emitted body.
#
# Its first run, on 2026-09-28, found three defects no gate had seen:
# `(cast a x)`'s type operand walked as a reference, a nullary function
# compiled in place of a parameter of the same name (wrong code:
# `tests/selfhost/1007-param-shadows-nullary.ax` answered 101 for 11,
# or faulted), and a named pattern's binders missing from the effect
# walk. `tests/selfhost/1006-cast-type-operand.ax` and `1007` pin them.
#
# FIVE SECTIONS.
#   1. The comparator's selftest: each of R1-R3 reported on a planted
#      difference, the two runtime tables that enumerate every function
#      allowed to differ, fresh type variables compared by order.
#   2. The relation over tests/stdlib, tests/selfhost and examples.
#      A floor on the files that were actually tested, so a glob that
#      stops matching can't pass by testing nothing.
#   2b. The second relation: reversing a program's top-level
#      declarations (imports first, a `::` with its `fn`) changes
#      neither its verdict nor any `symbols` row. Two programs a
#      reordering refuses are known defects (AN-39, AN-40): each must
#      still fail exactly as recorded below, so a fix updates the list.
#   3. Three compilers each rebuilt with one of the fixes taken out
#      (`gate_build_tree`), and the relation required to FAIL under
#      each: the gate watches the defects it was built on.
#   4. `--long` only: the compiler's own entry module and every stdlib
#      module as an entry file (about two minutes more).
#
# WHAT IT CANNOT SEE. Only the names it adds, and only programs the
# compiler accepts: a refused program's free names are the names this
# adds, so its answer may rightly change (`tests/diagnostics/1009-
# macro-for-innermost.ax`). IR is compared as text.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

long=0
[[ "${1:-}" == "--long" ]] && long=1

checks=0
failed=0
ok()  { checks=$((checks + 1)); echo "ok   $*"; }
bad() { checks=$((checks + 1)); failed=$((failed + 1)); echo "FAIL $*"; }

lib="$repo_root/scripts/lib/metamorphic.py"
jobs="${AXIOM_GATE_JOBS:-4}"

echo "== 1. the comparator reports what it is built to report =="
if python3 "$lib" selftest >"$work/selftest.log" 2>&1; then
  ok "selftest: $(grep -c '^ok ' "$work/selftest.log") comparator checks"
else
  bad "the comparator's selftest failed"
  sed 's/^/     /' "$work/selftest.log"
fi

echo "== 2. an unused declaration changes nothing, over the corpora =="
corpus=()
while IFS= read -r f; do corpus+=("$f"); done < <(
  cd "$repo_root" && { ls tests/stdlib/*.ax tests/selfhost/*.ax; find examples -name '*.ax'; } | LC_ALL=C sort)
rc=0
( cd "$repo_root" && python3 "$lib" run --axiom "$axc" --jobs "$jobs" "${corpus[@]}" ) \
  >"$work/corpus.log" 2>&1 || rc=$?
summary="$(grep '^swept ' "$work/corpus.log" || true)"
kept="$(sed -nE 's/^swept [0-9]+ files: ([0-9]+) accepted.*/\1/p' <<<"$summary")"
if [[ $rc -eq 0 && -n "$kept" ]]; then
  ok "$summary"
else
  bad "the relation does not hold: ${summary:-no summary}"
  grep '^DIVERGED' "$work/corpus.log" | cut -c1-400 | sed 's/^/     /' || true
  tail -5 "$work/corpus.log" | sed 's/^/     /'
fi
# 333 programs kept it on 2026-09-28; the corpus only grows.
if [[ -n "$kept" && "$kept" -ge 300 ]]; then
  ok "$kept accepted programs tested, at least 300"
else
  bad "only ${kept:-0} accepted programs were tested; the floor is 300"
fi

echo "== 2b. reordering the declarations changes nothing, over the corpora =="
cat > "$work/reorder-known.txt" <<'KNOWN'
# path<TAB>the divergence it must still show, until fixed
tests/selfhost/381-macro-type-templates.ax	R1 AX3028 AX3028
tests/selfhost/770-over-application.ax	R1 AX3004
KNOWN
rc=0
( cd "$repo_root" && python3 "$lib" reorder --axiom "$axc" --jobs "$jobs" --known "$work/reorder-known.txt" "${corpus[@]}" ) \
  >"$work/reorder.log" 2>&1 || rc=$?
summary="$(grep '^reordered ' "$work/reorder.log" || true)"
permuted="$(sed -nE 's/^reordered [0-9]+ files: ([0-9]+) permuted.*/\1/p' <<<"$summary")"
held="$(sed -nE 's/.* ([0-9]+) known divergences held.*/\1/p' <<<"$summary")"
if [[ $rc -eq 0 && -n "$permuted" ]]; then
  ok "$summary"
else
  bad "the reorder relation does not hold: ${summary:-no summary}"
  grep -E '^(DIVERGED|FIXED|MISSING|UNPARSED)' "$work/reorder.log" | cut -c1-400 | sed 's/^/     /' || true
  tail -3 "$work/reorder.log" | sed 's/^/     /'
fi
# 259 permuted programs kept it on 2026-09-28. The known divergences
# are also the proof that the harness sees a verdict change.
if [[ -n "$permuted" && "$permuted" -ge 250 && "${held:-0}" -eq 2 ]]; then
  ok "$permuted reordered programs tested, at least 250, and both known divergences seen"
else
  bad "only ${permuted:-0} reordered programs tested (floor 250), ${held:-0} of 2 known divergences seen"
fi

echo "== 3. a compiler with a fix taken out fails the relation =="
trio=(tests/stdlib/020-fmt.ax tests/stdlib/070-vec.ax tests/stdlib/210-struct-variants.ax)
# `ablate <name> <file> <from> <to>`: rebuild from a copy of self_host/
# with one exact span replaced, and require section 2's relation to
# fail on the three programs above. A span that no longer matches
# exactly once is a failure of this gate, not a pass.
ablate() {
  local name="$1" file="$2" from="$3" to="$4"
  local dir="$work/ablate-$name"
  rm -rf "$dir"; mkdir -p "$dir"
  cp -R "$repo_root/self_host" "$dir/self_host"
  cp -R "$repo_root/stdlib" "$dir/stdlib"
  if ! python3 - "$dir/self_host/$file" "$from" "$to" <<'PY'
import sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if s.count(a) != 1:
    print("span occurs %d times" % s.count(a)); sys.exit(1)
open(p, 'w').write(s.replace(a, b))
PY
  then
    bad "ablation \`$name\`: its span is not in self_host/$file exactly once, so it watches nothing"
    return
  fi
  if ! gate_build_tree "$axc" "$dir" "$dir/stdlib" "$dir/axc" >"$dir/build.log" 2>&1; then
    bad "ablation \`$name\`: the ablated compiler did not build"
    head -20 "$dir/build.log" | sed 's/^/     /'
    return
  fi
  if ( cd "$repo_root" && AXIOM_STDLIB="$dir/stdlib" python3 "$lib" run --axiom "$dir/axc" --jobs "$jobs" "${trio[@]}" ) \
      >"$dir/run.log" 2>&1; then
    bad "ablation \`$name\`: the relation still holds with the fix taken out"
  else
    ok "ablation \`$name\`: $(grep -c '^DIVERGED' "$dir/run.log") of ${#trio[@]} programs diverge"
  fi
}

ablate "cast-operand" typecheck.ax \
  "(if (&& (== (nodeTag head) TAG_E_VAR) (&& (== (isCastLike (nodeAName head)) 1) (== (bsIsLocal bound (nodeAName head)) 0)))
            1
            0)" \
  "0"
ablate "param-first" codegen.ax \
  "(if (&& (isNullaryFnCg cg full) (< (paramIndexOf cg name) 0))" \
  "(if (isNullaryFnCg cg full)"
ablate "named-pattern" typecheck.ax \
  "          (if (== tag TAG_P_CONNAMED)
            (patBindersVec (nodeCVec pat) 0 acc)
            0))))))" \
  "          0)))))"

if (( long )); then
  echo "== 4. --long: the compiler and every stdlib module as an entry file =="
  rc=0
  mods=()
  while IFS= read -r f; do mods+=("$f"); done < <(cd "$repo_root" && find stdlib -name '*.ax' | LC_ALL=C sort)
  ( cd "$repo_root" && python3 "$lib" run --axiom "$axc" --jobs "$jobs" self_host/main.ax "${mods[@]}" ) \
    >"$work/long.log" 2>&1 || rc=$?
  if [[ $rc -eq 0 ]]; then
    ok "$(grep '^swept ' "$work/long.log")"
  else
    bad "the relation does not hold on the compiler or a stdlib module"
    grep '^DIVERGED' "$work/long.log" | cut -c1-400 | sed 's/^/     /' || true
  fi
else
  echo "== 4. skipped: --long runs the compiler and every stdlib module =="
fi

echo
if (( failed > 0 )); then
  echo "check-metamorphic: $failed of $checks checks failed"
  exit 1
fi
echo "check-metamorphic: $checks checks - an unused declaration changes nothing"
