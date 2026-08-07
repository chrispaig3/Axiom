#!/usr/bin/env bash
# The self-hosted formatter is the same function as stage0's, measured.
#
# `self_host/format.ax` reimplements `axiom fmt` over its own scan and
# form tree, and its exit criterion is symmetric: on every input, stage0
# and stage1 `fmt` produce identical bytes AND identical exit status -
# either side may be the one that moves. A two-way diff cannot see a
# stage0 bug baked into stage1, so the zoo comparison is three-way
# against the checked-in golden (`tests/fmt/syntax-zoo.expected.ax`),
# the same golden `check-fmt.sh` pins for stage0 alone.
#
# Four sweeps, each with a counted floor so a glob that stops matching
# cannot report the silence it was looking for:
#
#   1. the zoo, three-way:  golden == stage0(zoo) == stage1(zoo)
#   2. every `.ax` in stdlib/, self_host/ and tests/: same status, and
#      identical bytes on success; plus `--check` status parity on the
#      unformatted copy
#   3. the parity bank, `tests/fmt/parity/*.axp`: deliberate refusals
#      and rewrites probed against the real stage0 binary when the
#      printer was written - same status, same bytes on success
#      (`.axp`, not `.ax`, so check-fmt.sh's every-file-formats sweep
#      does not trip over the refusals)
#   4. special cases a file cannot carry: an empty file formats to an
#      empty file with exit 0, a missing file exits 1, `--check` on a
#      dirty file exits 1 in either argument order and never writes
#
# Negative test, run by hand when the printer changes shape (ablation,
# never committed): drop one normalisation - e.g. make `fpType` print
# `Integer` verbatim instead of `Int` - rebuild stage1, and this gate
# must fail on sweep 2 (stdlib sources spell `Int`, the zoo pins the
# rewrite). Verified at introduction: the ablated printer fails 1 zoo
# + parity case while the unablated one passes everything.
#
# Known, deliberate residue (probed 2026-08-07): stage1 refuses a few
# shapes stage0 rewrites, all involving token sequences no real program
# contains - `(- -5)` and a bare top-level `- x` body (stage0's lexer
# emits two Minus tokens where the format scanner reads one operator
# run), spaced field/module chains (`p . x`, `X :: y`), and type-name
# keywords in expression position (`(g Int)`). Each refusal is safe
# (exit 1, no write); none appears in the corpus, and the parity bank
# deliberately contains none.
#
# Usage:  scripts/check-fmt-selfhost.sh

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "building the compiler first (no binary at $axiom)" >&2
  cargo build --release
fi

export AXIOM_STDLIB="$repo_root/stdlib"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# stage1 resolves imports relative to its working directory, like every
# other stage1 gate.
ln -s "$repo_root/stdlib" "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"

echo "== building stage1 =="
if ! "$axiom" build --input self_host/main.ax --output "$work/stage1" >"$work/build.log" 2>&1; then
  echo "FAIL: could not build stage1" >&2
  tail -20 "$work/build.log" >&2
  exit 1
fi

failed=0

# Run both formatters on copies of one input; report status parity and
# byte parity. $1 = label, $2 = path to the input.
compare_both() {
  local label="$1" src="$2"
  cp "$src" "$work/c0"
  cp "$src" "$work/c1.ax"
  "$axiom" fmt "$work/c0" >/dev/null 2>&1
  local s0=$?
  (cd "$work" && ./stage1 fmt c1.ax >/dev/null 2>&1)
  local s1=$?
  if [[ "$s0" != "$s1" ]]; then
    echo "FAIL $label: exit status diverged (stage0=$s0 stage1=$s1)"
    failed=$((failed + 1))
    return 1
  fi
  if [[ "$s0" == "0" ]] && ! cmp -s "$work/c0" "$work/c1.ax"; then
    echo "FAIL $label: formatted bytes differ"
    diff "$work/c0" "$work/c1.ax" | head -8 | sed 's/^/     /'
    failed=$((failed + 1))
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------
# 1. The zoo, three-way against the golden.
# ---------------------------------------------------------------
echo "== zoo: golden == stage0 == stage1 =="
golden="$repo_root/tests/fmt/syntax-zoo.expected.ax"
if [[ ! -s "$golden" ]]; then
  echo "FAIL the golden is missing or empty"
  failed=$((failed + 1))
else
  cp "$repo_root/tests/fmt/syntax-zoo.ax" "$work/zoo0.ax"
  cp "$repo_root/tests/fmt/syntax-zoo.ax" "$work/zoo1.ax"
  if ! "$axiom" fmt "$work/zoo0.ax" >/dev/null 2>&1; then
    echo "FAIL stage0 refused the zoo"
    failed=$((failed + 1))
  elif ! cmp -s "$work/zoo0.ax" "$golden"; then
    echo "FAIL stage0's zoo output is not the golden"
    failed=$((failed + 1))
  fi
  if ! (cd "$work" && ./stage1 fmt zoo1.ax >/dev/null 2>&1); then
    echo "FAIL stage1 refused the zoo"
    failed=$((failed + 1))
  elif ! cmp -s "$work/zoo1.ax" "$golden"; then
    echo "FAIL stage1's zoo output is not the golden"
    diff "$golden" "$work/zoo1.ax" | head -12 | sed 's/^/     /'
    failed=$((failed + 1))
  fi
fi

# ---------------------------------------------------------------
# 2. The corpus: identical bytes and status on every real file, and
#    `--check` status parity on the unformatted original.
# ---------------------------------------------------------------
echo "== corpus differential =="
swept=0
for f in $(find stdlib self_host tests -name '*.ax' | sort); do
  swept=$((swept + 1))
  compare_both "$f" "$f" || true
  # --check parity on the original bytes. Its verdict (already clean /
  # needs formatting / refusal) must agree too.
  cp "$f" "$work/k0"
  cp "$f" "$work/k1.ax"
  "$axiom" fmt --check "$work/k0" >/dev/null 2>&1
  k0=$?
  (cd "$work" && ./stage1 fmt --check k1.ax >/dev/null 2>&1)
  k1=$?
  if [[ "$k0" != "$k1" ]]; then
    echo "FAIL $f: --check status diverged (stage0=$k0 stage1=$k1)"
    failed=$((failed + 1))
  fi
done
echo "     $swept files swept"
if [[ $swept -lt 150 ]]; then
  echo "FAIL corpus sweep read $swept files; the floor is 150"
  failed=$((failed + 1))
fi

# ---------------------------------------------------------------
# 3. The parity bank.
# ---------------------------------------------------------------
echo "== parity bank =="
cases=0
for f in "$repo_root"/tests/fmt/parity/*.axp; do
  [[ -f "$f" ]] || continue
  cases=$((cases + 1))
  compare_both "parity/$(basename "$f")" "$f" || true
done
echo "     $cases cases"
if [[ $cases -lt 20 ]]; then
  echo "FAIL parity bank has $cases cases; the floor is 20"
  failed=$((failed + 1))
fi

# ---------------------------------------------------------------
# 4. The cases a file cannot carry.
# ---------------------------------------------------------------
echo "== driver special cases =="
: > "$work/empty0.ax"; : > "$work/empty1.ax"
"$axiom" fmt "$work/empty0.ax" >/dev/null 2>&1; e0=$?
(cd "$work" && ./stage1 fmt empty1.ax >/dev/null 2>&1); e1=$?
if [[ "$e0" != "0" || "$e1" != "0" ]]; then
  echo "FAIL an empty file must format with exit 0 (stage0=$e0 stage1=$e1)"
  failed=$((failed + 1))
fi

"$axiom" fmt "$work/does-not-exist.ax" >/dev/null 2>&1; m0=$?
(cd "$work" && ./stage1 fmt does-not-exist.ax >/dev/null 2>&1); m1=$?
if [[ "$m0" == "0" || "$m1" == "0" ]]; then
  echo "FAIL a missing file must refuse (stage0=$m0 stage1=$m1)"
  failed=$((failed + 1))
fi

printf '(fn  (f)   1)\n' > "$work/dirty.ax"
cp "$work/dirty.ax" "$work/dirty-orig"
(cd "$work" && ./stage1 fmt --check dirty.ax >/dev/null 2>&1); c1=$?
(cd "$work" && ./stage1 fmt dirty.ax --check >/dev/null 2>&1); c2=$?
if [[ "$c1" != "1" || "$c2" != "1" ]]; then
  echo "FAIL --check on a dirty file must exit 1 in both argument orders (got $c1, $c2)"
  failed=$((failed + 1))
fi
if ! cmp -s "$work/dirty.ax" "$work/dirty-orig"; then
  echo "FAIL --check wrote to the file"
  failed=$((failed + 1))
fi

echo
if [[ $failed -eq 0 ]]; then
  echo "fmt-selfhost: all checks passed"
else
  echo "fmt-selfhost: $failed check(s) failed"
  exit 1
fi
