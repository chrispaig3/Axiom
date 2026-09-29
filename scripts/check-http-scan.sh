#!/usr/bin/env bash
# The HTTP request reader examines each byte of a request head a bounded
# number of times, however the head is fragmented - counted, not timed.
#
# WHY THIS EXISTS. `httpRead` refills its buffer until `\r\n\r\n` has
# arrived and looks for the terminator after every `read`. Until
# 2026-09-26 each look started at offset 0, so a peer sending its head a
# byte at a time made every look rescan every byte already seen:
# (N-3)(N-2)/2 candidate positions for an N-byte head with no terminator,
# about 134 million at the 16 KiB ceiling. An audit measured it through
# an adapter over the private scanner - 1.6, 6.8, 27.8 and 107.8 ms for
# 2, 4, 8 and 16 KiB, four times the cost for twice the bytes - and no
# gate could see it: every parser fixture was correct, and a correct
# answer arrived at quadratically is still correct. The scan resumes
# where the last one stopped now (`httpHeadEndFrom`, stdlib/Http.ax).
#
# WHY A COUNT AND NOT A CLOCK. A wall-clock bound on a shared runner is
# the flaky test `check-name-scale.sh`'s header spends a page on; that
# gate's bounds moved twice for the machine rather than the tree. The
# property is algorithmic, so the measurement is the algorithm's own
# unit: a copy of `Http.ax` has one line added inside the scan loop that
# writes one byte to fd 2 per candidate position examined, and the gate
# counts the bytes. Same input, same count, on every machine.
#
# THE INPUT is the worst case the audit named: a head with no terminator
# from a peer that delivers ONE BYTE PER `read`. That peer cannot be
# built deterministically out of a socket - how many bytes a read
# answers is the kernel's and the sender's timing - and a one-byte
# READER is not it either: measured on the first draft of this gate,
# `httpReaderWith fd 1` doubles its buffer as it fills and each read
# then takes the whole free tail, so a 1,024-byte head arrived in about
# ten reads and even the pre-fix rescan examined only 2,017 positions.
# So the copy's `httpFill` asks `read` for at most one byte - the peer
# modelled at the one line where the peer is met, as the audit's adapter
# modelled it by advancing `filled` one byte per call - and the head is
# read from a FILE, which needs no second process and no port. The scan,
# the cursor and the buffer growth are the tree's own, unmodified.
#
# THE ASSERTIONS, each with the reason it cannot pass vacuously:
#
#   1. The count is at most 2N at two sizes. Linear work is about N;
#      quadratic is N^2/2, which passes 2N from N = 5 on.
#   2. The count is at least N - 8. An instrumentation line that never
#      ran - a seam that matched the wrong line, a loop that was never
#      entered - would satisfy (1) with a count of zero.
#   3. THE ABLATION: the same copy with the resume taken out - the scan
#      restarted at 0 on every fill, which is the code before the fix -
#      must be refused by the same bound. A bound nothing quadratic has
#      been seen to fail is a bound that proves nothing.
#
# Every seam is an exact line whose match count is asserted to be one
# before the copy is used: an edit that matches nothing produces a copy
# identical to the original, and then (3) would be measuring the fix.
#
# Requires: a compiler that builds the standard library. The subject is
# library code, not the compiler, so this uses `gate_init`'s compiler
# and builds none of its own.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

http="$repo_root/stdlib/Http.ax"

# `seam <file> <exact line>` - fails the gate unless the line occurs once.
seam() {
  local n
  n="$(grep -cxF -- "$2" "$1" || true)"
  if [[ "$n" != 1 ]]; then
    bad "the seam \`$2\` matches $n lines of $(basename "$1"), not 1 - the copy would not be instrumented"
    return 1
  fi
}

# `instrument <stdlib dir> [ablate]`: a copy of the tree's stdlib whose
# `Http.ax` writes one byte to fd 2 per scan candidate; with `ablate`,
# the scan also restarts at 0 on every fill.
count_line='          (set cand (+ cand 1))'
tag_line='(fn (httpHeadEndFrom r from)'
resume_line='          (set hdr (httpHeadEndFrom r scanned))'
read_line='        (match (sysReadFd r.fd (+ (strData r.buf) r.filled) (- (strLen r.buf) r.filled))'
instrument() {
  local dir="$1" mode="${2:-}"
  rm -rf "$dir"; cp -R "$repo_root/stdlib" "$dir"
  seam "$http" "$count_line" || return 1
  seam "$http" "$tag_line" || return 1
  seam "$http" "$read_line" || return 1
  [[ "$mode" == ablate ]] && { seam "$http" "$resume_line" || return 1; }
  COUNT="$count_line" TAG="$tag_line" RESUME="$resume_line" READ="$read_line" MODE="$mode" awk '
    $0 == ENVIRON["TAG"] { print ";@axiom:effect(io)"; print ";@axiom:effect(unsafe)"; print; next }
    $0 == ENVIRON["COUNT"] {
      print "          (let ((_ (sysWriteFd 2 (__addr \"+\") 1))) 0)"; print; next }
    $0 == ENVIRON["READ"] {
      print "        (match (sysReadFd r.fd (+ (strData r.buf) r.filled) 1)"; next }
    ENVIRON["MODE"] == "ablate" && $0 == ENVIRON["RESUME"] {
      print "          (set hdr (httpHeadEndFrom r 0))"; next }
    { print }' "$http" > "$dir/Http.ax"
}

cat > "$work/drive.ax" <<'AX'
(import Sys)
(import Err)
(import Http)

; Read the head in `head.bin`, one byte per `read` in the instrumented
; copy. It has no terminator, so the reader looks once per byte until
; end of input and answers the 400 for a head that never ended.
(:: main Int)
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (main)
  (match (sysOpenPath (__addr "head.bin") oRdonly)
    ((Err _) 2)
    ((Ok fd)
      (match (httpRead (httpReaderNew fd))
        ((Ok _) 3)
        ((Err e)
          (if (== (errCode e) 400)
            0
            4))
      ))))
AX

# `candidates <stdlib dir> <N>`: the count, or empty on failure.
candidates() {
  local dir="$1" n="$2" rc
  python3 -c 'import sys
n = int(sys.argv[1])
head = b"GET / HTTP/1.1\r\nX-Pad: "
sys.stdout.buffer.write(head + b"x" * (n - len(head)))' "$n" > "$work/head.bin"
  rm -f "$work/drive"
  if ! AXIOM_STDLIB="$dir" "$axiom" build --input "$work/drive.ax" --output "$work/drive" \
       >"$work/build.log" 2>&1; then
    echo "     could not build the driver against $(basename "$dir"):" >&2
    sed 's/^/       /' "$work/build.log" | head -5 >&2
    return 1
  fi
  ( cd "$work" && ./drive ) 2>"$work/count.bin" >/dev/null
  rc=$?
  if (( rc != 0 )); then
    echo "     the driver exited $rc, not 0 (a 400 for a head that never ended)" >&2
    return 1
  fi
  wc -c < "$work/count.bin" | tr -d ' '
}

echo "== the scan over a head read a byte at a time is linear =="
if instrument "$work/std"; then
  for n in 4096 16000; do
    if c="$(candidates "$work/std" "$n")"; then
      if (( c > 2 * n )); then
        bad "N=$n: $c candidate positions examined, above 2N = $((2 * n))"
      elif (( c < n - 8 )); then
        bad "N=$n: only $c candidate positions examined - the counting line did not run on every look"
      else
        ok "N=$n: $c candidate positions examined (bound 2N = $((2 * n)), floor N-8)"
      fi
    else
      bad "N=$n: the instrumented reader did not run"
    fi
  done
fi

echo "== the ablation: the scan restarted at 0 on every fill must be refused =="
# N is smaller here only because the ablated count is quadratic and is
# written a byte at a time: 1,024 bytes of head is ~520,000 writes.
if instrument "$work/std-abl" ablate; then
  n=1024
  if c="$(candidates "$work/std-abl" "$n")"; then
    if (( c > 2 * n )); then
      ok "with the resume removed, N=$n examines $c positions - over 2N, as the pre-fix scan did"
    else
      bad "with the resume removed, N=$n examined only $c positions - the bound cannot see a rescan"
    fi
  else
    bad "the ablated reader did not run"
  fi
fi

echo
if (( failed > 0 )); then
  echo "check-http-scan: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-http-scan: $checks checks - the HTTP head scan is linear in the"
echo "                 bytes of a head fed one byte per read, counted rather"
echo "                 than timed, and the pre-fix rescan is seen to fail it"
