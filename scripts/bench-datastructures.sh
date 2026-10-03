#!/usr/bin/env bash
# Compare Axiom's `Vec`, `Map` and `Intern` against the Rust equivalents
# the compiler currently uses, at the scale a self-hosted compiler works
# at.
#
# This is the throughput half of B3; the correctness half is
# `tests/stdlib/200-scale.ax`, which is a CI gate. This one prints a
# table rather than failing a build, because a wall-clock threshold on a
# shared CI runner is a flaky test. Pass `--check` to enforce the
# roadmap's "within 2x" exit criterion anyway. Timings are measured with
# hyperfine; see `web/bench/README.md` for the methodology (whole
# process, best of N, interleaved where commands are compared).
#
# METHODOLOGY, because the obvious way to write this measures the wrong
# thing in two directions at once:
#
#   - Both sides are timed as *whole processes*, doing identical work
#     and printing the same answer. Timing Rust with `Instant` inside
#     the process while timing Axiom with a shell clock compares a loop
#     against a loop plus `execve`, `mmap` and dynamic linking. At these
#     durations that gap is most of the measurement.
#
#   - Process startup is measured separately, with a program of each
#     language that does nothing, and subtracted. What remains is the
#     work, which is what the criterion is about.
#
#   - The Rust side reads its size from `argv` and passes every value
#     through `black_box`. Without that, `rustc` proves the sum of
#     `0..N` is a constant and deletes the loop - the first version of
#     this script reported Rust doing 100,000 pushes and reads in 200
#     microseconds, which is not a fast `Vec`, it is no `Vec` at all.
#
# Two asymmetries remain, and neither can be removed, so they are
# reported rather than hidden:
#
#   - Rust's default `HashMap` hasher is SipHash-1-3, which is
#     DoS-resistant and slower than the multiplicative hash
#     `stdlib/Map.ax` uses. `--fx` switches Rust to a fast
#     non-cryptographic hasher, which is the map a compiler would
#     actually pick, since a symbol table has no adversary. Read the
#     default run as flattering Axiom and the `--fx` run as the fair
#     one.
#
#   - The two sides free differently. Axiom bump-allocates from
#     `mmap`-ed chunks it never unmaps; a block whose count reaches zero
#     goes onto a per-size-class free list the next allocation of that
#     size reuses (docs/memory-model.md MM-ALLOC-2, MM-LIFE-2e). Rust's
#     `Drop` returns memory to the system allocator. (This line said
#     Axiom "never frees" until 2026-09-26, which stopped being true when
#     the release path landed.)
#
# A RATIO IS ONLY PRINTED WHEN BOTH SIDES WERE MEASURED, and until
# 2026-09-26 it was printed regardless. Each side's work is its best
# whole-process time minus its best empty-process time, and when launch
# jitter exceeded the work that difference went to zero or below and was
# clamped to one microsecond - so `N=100000 REPS=3` reported Vec at
# "1204.00x", a ratio over an invented denominator, and `--check` would
# have failed the build on it; the default scale then hit the floor on
# the OTHER side and reported 0.00x. Now:
#
#   - Both programs read N and a round count R from argv, so neither
#     compiler can fold the workload (the Axiom side used to have N
#     compiled in), and both print a checksum the script requires to
#     equal the closed form for (N, R) - equal work, verified, not
#     assumed.
#   - A side's work is CONCLUSIVE only when it is at least its own
#     launch cost and at least ten times the launch jitter measured in
#     the same run. Until both sides are, R is multiplied by four (to
#     `RMAX`, 256 by default) and both are measured again; the table
#     reports time per round.
#   - A side that never becomes conclusive is reported INCONCLUSIVE,
#     with no ratio, and `--check` exits 3 for it: an unverifiable
#     bound is not a pass and not a failure of the bound.
#   - Every hyperfine sample - the empty programs' included - is kept as
#     JSON in the output directory (`BENCH_OUT`, or a fresh one whose
#     path is printed), not just the minima.
#
# Usage:
#   scripts/bench-datastructures.sh              # table only
#   scripts/bench-datastructures.sh --check      # enforce the 2x bound
#   scripts/bench-datastructures.sh --fx         # fast hasher on the Rust side
#   scripts/bench-datastructures.sh --opt=0      # axiom unoptimised
#   N=100000 scripts/bench-datastructures.sh     # a different scale
#   ROUNDS=4 RMAX=256 scripts/bench-datastructures.sh   # start and ceiling for R
#   BENCH_OUT=dir scripts/bench-datastructures.sh # keep the raw samples there

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

N="${N:-1000000}"
REPS="${REPS:-7}"
ROUNDS="${ROUNDS:-1}"
RMAX="${RMAX:-256}"
[[ "$N" =~ ^[1-9][0-9]*$ && "$REPS" =~ ^[1-9][0-9]*$ && "$ROUNDS" =~ ^[1-9][0-9]*$ \
   && "$RMAX" =~ ^[1-9][0-9]*$ ]] \
  || { echo "error: N, REPS, ROUNDS and RMAX must be positive integers" >&2; exit 2; }
check=0
fx=0
# Axiom's optimisation level. The Rust side is always `rustc -O`, so
# comparing against Axiom's default `-O0` measures the absence of an
# optimiser as much as the data structure. `--opt 2` is what the
# roadmap recommends for real work and is the level the criterion
# should be read at; `--opt 0` shows what the structures cost unaided.
opt="${OPT:-2}"
for arg in "$@"; do
  case "$arg" in
    --check) check=1 ;;
    --fx)    fx=1 ;;
    # `--gc` used to set a flag that was passed to the compiler,
    # silently ignored by it, and then printed in the results banner -
    # so the table said "axiom under --gc" while measuring the bump
    # allocator. Refused rather than quietly dropped: a benchmark that
    # answers a question it did not measure is worse than one that
    # declines to.
    --gc)    echo "error: --gc was not ported to the self-hosted compiler; there is no collected variant to measure" >&2; exit 2 ;;
    --opt=*) opt="${arg#--opt=}" ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

command -v rustc > /dev/null || { echo "error: rustc not on PATH" >&2; exit 1; }
command -v "${HYPERFINE:-hyperfine}" > /dev/null || { echo "error: hyperfine not on PATH - timings are measured with it" >&2; exit 1; }

# ------------------------------------------------------------------
# The Axiom side. Each structure is its own program, so one's
# allocation behaviour cannot skew another's timing, and each does
# insert *and* lookup - the operation mix the criterion names.
# ------------------------------------------------------------------

# Each Axiom program reads N (argv 1) and a round count R (argv 2) at
# RUN time, builds a fresh structure R times, and prints the sum of what
# it read back - the checksum `measure` below holds to a closed form.
ax_args='(import Sys)
(import Str)
; argv[i] as an Int, 0 when it is absent or not a number
(:: argN (-> Int Int))
;@axiom:effect(io)
(fn (argN i)
  (match (strParseInt (sysArg i))
    ((Some n) n)
    ((None) 0)))'

cat > "$work/b_empty.ax" <<'AX'
(import IO)
(pub :: main Int)
;@axiom:effect(io)
(pub fn (main) { (println 0) 0 })
AX

cat > "$work/b_vec.ax" <<AX
(import IO)
(import Vec)
$ax_args
(:: push (-> (Vec Int) Int Int (Vec Int)))
(fn (push v lo hi)
  (if (>= lo hi) v { (vecPush v lo) (push v (+ lo 1) hi) }))
(:: sum (-> (Vec Int) Int Int Int Int))
(fn (sum v lo hi acc)
  (if (>= lo hi) acc (sum v (+ lo 1) hi (+ acc (vecGet v lo)))))
(:: rounds (-> Int Int Int Int))
(fn (rounds n r acc)
  (if (<= r 0) acc (rounds n (- r 1) (+ acc (sum (push vecNew 0 n) 0 n 0)))))
(:: main Int)
;@axiom:effect(io)
(fn (main) { (println (rounds (argN 1) (argN 2) 0)) 0 })
AX

cat > "$work/b_map.ax" <<AX
(import IO)
(import Map)
$ax_args
(:: ins (-> Map Int Int Map))
(fn (ins m lo hi)
  (if (>= lo hi) m { (mapInsert m lo (* lo 3)) (ins m (+ lo 1) hi) }))
(:: look (-> Map Int Int Int Int))
(fn (look m lo hi acc)
  (if (>= lo hi) acc (look m (+ lo 1) hi (+ acc (mapGet m lo 0)))))
(:: rounds (-> Int Int Int Int))
(fn (rounds n r acc)
  (if (<= r 0) acc (rounds n (- r 1) (+ acc (look (ins mapNew 0 n) 0 n 0)))))
(:: main Int)
;@axiom:effect(io)
(fn (main) { (println (rounds (argN 1) (argN 2) 0)) 0 })
AX

cat > "$work/b_intern.ax" <<AX
(import IO)
(import Intern)
(import Fmt)
$ax_args
(:: nm (-> Int String))
(fn (nm i) (concat "sym" (fmtInt i)))
(:: fill (-> Int Int Int Int))
(fn (fill it lo hi)
  (if (>= lo hi) it { (internIntern it (nm lo)) (fill it (+ lo 1) hi) }))
(:: relook (-> Int Int Int Int Int))
(fn (relook it lo hi acc)
  (if (>= lo hi) acc (relook it (+ lo 1) hi (+ acc (internIntern it (nm lo))))))
(:: rounds (-> Int Int Int Int))
(fn (rounds n r acc)
  (if (<= r 0) acc (rounds n (- r 1) (+ acc (relook (fill internNew 0 n) 0 n 0)))))
(:: main Int)
;@axiom:effect(io)
(fn (main) { (println (rounds (argN 1) (argN 2) 0)) 0 })
AX

# ------------------------------------------------------------------
# The Rust side. N and R come from argv and every value goes through
# `black_box`, so none of these loops can be folded away.
# ------------------------------------------------------------------

hasher_prelude=""
map_new="HashMap::new()"
if [[ $fx -eq 1 ]]; then
  hasher_prelude='
#[derive(Default, Clone, Copy)]
struct Fx(u64);
impl std::hash::Hasher for Fx {
    fn finish(&self) -> u64 { self.0 }
    fn write(&mut self, bytes: &[u8]) { for &b in bytes { self.add(b as u64) } }
    fn write_u8(&mut self, i: u8) { self.add(i as u64) }
    fn write_u64(&mut self, i: u64) { self.add(i) }
    fn write_usize(&mut self, i: usize) { self.add(i as u64) }
    fn write_i64(&mut self, i: i64) { self.add(i as u64) }
}
impl Fx {
    #[inline]
    fn add(&mut self, w: u64) {
        self.0 = (self.0.rotate_left(5) ^ w).wrapping_mul(0x51_7c_c1_b7_27_22_0a_95);
    }
}
#[derive(Default, Clone, Copy)]
struct FxBuild;
impl std::hash::BuildHasher for FxBuild {
    type Hasher = Fx;
    fn build_hasher(&self) -> Fx { Fx::default() }
}
'
  map_new="HashMap::with_hasher(FxBuild)"
fi

common_head="
use std::collections::HashMap;
use std::hint::black_box;
$hasher_prelude
fn arg(i: usize) -> i64 { std::env::args().nth(i).unwrap().parse().unwrap() }
"

cat > "$work/b_empty.rs" <<RS
$common_head
fn main() { println!("{}", black_box(0)); }
RS

cat > "$work/b_vec.rs" <<RS
$common_head
fn main() {
    let (n, r) = (arg(1), arg(2));
    let mut acc: i64 = 0;
    for _ in 0..r {
        let mut v: Vec<i64> = Vec::new();
        for k in 0..n { v.push(black_box(k)); }
        for k in 0..n { acc = acc.wrapping_add(black_box(v[k as usize])); }
    }
    println!("{}", acc);
}
RS

cat > "$work/b_map.rs" <<RS
$common_head
fn main() {
    let (n, r) = (arg(1), arg(2));
    let mut acc: i64 = 0;
    for _ in 0..r {
        let mut m = $map_new;
        for k in 0..n { m.insert(black_box(k), black_box(k * 3)); }
        for k in 0..n { acc = acc.wrapping_add(*m.get(&black_box(k)).unwrap_or(&0)); }
    }
    println!("{}", acc);
}
RS

# The interner a Rust compiler actually writes: text -> id, plus a
# vector from id back to text.
cat > "$work/b_intern.rs" <<RS
$common_head
fn main() {
    let (n, r) = (arg(1), arg(2));
    let mut acc: usize = 0;
    for _ in 0..r {
        let mut ids = $map_new;
        let mut strs: Vec<String> = Vec::new();
        for k in 0..n {
            let s = format!("sym{}", black_box(k));
            let next = strs.len();
            let id = *ids.entry(s.clone()).or_insert(next);
            if id == next { strs.push(s); }
        }
        for k in 0..n {
            let s = format!("sym{}", black_box(k));
            acc = acc.wrapping_add(*ids.get(&s).unwrap_or(&0));
        }
    }
    println!("{}", acc);
}
RS

echo "building..."
for b in empty vec map intern; do
  rustc -O -o "$work/rs_$b" "$work/b_$b.rs" 2>"$work/rustc.log" || {
    echo "error: could not build the Rust $b benchmark" >&2
    tail -20 "$work/rustc.log" >&2; exit 1
  }
  build=("$axiom" build)
  "${build[@]}" --opt "$opt" --input "$work/b_$b.ax" --output "$work/ax_$b" \
    >"$work/build.log" 2>&1 || {
    echo "error: could not build the Axiom $b benchmark" >&2
    tail -20 "$work/build.log" >&2; exit 1
  }
done

out_dir="${BENCH_OUT:-}"
if [[ -z "$out_dir" ]]; then
  out_dir="$(mktemp -d "${TMPDIR:-/tmp}/axiom-bench-datastructures.XXXXXX")"
fi
mkdir -p "$out_dir"

# Every sample of one command, kept: hyperfine's JSON, one warmup, then
# REPS timed runs, into `$out_dir/<label>.json`. Prints nothing.
sample() {  # <label> <command...>
  local label="$1"; shift
  "${HYPERFINE:-hyperfine}" --warmup 1 --runs "$REPS" --style none \
    --export-json "$out_dir/$label.json" "$(printf '%q ' "$@")" >/dev/null 2>&1 \
    || { echo "error: hyperfine could not run $label" >&2; exit 1; }
}

# `min max` of a label's samples, in seconds.
spread() {  # <label>
  python3 -c 'import json,sys
t = json.load(open(sys.argv[1]))["results"][0]["times"]
print(f"{min(t):.6f} {max(t):.6f}")' "$out_dir/$1.json"
}

# The checksum each program must print for N and R: the sum of what one
# round reads back, R times. Vec reads k back, Map 3k, and the interner
# the ids 0..N-1 - on both sides, which is what makes the work equal.
expect() {  # <structure> <rounds>
  python3 -c 'import sys
n, r, b = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
base = n * (n - 1) // 2
print(r * (3 * base if b == "map" else base))' "$N" "$2" "$1"
}

sample ax_empty "$work/ax_empty"
sample rs_empty "$work/rs_empty" "$N" 1
read -r ax_s0 ax_s1 <<< "$(spread ax_empty)"
read -r rs_s0 rs_s1 <<< "$(spread rs_empty)"

printf '\n%-9s %4s %12s %12s %8s  %s\n' structure R "axiom/round" "rust/round" ratio verdict
printf '%s\n' "----------------------------------------------------------------"

status=0
inconclusive=0
for b in vec map intern; do
  r="$ROUNDS"
  while :; do
    want="$(expect "$b" "$r")"
    ax_got="$("$work/ax_$b" "$N" "$r")"
    rs_got="$("$work/rs_$b" "$N" "$r")"
    if [[ "$ax_got" != "$want" || "$rs_got" != "$want" ]]; then
      echo "error: $b at N=$N R=$r: axiom printed '$ax_got', rust '$rs_got', both must print $want" >&2
      echo "       - the two programs did not do the same work, so no timing of them compares" >&2
      exit 1
    fi
    sample "ax_${b}_r$r" "$work/ax_$b" "$N" "$r"
    sample "rs_${b}_r$r" "$work/rs_$b" "$N" "$r"
    read -r ax_w0 _ <<< "$(spread "ax_${b}_r$r")"
    read -r rs_w0 _ <<< "$(spread "rs_${b}_r$r")"
    read -r ax_t rs_t ratio verdict <<EOF
$(python3 -c '
import sys
ax_w0, ax_s0, ax_s1, rs_w0, rs_s0, rs_s1, r = map(float, sys.argv[1:8])
def work(w0, s0, s1):
    # the work, and whether it stands clear of launch cost and jitter
    w = w0 - s0
    return w, w >= s0 and w >= 10 * (s1 - s0) and w > 0
ax, ax_ok = work(ax_w0, ax_s0, ax_s1)
rs, rs_ok = work(rs_w0, rs_s0, rs_s1)
if ax_ok and rs_ok:
    q = ax / rs
    print(f"{ax / r * 1000:.3f}ms {rs / r * 1000:.3f}ms {q:.2f}x", "within" if q <= 2.0 else "OVER")
else:
    print(f"{max(ax, 0) / r * 1000:.3f}ms {max(rs, 0) / r * 1000:.3f}ms - INCONCLUSIVE")
' "$ax_w0" "$ax_s0" "$ax_s1" "$rs_w0" "$rs_s0" "$rs_s1" "$r")
EOF
    if [[ "$verdict" != INCONCLUSIVE ]] || (( r * 4 > RMAX )); then break; fi
    r=$(( r * 4 ))
  done
  case "$verdict" in
    within) verdict="within 2x" ;;
    OVER) verdict="OVER 2x"; [[ $check -eq 1 ]] && status=1 ;;
    INCONCLUSIVE)
      verdict="INCONCLUSIVE: the work never cleared launch cost and 10x its jitter by R=$r"
      inconclusive=1 ;;
  esac
  printf '%-9s %4s %12s %12s %8s  %s\n' "$b" "$r" "$ax_t" "$rs_t" "$ratio" "$verdict"
done

printf '\nn=%s, axiom --opt %s vs rustc -O, best of %s runs after one warmup, ' "$N" "$opt" "$REPS"
printf 'startup subtracted (axiom %ss, rust %ss best; jitter %ss, %ss)' \
  "$ax_s0" "$rs_s0" "$(python3 -c "print(f'{$ax_s1 - $ax_s0:.6f}')")" "$(python3 -c "print(f'{$rs_s1 - $rs_s0:.6f}')")"
[[ $fx -eq 1 ]] && printf ', rust using a fast non-cryptographic hasher'
printf '\nchecksums verified on both sides; raw samples in %s\n' "$out_dir"

if [[ $check -eq 1 && $status -eq 0 && $inconclusive -eq 1 ]]; then
  echo "check: a structure was INCONCLUSIVE, so the 2x bound was not verified for it (exit 3)" >&2
  exit 3
fi
exit $status
