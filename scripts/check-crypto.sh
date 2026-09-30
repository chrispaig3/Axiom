#!/usr/bin/env bash
# The cryptography suite's gate: known answers, negative cases, and the
# proof that each of those tests can fail.
#
# WHAT IT RUNS. Every `tests/crypto/NNN-*.ax` is a program that reads
# vector files from the directory named by its first argument, checks
# every case, and prints one line per suite: `<suite> ok`, or a `FAIL`
# line per failing case and `<suite> FAILED`. Its stdout must equal the
# `.out` beside it. The per-suite case counts go to stderr and are
# printed here, so the log says how many cases each suite ran; a suite
# that ran none prints `FAILED`, never `ok` (tests/crypto/Kat.ax).
#
# THE ABLATION. A known-answer test that cannot fail is the defect this
# repository keeps finding (a sweep that reads no files, a check under
# a stray `set -e`). So every test is run a second time against a COPY
# of the vectors in which the last hex digit of the last field of every
# case line has been changed. A test that still prints only `ok` lines
# there is reported as vacuous and fails the gate. A test that reads
# no vector file at all - one that checks built-in cases - says so with
# a `.novectors` marker beside it and is exempt from this half.
#
# LEVELS. `CRYPTO_OPTS` lists the optimisation levels each test is
# built at, default "1" (the compiler's default). The scheduled run
# sets "0 1 3": the constant-time kernels and the arithmetic they rely
# on must give the same answers whatever the optimiser did.
#
# Usage:
#   scripts/check-crypto.sh            # every test
#   scripts/check-crypto.sh 100-sha2   # tests whose name starts with this
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

filter="${1:-}"
opts="${CRYPTO_OPTS:-1}"
vectors="$repo_root/tests/crypto/vectors"
failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# The corrupted copy the ablation half runs against.
spoiled="$work/spoiled-vectors"
mkdir -p "$spoiled"
for f in "$vectors"/*.txt; do
  [[ -e "$f" ]] || continue
  python3 - "$f" "$spoiled/$(basename "$f")" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
out = []
for line in open(src, encoding="utf-8").read().split("\n"):
    if line and not line.startswith("#"):
        fields = line.split(" ")
        last = fields[-1]
        if last and last != "-":
            c = last[-1]
            flip = {"0": "1"}.get(c.lower(), "0")
            fields[-1] = last[:-1] + flip
        line = " ".join(fields)
    out.append(line)
open(dst, "w", encoding="utf-8").write("\n".join(out))
PY
done

shopt -s nullglob
tests=("$repo_root"/tests/crypto/[0-9]*.ax)
ran=0
for t in "${tests[@]}"; do
  name="$(basename "$t" .ax)"
  [[ -n "$filter" && "$name" != "$filter"* ]] && continue
  golden="${t%.ax}.out"
  if [[ ! -f "$golden" ]]; then
    bad "$name: no $name.out beside it"
    continue
  fi
  ran=$((ran + 1))
  for lvl in $opts; do
    bin="$work/$name.O$lvl"
    if ! (cd "$repo_root/tests/crypto" && "$axc" --diagnostic-format=ai build --input "$name.ax" --output "$bin" --opt "$lvl") >"$work/$name.build.log" 2>&1; then
      bad "$name --opt $lvl: does not build"
      sed 's/^/    /' "$work/$name.build.log" | head -20
      continue
    fi
    rc=0
    gate_timeout 900 "$bin" "$vectors" >"$work/$name.O$lvl.out" 2>"$work/$name.O$lvl.err" || rc=$?
    sed 's/^/    /' "$work/$name.O$lvl.err" | grep -E ': [0-9]+ passed, [0-9]+ failed$' || true
    if [[ $rc -eq 0 ]] && diff -u "$golden" "$work/$name.O$lvl.out" >"$work/$name.diff"; then
      ok "$name --opt $lvl"
    else
      bad "$name --opt $lvl: exit $rc"
      sed 's/^/    /' "$work/$name.diff" | head -40
      sed 's/^/    /' "$work/$name.O$lvl.err" | grep -v -E ': [0-9]+ passed, [0-9]+ failed$' | head -10 || true
    fi
  done
  # The ablation, at the first level only: it asks whether the test can
  # fail, which does not depend on the level.
  if [[ -f "${t%.ax}.novectors" ]]; then
    continue
  fi
  first="${opts%% *}"
  bin="$work/$name.O$first"
  [[ -x "$bin" ]] || continue
  rc=0
  gate_timeout 900 "$bin" "$spoiled" >"$work/$name.spoiled.out" 2>/dev/null || rc=$?
  if [[ $rc -ne 0 ]] && grep -q ' FAILED$' "$work/$name.spoiled.out"; then
    ok "$name fails on corrupted vectors ($(grep -c ' FAILED$' "$work/$name.spoiled.out") suite(s) caught it)"
  else
    bad "$name still passes with every expected value corrupted: it cannot fail"
  fi
done

if [[ $ran -eq 0 ]]; then
  bad "no test matched '${filter}'"
fi

# --------------------------------------------------------------------
echo
echo "== constant time: the IR each claimed kernel compiles to =="
# --------------------------------------------------------------------
# A function that handles secrets says which of its parameters are
# secret with `;@axiom:ct(a, *p)`. `scripts/lib/ct-taint.py` reads the
# IR `opt` produced for it - after inlining, so what was inlined is
# checked where it landed - and refuses a branch, a `select`, a memory
# index or a division that depends on a secret, and a secret handed to
# a function that makes no claim. Source that looks branchless is not
# the evidence; this is. The claims come from `axiom symbols`, which is
# the compiler's own reading of which declaration each tag is on.
#
# The IR is each test program's, at every level in CRYPTO_CT_OPTS: a
# kernel exists in a module only if something reaches it, and the tests
# are what reach them. So the last check is coverage - a claim that no
# test program's IR contains was never checked, and fails here.
ct_opts="${CRYPTO_CT_OPTS:-1 2 3}"
mkdir -p "$work/ct"
{
  for m in "$repo_root"/stdlib/Crypto/*.ax; do
    printf '(import Crypto.%s)\n' "$(basename "$m" .ax)"
  done
  printf '(:: main Int)\n(fn (main) 0)\n'
} > "$work/ct/claims.ax"
( cd "$work/ct" && AXIOM_STDLIB="$repo_root/stdlib" "$axc" --diagnostic-format=ai symbols claims.ax ) \
  > "$work/ct/claims.axsym" 2>"$work/ct/claims.err" || true
python3 - "$work/ct/claims.axsym" > "$work/ct/specs" <<'PY'
import re, sys, urllib.parse
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.startswith("F "):
        continue
    m = re.search(r"#ct=(\S+)", line)
    if not m:
        continue
    f = line.split(" ")
    mod = re.search(r"/stdlib/(.+)\.ax:", f[2])
    if not mod:
        continue
    params = urllib.parse.unquote(m.group(1)).replace(" ", "")
    print(f"{mod.group(1).replace('/', '.')}${f[1]}={params}")
PY
n_claims="$(grep -c . "$work/ct/specs" || true)"
if [[ "$n_claims" -eq 0 ]]; then
  bad "no ;@axiom:ct(...) claim found in stdlib/Crypto - the claims sweep read nothing"
else
  echo "     $n_claims constant-time claims in stdlib/Crypto"
  : > "$work/ct/checked"
  ct_specs=()
  while IFS= read -r spec; do ct_specs+=("$spec"); done < "$work/ct/specs"
  ct_fail=0
  for t in "${tests[@]}"; do
    name="$(basename "$t" .ax)"
    [[ -n "$filter" && "$name" != "$filter"* ]] && continue
    if ! (cd "$repo_root/tests/crypto" && "$axc" emit-llvm "$name.ax" -o "$work/ct/$name.ll") >/dev/null 2>&1; then
      continue
    fi
    for lvl in $ct_opts; do
      opt -O"$lvl" "$work/ct/$name.ll" -S -o "$work/ct/$name.O$lvl.ll" 2>/dev/null || continue
      # The specs go through an array, never an unquoted expansion: a
      # `*p` in one is a glob, and under this script's `nullglob` an
      # unmatched glob expands to nothing - which drops exactly the
      # claims about secret memory and checks the rest.
      if ! python3 "$repo_root/scripts/lib/ct-taint.py" --present-only "$work/ct/$name.O$lvl.ll" \
             "${ct_specs[@]}" > "$work/ct/$name.O$lvl.out" 2>&1; then
        ct_fail=1
        echo "     $name --opt $lvl:"
        grep -v '^checked \|^ok ' "$work/ct/$name.O$lvl.out" | sed 's/^/     /' | head -20
      fi
      sed -n 's/^checked //p' "$work/ct/$name.O$lvl.out" >> "$work/ct/checked"
    done
  done
  if [[ $ct_fail -eq 0 ]]; then
    ok "every claimed kernel a test reaches is free of secret-dependent branches, indices and divisions at --opt $ct_opts"
  else
    bad "a kernel's optimised IR contradicts its constant-time claim"
  fi
  LC_ALL=C sort -u "$work/ct/checked" > "$work/ct/checked.u"
  sed 's/=.*//' "$work/ct/specs" | LC_ALL=C sort -u > "$work/ct/claimed"
  unchecked="$(LC_ALL=C comm -23 "$work/ct/claimed" "$work/ct/checked.u")"
  if [[ -n "$filter" ]]; then
    echo "     coverage not asked: a filtered run reaches only some kernels"
  elif [[ -z "$unchecked" ]]; then
    ok "all $n_claims claims were checked in at least one test program's IR"
  else
    bad "claimed constant time, and no test program reaches it, so nothing checked it:"
    printf '%s\n' "$unchecked" | sed 's/^/     /'
  fi
fi

# The checker can fail: three functions that leak, each one way, must
# each be refused, at every level.
cat > "$work/ct/leaks.ax" <<'AX'
(import IO)
(import Mem)

(:: leakBranch (-> Int Int))
(fn (leakBranch x)
  (if (== x 5) 1 2))

(:: leakIndex (-> Int Int Int))
;@axiom:effect(unsafe)
(fn (leakIndex tbl x)
  (__load8 tbl (& x 255)))

(:: leakDivide (-> Int Int))
(fn (leakDivide x)
  (/ 1000 (| x 1)))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (+ (leakBranch 3) (+ (leakIndex (memAlloc 256) 7) (leakDivide 9))))
    0
  })
AX
if ( cd "$work/ct" && AXIOM_STDLIB="$repo_root/stdlib" "$axc" emit-llvm leaks.ax -o leaks.ll ) >/dev/null 2>&1; then
  for lvl in $ct_opts; do
    opt -O"$lvl" "$work/ct/leaks.ll" -S -o "$work/ct/leaks.O$lvl.ll" 2>/dev/null
    python3 "$repo_root/scripts/lib/ct-taint.py" "$work/ct/leaks.O$lvl.ll" \
      'leakBranch=x' 'leakIndex=x' 'leakDivide=x' > "$work/ct/leaks.O$lvl.out" 2>&1 || true
    caught="$(grep -c '^FAIL leak' "$work/ct/leaks.O$lvl.out" || true)"
    if [[ "$caught" -eq 3 ]]; then
      ok "the checker refuses a secret branch, index and division at --opt $lvl"
    else
      bad "the checker caught $caught of 3 planted leaks at --opt $lvl"
      sed 's/^/     /' "$work/ct/leaks.O$lvl.out" | head -10
    fi
  done
else
  bad "the planted-leak probe did not compile"
fi

echo
if [[ $failed -eq 0 ]]; then
  echo "check-crypto: all $checks checks passed"
else
  echo "check-crypto: $failed of $((checks + failed)) checks failed"
  exit 1
fi
