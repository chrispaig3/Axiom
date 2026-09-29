#!/usr/bin/env bash
# THE RECLAMATION AND REUSE GATE (docs/assurance/requirements.md R-B7 to
# R-B9; docs/memory-model.md MM-LIFE-2e, MM-LIFE-2f, MM-ALLOC-22 to 25).
#
# What happens to memory, and to what memory stands for, when values die,
# when they die in a cycle, when an arena resets, and when a trap is
# contained. Six sections, each with the measurement that says it holds
# and a control or an ablation that says the measurement can fail:
#
#   1  deep destruction. `tests/stdlib/555-release-deep-chain.ax` drops
#      million-deep lists, trees and closure chains whole under a 64 KiB
#      stack. Controls: a 20,000-deep non-tail recursion dies under the
#      same limit (so the limit is in force), and the same fixture with
#      the release walk made recursive in its IR dies too.
#   2  fragmentation. A reset-free loop keeps 1,000 strings of random
#      length up to 60,000 bytes live and replaces one per iteration,
#      at 10^4, 10^5 and 10^6 iterations (10^7 with --long). Peak RSS
#      must plateau, the arena must hold under 2.5 times the live bytes,
#      and `__axiom_mem_stat 0` must agree with RSS. Control: with
#      MM-ALLOC-25's request rounding deleted from the IR, a smaller
#      loop must grow at least fourfold where the intact one doesn't.
#   3  cycles. Two-node knots dropped per iteration grow the backlog by
#      exactly 64 bytes a knot at two magnitudes, and RSS with it; the
#      same knots inside an arena scope, and an acyclic control, hold
#      RSS flat (MM-LIFE-2f's policy, measured).
#   4  resets. `tests/stdlib/559-reset-metadata.ax` at --opt 0 and 2,
#      and with the reset's list scrub deleted from its IR, which must
#      fail. Four threads resetting their own arenas with every class
#      filed, and the main thread's filed block surviving them; with the
#      lists made one global for every thread, that probe must fail.
#   5  resources beyond memory across 10,000 trap-and-recover cycles:
#      a file opened inside the extent leaks one descriptor a cycle,
#      which is the program's obligation (the control that closes first
#      holds flat); a forked child spawned inside the extent is swept
#      by the abort, which is the runtime's.
#   6  recovery points. `tests/stdlib/560-recover-record.ax` at four
#      levels; with the record moved back into the arena in the IR,
#      its first line must change.
#
# Timing is never asserted. Every RSS comparison is a ratio, and every
# ratio has a twin that must move.
#
#   scripts/check-reclaim-soak.sh          per push, under a minute
#   scripts/check-reclaim-soak.sh --long   adds the 10^7 soak (nightly)

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

long=0
[[ "${1:-}" == "--long" ]] && long=1

checks=0
failed=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

for t in llc cc python3; do
  command -v "$t" >/dev/null 2>&1 || { echo "FAIL: $t is not on PATH"; exit 1; }
done

# build <src> <out> [opt]
build() {
  "$axc" build --input "$1" --output "$2" --opt "${3:-1}" >"$2.build" 2>&1 \
    || { bad "$(basename "$1") did not build at --opt ${3:-1}"; sed 's/^/    /' "$2.build" | head -8; return 1; }
}

# build_mutated <src> <out> <kind>: the emitted IR with ONE named
# mutation, built through the driver's own steps at -O1.
build_mutated() {
  local src="$1" out="$2" kind="$3"
  "$axc" emit-llvm "$src" -o "$out.ll" >"$out.emit" 2>&1 \
    || { bad "$kind: emit-llvm failed"; return 1; }
  if ! python3 - "$kind" "$out.ll" "$out.mut.ll" >"$out.mutate" 2>&1 <<'PY'
import re, sys
kind, src_path, out_path = sys.argv[1:4]
src = open(src_path).read()
if kind == "recursive-release":
    # a dead child is released by a nested call instead of joining the
    # invocation's dead list: one machine frame per level of a chain
    out, n = re.subn(
        r"(relchild:\n(?:  .*\n)*?  %wval = load i64, ptr %waddrp\n)  store i64 %wval, ptr %cur\n  br label %relone\n",
        r"\1  call void @axiom_release(i64 %wval)\n  br label %walk\n", src)
elif kind == "no-rounding":
    # MM-ALLOC-25's request half: every request keeps its 16-byte size
    out, n = re.subn(r"  %rcbig = icmp ult i64 %rcoff, 64512\n",
                     "  %rcbig = icmp ult i64 %rcoff, 0\n", src)
elif kind == "no-scrub":
    # a reset that leaves the size-class lists as they were
    out, n = re.subn(
        r"  br label %slabclear\nslabclear:.*?br i1 %sdone, label %resetbody, label %slabclear\n",
        "  br label %resetbody\n", src, flags=re.S)
elif kind == "shared-slabs":
    # the size-class lists shared by every thread, the chunks still not
    out, n = re.subn(r"@__axiom_slabs = internal thread_local\(localexec\) global",
                     "@__axiom_slabs = internal global", src)
elif kind == "arena-record":
    # the recovery record back in the arena: each stack cell of 16 or
    # more words becomes an `axiom_alloc` of its size, never released
    cells = dict(re.findall(r"  (%[\w.]+) = alloca i64, i64 (\d+), align 16\n", src))
    cells = {c: int(w) for c, w in cells.items() if int(w) >= 16}
    out, n = src, 0
    for cell, words in cells.items():
        out, k = re.subn(r"  (%[\w.]+) = ptrtoint ptr " + re.escape(cell) + r" to i64\n",
                         r"  \1 = call i64 @axiom_alloc(i64 " + str(words * 8) + ")\n", out)
        n += k
    n = 1 if n >= 1 else 0
else:
    sys.exit("unknown mutation " + kind)
if n != 1:
    sys.exit("%s matched %d times, wanted 1" % (kind, n))
open(out_path, "w").write(out)
PY
  then
    bad "$kind: the mutation did not apply: $(cat "$out.mutate")"; return 1
  fi
  if cmp -s "$out.ll" "$out.mut.ll"; then bad "$kind: the mutation changed nothing"; return 1; fi
  opt -O1 "$out.mut.ll" -S -o "$out.opt.ll" 2>"$out.log" \
    && llc "$out.opt.ll" -filetype=obj -o "$out.o" -O1 -relocation-model=pic 2>>"$out.log" \
    && cc "$out.o" -o "$out" $link_entry 2>>"$out.log" \
    || { bad "$kind: the mutated IR did not build"; sed 's/^/    /' "$out.log" | head -5; return 1; }
}

# run_capped <stack-KiB> <cmd...>: exit status of the command under a
# soft stack limit, in a subshell so the limit ends with it.
run_capped() {
  local kib="$1"; shift
  ( ulimit -s "$kib" && "$@" >/dev/null 2>&1 )
}

ratio_ge() { python3 -c "import sys; sys.exit(0 if $1 >= $2 * $3 else 1)"; }

# Named numbers without associative arrays, which the bash 3.2 that
# macOS ships lacks: `setv key value`, `getv key`.
setv() { printf -v "v_${1//[^A-Za-z0-9_]/_}" '%s' "$2"; }
getv() { local n="v_${1//[^A-Za-z0-9_]/_}"; printf '%s' "${!n:-}"; }

# ---------------------------------------------------------------------
echo "== 1. deep destruction chains release in bounded stack =="
# ---------------------------------------------------------------------
deep=tests/stdlib/555-release-deep-chain
if build "$deep.ax" "$work/deep"; then
  got="$( ulimit -s 64 && "$work/deep" 2>/dev/null )"; rc=$?
  if (( rc == 0 )) && [[ "$got" == "$(cat "$deep.out")" ]]; then
    ok "555: five million-deep shapes dropped whole under a 64 KiB stack, each second round served by the first"
  else
    bad "555 under a 64 KiB stack exited $rc or printed something else"
  fi
fi
cat > "$work/nontail.ax" <<'AX'
; the control: a recursion that is NOT a tail call, 20,000 deep
(:: depth (-> Int Int))
(fn (depth n)
  (if (== n 0)
    0
    (+ 1 (depth (- n 1)))))
(:: main Int)
(fn (main)
  (if (== (depth 20000) 20000) 0 1))
AX
if build "$work/nontail.ax" "$work/nontail" 0; then
  "$work/nontail" >/dev/null 2>&1; rc_free=$?
  run_capped 64 "$work/nontail"; rc_cap=$?
  if (( rc_free == 0 && rc_cap >= 128 )); then
    ok "control: a 20,000-deep non-tail recursion runs at the default stack and dies under 64 KiB (signal exit $rc_cap)"
  else
    bad "control: the 64 KiB limit is not in force (default exit $rc_free, capped exit $rc_cap)"
  fi
fi
if build_mutated "$deep.ax" "$work/deep-rec" recursive-release; then
  run_capped 64 "$work/deep-rec"; rc=$?
  if (( rc >= 128 )); then
    ok "ablation: with the release walk recursing per level, 555 dies under 64 KiB (exit $rc)"
  else
    bad "ablation: a recursive release walk still passed under 64 KiB (exit $rc) - section 1 cannot see recursion"
  fi
fi

# ---------------------------------------------------------------------
echo "== 2. fragmentation: a reset-free soak of mixed sizes plateaus =="
# ---------------------------------------------------------------------
cat > "$work/soak.ax" <<'AX'
; args: iterations live maxLen. Prints the checksum, the live bytes,
; and the allocator's held and filed bytes (MM-ALLOC-24).
(import IO)
(import Sys)
(import Str)
(import Vec)

(:: next (-> Int Int))
(fn (next s)
  (% (+ (* s 1103515245) 12345) 2147483648))

(:: fill (-> (Vec String) Int Int Int))
(fn (fill v i n)
  (if (>= i n)
    0
    {
      (vecPush v (strAlloc 1))
      (fill v (+ i 1) n)
    }))

(:: churn (-> (Vec String) Int Int Int Int Int Int))
(fn (churn v k live maxLen seed acc)
  (if (== k 0)
    acc
    (let ((s1 (next seed)))
      (let ((s2 (next s1)))
        (let ((slot (% (/ s1 16) live)) (len (+ 1 (% (/ s2 16) maxLen))))
          {
            (vecSet v slot (strAlloc len))
            (churn v (- k 1) live maxLen s2 (+ acc len))
          })))))

(:: liveBytes (-> (Vec String) Int Int Int))
(fn (liveBytes v i acc)
  (if (>= i (vecLen v))
    acc
    (liveBytes v (+ i 1) (+ acc (strLen (vecGet v i))))))

(:: atoiFrom (-> String Int Int Int))
(fn (atoiFrom s i acc)
  (if (>= i (strLen s))
    acc
    (atoiFrom s (+ i 1) (+ (* acc 10) (- (strByte s i) 48)))))

(:: argInt (-> Int Int))
;@axiom:effect(io)
(fn (argInt i)
  (atoiFrom (sysArg i) 0 0))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((n (argInt 1)) (live (argInt 2)) (maxLen (argInt 3)))
    (let ((v (vecNewRef)))
      {
        (fill v 0 live)
        (let ((total (churn v n live maxLen 42 0)))
          (let ((lb (liveBytes v 0 0)) (held (__axiom_mem_stat 0)) (filed (__axiom_mem_stat 1)))
            (println "{total} {lb} {held} {filed}")))
        0
      })))
AX
soak() {  # <binary> <n> <live> <maxLen> <key>
  local o r
  o="$("$1" "$2" "$3" "$4")" || { bad "soak $5 exited nonzero"; return 1; }
  r="$(max_rss_kb "$1" "$2" "$3" "$4")" || { bad "soak $5: no RSS measurement"; return 1; }
  if [[ -z "$r" || "$r" -le 0 ]]; then bad "soak $5 measured no RSS ('$r')"; return 1; fi
  setv "rss_$5" "$r"; setv "out_$5" "$o"
  echo "     $5: n=$2 peak ${r} KiB (checksum, live, held, filed: $o)"
}
if build "$work/soak.ax" "$work/soak" 1; then
  mags=(10000 100000 1000000)
  (( long )) && mags+=(10000000)
  for n in "${mags[@]}"; do soak "$work/soak" "$n" 1000 60000 "n$n"; done
  for pair in "100000 1000000" "1000000 10000000"; do
    read -r a b <<< "$pair"
    ra="$(getv "rss_n$a")"; rb="$(getv "rss_n$b")"
    [[ -n "$ra" && -n "$rb" ]] || continue
    if ratio_ge "$ra * 1.2" "$rb" 1; then
      ok "plateau: peak RSS $ra KiB at $a iterations, $rb KiB at $b (within 1.2x)"
    else
      bad "no plateau: $ra KiB at $a iterations, $rb KiB at $b"
    fi
  done
  read -r _ lb held filed <<< "$(getv out_n1000000)"
  lb="${lb:-0}"; held="${held:-0}"
  if (( lb > 0 )) && ratio_ge "$lb * 2.5" "$held" 1; then
    ok "bound: the arena holds $held bytes for $lb live bytes after 10^6 replacements (under 2.5x)"
  else
    bad "bound: the arena holds $held bytes for $lb live bytes (2.5x allowed)"
  fi
  rss_b=$(( $(getv rss_n1000000) * 1024 ))
  if ratio_ge "$rss_b * 1.1" "$held" 1 && ratio_ge "$held" "$rss_b" 0.75; then
    ok "instrument: __axiom_mem_stat 0 reads $held bytes where peak RSS is $rss_b"
  else
    bad "instrument: __axiom_mem_stat 0 reads $held bytes but peak RSS is $rss_b"
  fi
fi
if build_mutated "$work/soak.ax" "$work/soak-nr" no-rounding && build "$work/soak.ax" "$work/soak-small" 1; then
  soak "$work/soak-nr" 2000 100 8000 nr2k && soak "$work/soak-nr" 20000 100 8000 nr20k
  soak "$work/soak-small" 2000 100 8000 in2k && soak "$work/soak-small" 20000 100 8000 in20k
  n2="$(getv rss_nr2k)"; n20="$(getv rss_nr20k)"; i2="$(getv rss_in2k)"; i20="$(getv rss_in20k)"
  if ratio_ge "${n20:-0}" "${n2:-1}" 4 && ratio_ge "${i2:-0} * 1.5" "${i20:-1}" 1; then
    ok "ablation: without request rounding the small soak grows $n2 -> $n20 KiB; intact $i2 -> $i20 KiB"
  else
    bad "ablation: no-rounding ${n2:-?} -> ${n20:-?} KiB, intact ${i2:-?} -> ${i20:-?} KiB - section 2 cannot see the classes"
  fi
fi

# ---------------------------------------------------------------------
echo "== 3. cycles: counting leaves them, an arena scope reclaims them =="
# ---------------------------------------------------------------------
cat > "$work/cycles.ax" <<'AX'
; args: shape n. 0 knots, 1 knots inside a scope reset per iteration,
; 2 the acyclic chain. Prints the backlog (held less filed) per knot.
(import IO)
(import Sys)
(import Str)

(struct Node
  (v : Int)
  (mut next : Node))

(:: knot (-> Int Int))
(fn (knot i)
  (let ((a (Node i (cast Node 0))) (b (Node (+ i 1) (cast Node 0))))
    {
      (set a.next b)
      (set b.next a)
      (+ a.v b.v)
    }))

(:: chain (-> Int Int))
(fn (chain i)
  (let ((b (Node (+ i 1) (cast Node 0))))
    (let ((a (Node i b)))
      (+ a.v b.v))))

(:: loop (-> Int Int Int Int))
(fn (loop shape k acc)
  (if (== k 0)
    acc
    (loop shape (- k 1) (+ acc (if (== shape 0) (knot k) (chain k))))))

(:: scoped (-> Int Int Int Int))
;@axiom:effect(unsafe)
(fn (scoped m k acc)
  (if (== k 0)
    acc
    (let ((r (knot k)))
      {
        (__axiom_arena_reset m)
        (scoped m (- k 1) (+ acc r))
      })))

(:: atoiFrom (-> String Int Int Int))
(fn (atoiFrom s i acc)
  (if (>= i (strLen s))
    acc
    (atoiFrom s (+ i 1) (+ (* acc 10) (- (strByte s i) 48)))))

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (main)
  (let ((shape (atoiFrom (sysArg 1) 0 0)) (n (atoiFrom (sysArg 2) 0 0)))
    (let ((b0 (- (__axiom_mem_stat 0) (__axiom_mem_stat 1))))
      (let ((r (if (== shape 1) (scoped __axiom_arena_mark n 0) (loop shape n 0))))
        (let ((per (/ (- (- (__axiom_mem_stat 0) (__axiom_mem_stat 1)) b0) n)))
          {
            (println "{per}")
            0
          })))))
AX
if build "$work/cycles.ax" "$work/cycles" 1; then
  for shape in 0 1 2; do
    for n in 100000 1000000; do
      setv "per_${shape}_$n" "$("$work/cycles" "$shape" "$n")"
      setv "rss_${shape}_$n" "$(max_rss_kb "$work/cycles" "$shape" "$n")"
      echo "     shape $shape n=$n: $(getv "per_${shape}_$n") bytes a knot, peak $(getv "rss_${shape}_$n") KiB"
    done
  done
  p1="$(getv per_0_100000)"; p2="$(getv per_0_1000000)"; r1="$(getv rss_0_100000)"; r2="$(getv rss_0_1000000)"
  if [[ "$p1" == 64 && "$p2" == 64 ]] && ratio_ge "${r2:-0}" "${r1:-1}" 5; then
    ok "unscoped knots: the backlog grows 64 bytes a knot at both magnitudes, and RSS $r1 -> $r2 KiB"
  else
    bad "unscoped knots: $p1 and $p2 bytes a knot, RSS $r1 -> $r2 KiB"
  fi
  for shape in 1 2; do
    name=scoped; (( shape == 2 )) && name=acyclic
    p2="$(getv "per_${shape}_1000000")"; r1="$(getv "rss_${shape}_100000")"; r2="$(getv "rss_${shape}_1000000")"
    if [[ "$p2" == 0 ]] && ratio_ge "${r1:-0} * 1.1" "${r2:-1}" 1; then
      ok "$name: no backlog, RSS $r1 -> $r2 KiB"
    else
      bad "$name: $p2 bytes a knot, RSS $r1 -> $r2 KiB"
    fi
  done
fi

# ---------------------------------------------------------------------
echo "== 4. resets leave no stale allocator metadata =="
# ---------------------------------------------------------------------
meta=tests/stdlib/559-reset-metadata
for lvl in 0 2; do
  if build "$meta.ax" "$work/meta$lvl" "$lvl"; then
    if [[ "$("$work/meta$lvl" 2>/dev/null)" == "$(cat "$meta.out")" ]]; then
      ok "559 at --opt $lvl: every block zeroed and disjoint after four kinds of reset"
    else
      bad "559 at --opt $lvl printed something else"
    fi
  fi
done
if build_mutated "$meta.ax" "$work/meta-noscrub" no-scrub; then
  got="$("$work/meta-noscrub" 2>/dev/null)"; rc=$?
  if (( rc != 0 )) || [[ "$got" != "$(cat "$meta.out")" ]]; then
    ok "ablation: with the reset's list scrub deleted, 559 fails (exit $rc)"
  else
    bad "ablation: 559 still passes with no list scrub - section 4 is blind to stale heads"
  fi
fi
if [[ "$(uname -s)" == FreeBSD ]]; then
  echo "skip threads: --threads is refused for freebsd (AX4006)"
else
  cat > "$work/threads.ax" <<'AX'
; four threads, each with its own arena: every class filed and reset,
; twenty times, then blocks allocated and verified. The main thread
; files one block of its own first, and must get that same block back
; after the joins: no other thread's reset reached its lists
(import IO)
(import Mem)
(import Vec)

(:: pat (-> Int Int Int Int))
(fn (pat p words tag)
  {
    (for i 0 words
      (memSetWord p i (+ (* tag 1000003) i)))
    p
  })

(:: bad (-> Int Int Int Int))
(fn (bad p words tag)
  (let ((mut k 0))
    {
      (for i 0 words
        (if (== (memGetWord p i) (+ (* tag 1000003) i)) 0 (set k (+ k 1))))
      k
    }))

(:: churnOnce (-> Int Int))
;@axiom:effect(unsafe)
(fn (churnOnce salt)
  (let ((m __axiom_arena_mark) (mut k 0))
    {
      (let ((mut sz 16))
        (while (<= sz 65536)
          (let ((p (memAlloc sz)))
            {
              (__retain p)
              (pat p (/ sz 8) 5)
              (__release p)
              (set sz (+ sz 48))
            })))
      (__axiom_arena_reset m)
      (if (== (__axiom_mem_stat 1) 0) 0 (set k (+ k 1)))
      (let ((v (vecNew)))
        {
          (for i 0 64
            (let ((p (memAlloc 1100)))
              {
                (if (== (memGetWord p 3) 0) 0 (set k (+ k 1)))
                (vecPush v (pat p 137 (+ salt i)))
              }))
          (for i 0 64
            (set k (+ k (bad (vecGet v i) 137 (+ salt i)))))
        })
      (__axiom_arena_reset m)
      k
    }))

(:: worker (-> Int Int))
(fn (worker salt)
  (let ((mut k 0))
    {
      (for r 0 20
        (set k (+ k (churnOnce (+ salt (* r 100))))))
      k
    }))

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (main)
  (let ((p (memAlloc 4000)))
    {
      (__retain p)
      (__release p)
      (let ((h1 (__thread_spawn (lambda (x) (worker x)) 1000))
            (h2 (__thread_spawn (lambda (x) (worker x)) 2000))
            (h3 (__thread_spawn (lambda (x) (worker x)) 3000))
            (h4 (__thread_spawn (lambda (x) (worker x)) 4000)))
        (let ((b (+ (+ (__thread_join h1) (__thread_join h2)) (+ (__thread_join h3) (__thread_join h4)))))
          (let ((same (== p (memAlloc 4000))))
            {
              (println "bad {b} main-block-back {same}")
              0
            })))
    }))
AX
  if build "$work/threads.ax" "$work/threads" 1; then
    got="$("$work/threads" 2>&1)"
    if [[ "$got" == "bad 0 main-block-back true" ]]; then
      ok "threads: four per-thread arenas file every band and reset twenty times, verified, and the main thread's filed block survives them"
    else
      bad "threads: '$got'"
    fi
  fi
  if build_mutated "$work/threads.ax" "$work/threads-shared" shared-slabs; then
    got="$("$work/threads-shared" 2>/dev/null)"; rc=$?
    if (( rc != 0 )) || [[ "$got" != "bad 0 main-block-back true" ]]; then
      ok "ablation: with one set of size-class lists for every thread, the probe fails (exit $rc)"
    else
      bad "ablation: shared size-class lists still passed - the thread check cannot see them"
    fi
  fi
fi

# ---------------------------------------------------------------------
echo "== 5. resources beyond memory across trap-and-recover =="
# ---------------------------------------------------------------------
cat > "$work/res.ax" <<'AX'
; args: mode n. 1 opens /dev/null inside a recovery point and traps
; before the close; 2 closes first. Prints the next descriptor before
; and after. 3 spawns a forked child inside the extent and traps.
(import IO)
(import Sys)
(import Str)
(import Mem)

(:: openFd Int)
;@axiom:effect(io)
(fn (openFd)
  (match (sysOpenPath (strCStr "/dev/null") 0)
    ((Ok fd) fd)
    ((Err e) -1)))

(:: closeFd (-> Int Int))
;@axiom:effect(io)
(fn (closeFd fd)
  (match (sysCloseFd fd)
    ((Ok r) r)
    ((Err e) -1)))

(:: boom (-> Int Int))
(fn (boom d)
  (/ 7 d))

(:: cycles (-> Int Int Int Int))
;@axiom:effect(io)
(fn (cycles mode m k)
  (if (== k 0)
    0
    {
      (__axiom_recover m
        (lambda (x)
          (let ((fd (openFd)))
            {
              (if (== mode 2) (closeFd fd) 0)
              (boom 0)
            })))
      (cycles mode m (- k 1))
    }))

(:: child Int)
;@axiom:effect(io)
(fn (child)
  (let ((w (memAlloc 16)))
    {
      (memSetWord w 0 7)
      (let ((st (__axiom_recover __axiom_arena_mark
        (lambda (x)
          (let ((h (__proc_spawn (lambda (y) { (sysWaitWordTimeout w 7 5000000000) y }) 1)))
            (boom 0))))))
        {
          (let ((pid sysGetPid))
            (println "pid {pid} status {st}"))
          (sysWaitWordTimeout w 7 1500000000)
          0
        })
    }))

(:: atoiFrom (-> String Int Int Int))
(fn (atoiFrom s i acc)
  (if (>= i (strLen s))
    acc
    (atoiFrom s (+ i 1) (+ (* acc 10) (- (strByte s i) 48)))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((mode (atoiFrom (sysArg 1) 0 0)) (n (atoiFrom (sysArg 2) 0 0)))
    (if (== mode 3)
      child
      (let ((before (openFd)))
        {
          (closeFd before)
          (cycles mode __axiom_arena_mark n)
          (let ((after (openFd)))
            {
              (println "{before} {after}")
              0
            })
        }))))
AX
if build "$work/res.ax" "$work/res" 1; then
  nfd=10000
  cap="$(ulimit -n)"
  if [[ "$cap" != unlimited ]] && (( cap < nfd + 64 )); then
    ( ulimit -n $((nfd + 64)) ) 2>/dev/null || nfd=$(( cap - 64 ))
  fi
  # The next fd is the lowest free number, so a descriptor the caller
  # left open above stderr is a number no leaked one can take, and the
  # count comes out high by one for each. CI's runners hand a child two
  # to four of them. Each probe closes them first, so the numbers the
  # program opens are contiguous wherever it runs.
  close_inherited() {
    local fd
    for fd in $(ls /dev/fd 2>/dev/null); do
      [[ "$fd" =~ ^[0-9]+$ ]] && (( fd > 2 && fd != 255 )) && eval "exec $fd>&-" 2>/dev/null
    done
    return 0
  }
  read -r b1 a1 <<< "$( ( ulimit -n $((nfd + 64)) 2>/dev/null; close_inherited; "$work/res" 1 "$nfd" ) )"
  read -r b2 a2 <<< "$( ( ulimit -n $((nfd + 64)) 2>/dev/null; close_inherited; "$work/res" 2 "$nfd" ) )"
  if [[ -n "${a1:-}" && -n "${a2:-}" ]] && (( a1 - b1 == nfd && a2 == b2 )); then
    ok "descriptors: $nfd trapped cycles leave $((a1 - b1)) open, one each (the program's to close); the control that closes first leaves $((a2 - b2))"
  else
    bad "descriptors: trapped cycles moved the next fd ${b1:-?} -> ${a1:-?}, the control ${b2:-?} -> ${a2:-?} (n=$nfd)"
  fi
  "$work/res" 3 0 > "$work/child.out" 2>&1 &
  bg=$!
  kids=-1
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.1
    grep -q '^pid ' "$work/child.out" && { kids="$(pgrep -P "$bg" | wc -l | tr -d ' ')"; break; }
  done
  wait "$bg"; rc=$?
  if [[ "$kids" == 0 && "$rc" == 0 ]] && grep -q 'status 72' "$work/child.out"; then
    ok "children: a forked child spawned inside the extent is gone once the abort answers 72"
  else
    bad "children: $kids child(ren) left after the abort (exit $rc: $(cat "$work/child.out"))"
  fi
fi

# ---------------------------------------------------------------------
echo "== 6. a recovery point allocates nothing =="
# ---------------------------------------------------------------------
rec=tests/stdlib/560-recover-record
for lvl in 0 1 2 3; do
  if build "$rec.ax" "$work/rec$lvl" "$lvl"; then
    if [[ "$("$work/rec$lvl")" == "$(cat "$rec.out")" ]]; then
      ok "560 at --opt $lvl: answered, trapped and nested arms grow nothing; a fresh mark costs 48 bytes"
    else
      bad "560 at --opt $lvl printed something else"
    fi
  fi
done
if build_mutated "$rec.ax" "$work/rec-arena" arena-record; then
  first="$("$work/rec-arena" | head -1)"
  if [[ "$first" != "$(head -1 "$rec.out")" ]]; then
    ok "ablation: with the record back in the arena, 560's first line reads '$first'"
  else
    bad "ablation: an arena record left 560's first line unchanged - section 6 is blind"
  fi
fi

echo
echo "check-reclaim-soak: $checks passed, $failed failed"
(( failed == 0 ))
