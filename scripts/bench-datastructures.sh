#!/usr/bin/env bash
# Compare Axiom's `Vec`, `Map` and `Intern` against the Rust equivalents
# the compiler currently uses, at the scale a self-hosted compiler works
# at.
#
# This is the throughput half of B3; the correctness half is
# `tests/stdlib/200-scale.ax`, which is a CI gate. This one prints a
# table rather than failing a build, because a wall-clock threshold on a
# shared CI runner is a flaky test. Pass `--check` to enforce the
# roadmap's "within 2x" exit criterion anyway.
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
#   - Axiom allocates from a bump allocator and never frees, so it does
#     no deallocation work at all, while Rust's `Drop` runs. There is no
#     longer a collected variant to measure against: the Rust
#     compiler's `--gc` was not ported (the self-hosting record), so
#     this comparison is bump-allocator-versus-Drop and says so.
#
# Usage:
#   scripts/bench-datastructures.sh              # table only
#   scripts/bench-datastructures.sh --check      # enforce the 2x bound
#   scripts/bench-datastructures.sh --fx         # fast hasher on the Rust side
#   scripts/bench-datastructures.sh --opt=0      # axiom unoptimised
#   N=100000 scripts/bench-datastructures.sh     # a different scale

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

N="${N:-1000000}"
REPS="${REPS:-7}"
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

# ------------------------------------------------------------------
# The Axiom side. Each structure is its own program, so one's
# allocation behaviour cannot skew another's timing, and each does
# insert *and* lookup - the operation mix the criterion names.
# ------------------------------------------------------------------

cat > "$work/b_empty.ax" <<'AX'
(import IO)
(pub :: main Int)
;@axiom:effect(io)
(pub fn (main) { (println 0) 0 })
AX

cat > "$work/b_vec.ax" <<AX
(import IO)
(import Vec)
(pub :: bN Int)
(pub fn (bN) $N)
(pub :: push (-> Int Int Int Int))
(pub fn (push v lo hi)
  (if (>= lo hi) v { (vecPush v lo) (push v (+ lo 1) hi) }))
(pub :: sum (-> Int Int Int Int Int))
(pub fn (sum v lo hi acc)
  (if (>= lo hi) acc (sum v (+ lo 1) hi (+ acc (vecGet v lo)))))
(pub :: main Int)
;@axiom:effect(io)
(pub fn (main)
  (let ((v (push vecNew 0 (bN))))
    { (println (sum v 0 (bN) 0)) 0 }))
AX

cat > "$work/b_map.ax" <<AX
(import IO)
(import Map)
(pub :: bN Int)
(pub fn (bN) $N)
(pub :: ins (-> Int Int Int Int))
(pub fn (ins m lo hi)
  (if (>= lo hi) m { (mapInsert m lo (* lo 3)) (ins m (+ lo 1) hi) }))
(pub :: look (-> Int Int Int Int Int))
(pub fn (look m lo hi acc)
  (if (>= lo hi) acc (look m (+ lo 1) hi (+ acc (mapGet m lo 0)))))
(pub :: main Int)
;@axiom:effect(io)
(pub fn (main)
  (let ((m (ins mapNew 0 (bN))))
    { (println (look m 0 (bN) 0)) 0 }))
AX

cat > "$work/b_intern.ax" <<AX
(import IO)
(import Intern)
(import Str)
(import Fmt)
(pub :: bN Int)
(pub fn (bN) $N)
; `nm` answers a String. It was declared `(-> Int Int)` and had been
; since it was written: the String/Int fiat made the two
; interchangeable, and deleting the fiat (2026-08-15) left this probe
; type-erroring with nothing running it - `bench-` scripts are not
; `check-` gates. Found by the printing sweep, which had to touch this
; file anyway.
(pub :: nm (-> Int String))
(pub fn (nm i) (strConcat "sym" (fmtInt i)))
(pub :: fill (-> Int Int Int Int))
(pub fn (fill it lo hi)
  (if (>= lo hi) it { (internIntern it (nm lo)) (fill it (+ lo 1) hi) }))
(pub :: relook (-> Int Int Int Int Int))
(pub fn (relook it lo hi acc)
  (if (>= lo hi) acc (relook it (+ lo 1) hi (+ acc (internIntern it (nm lo))))))
(pub :: main Int)
;@axiom:effect(io)
(pub fn (main)
  (let ((it (fill internNew 0 (bN))))
    { (println (relook it 0 (bN) 0)) 0 }))
AX

# ------------------------------------------------------------------
# The Rust side. `n` comes from argv and every value goes through
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
fn n() -> i64 { std::env::args().nth(1).unwrap().parse().unwrap() }
"

cat > "$work/b_empty.rs" <<RS
$common_head
fn main() { println!("{}", black_box(0)); }
RS

cat > "$work/b_vec.rs" <<RS
$common_head
fn main() {
    let n = n();
    let mut v: Vec<i64> = Vec::new();
    for k in 0..n { v.push(black_box(k)); }
    let mut acc: i64 = 0;
    for k in 0..n { acc = acc.wrapping_add(black_box(v[k as usize])); }
    println!("{}", acc);
}
RS

cat > "$work/b_map.rs" <<RS
$common_head
fn main() {
    let n = n();
    let mut m = $map_new;
    for k in 0..n { m.insert(black_box(k), black_box(k * 3)); }
    let mut acc: i64 = 0;
    for k in 0..n { acc = acc.wrapping_add(*m.get(&black_box(k)).unwrap_or(&0)); }
    println!("{}", acc);
}
RS

# The interner a Rust compiler actually writes: text -> id, plus a
# vector from id back to text.
cat > "$work/b_intern.rs" <<RS
$common_head
fn main() {
    let n = n();
    let mut ids = $map_new;
    let mut strs: Vec<String> = Vec::new();
    for k in 0..n {
        let s = format!("sym{}", black_box(k));
        let next = strs.len();
        let id = *ids.entry(s.clone()).or_insert(next);
        if id == next { strs.push(s); }
    }
    let mut acc: usize = 0;
    for k in 0..n {
        let s = format!("sym{}", black_box(k));
        acc = acc.wrapping_add(*ids.get(&s).unwrap_or(&0));
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

# Best-of-REPS wall clock, in seconds. Best rather than mean: the
# distribution is one-sided, since interference only ever makes a run
# slower, so the minimum is the closest estimate of the cost itself.
time_best() {
  python3 - "$REPS" "$@" <<'PY'
import subprocess, sys, time
reps = int(sys.argv[1])
cmd = sys.argv[2:]
best = None
for _ in range(reps):
    t = time.perf_counter()
    subprocess.run(cmd, stdout=subprocess.DEVNULL, check=True)
    d = time.perf_counter() - t
    best = d if best is None else min(best, d)
print(f"{best:.6f}")
PY
}

ax_startup="$(time_best "$work/ax_empty")"
rs_startup="$(time_best "$work/rs_empty" "$N")"

printf '\n%-9s %11s %11s %8s  %s\n' structure axiom rust ratio verdict
printf '%s\n' "---------------------------------------------------------"

status=0
for b in vec map intern; do
  ax_raw="$(time_best "$work/ax_$b")"
  rs_raw="$(time_best "$work/rs_$b" "$N")"
  read -r ax_t rs_t ratio within <<EOF
$(python3 -c "
ax = max($ax_raw - $ax_startup, 1e-6)
rs = max($rs_raw - $rs_startup, 1e-6)
print(f'{ax:.4f} {rs:.4f} {ax/rs:.2f} {1 if ax <= 2.0*rs else 0}')
")
EOF
  if [[ "$within" == 1 ]]; then
    verdict="within 2x"
  else
    verdict="OVER 2x"
    [[ $check -eq 1 ]] && status=1
  fi
  printf '%-9s %10ss %10ss %7sx  %s\n' "$b" "$ax_t" "$rs_t" "$ratio" "$verdict"
done

printf '\nn=%s, axiom --opt %s vs rustc -O, best of %s runs, startup subtracted ' "$N" "$opt" "$REPS"
printf '(axiom %ss, rust %ss)' "$ax_startup" "$rs_startup"
[[ $fx -eq 1 ]] && printf ', rust using a fast non-cryptographic hasher'
printf '\n'

exit $status
