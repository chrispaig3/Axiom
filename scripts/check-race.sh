#!/usr/bin/env bash
# A race detector over thread-lowered programs: ThreadSanitizer (R-E1;
# docs/memory-model.md MM-PAR-9 says what a data race is here).
#
# THE PIPELINE. Each program is emitted with `axc emit-llvm --threads`,
# which lowers `parallel` to `pthread_create`/`pthread_join` with the
# runtime's globals thread-local (MM-PAR-3, MM-PAR-6, MM-PAR-6a). Then:
#
#   - every attribute group of the module gains `sanitize_thread`, so
#     every function, the runtime's included, is instrumented;
#   - every raw system call goes through one added function that sends
#     `mmap` and `munmap` to the C library and makes every other call
#     exactly as the program did. TSan learns about memory from its
#     `mmap`/`munmap` interceptors, and the runtime maps its arenas
#     with raw system calls it never sees: a thread's arena unmapped
#     when the thread ends (MM-PAR-6a) and mapped again at the same
#     address by a sibling read as a race between `axiom_alloc` and
#     `__axiom_arena_unmap_thread` in the locked program before this
#     routing. The numbers come from the tree's own
#     `stdlib/Sys/Platform.*.ax`;
#   - `Sys$sysWaitWordTimeout` is kept out of line (`noinline`), the one
#     function the suppression list names (below);
#   - `opt -O<n>` when n > 0, LLVM's `tsan-module,function(tsan)` passes,
#     `llc -O<n> -relocation-model=pic`, and a `clang -fsanitize=thread`
#     link. The runtime is LLVM's (`libclang_rt.tsan*`).
#
# WHY TSAN SEES THE LANGUAGE'S EDGES. MM-PAR-9 has exactly four
# happens-before edges: program order; spawn (`pthread_create`); join
# (`pthread_join`); and the seq_cst atomics. TSan intercepts both
# pthread calls and models every instrumented atomic as acquire-release.
# The mutex (MM-PAR-11) and the channel (MM-PAR-10) add no edge of
# their own: their acquire is a compare-and-swap and their release a
# compare-and-swap, store or add, all atomics TSan sees. Their waits
# are raw `futex`/`__ulock_wait` calls TSan cannot see, and MM-PAR-9
# says a wait orders nothing, so nothing is lost: a woken waiter takes
# the lock by the compare-and-swap, which TSan does see. So a clean run
# here means no two accesses in it were unordered by the edges the
# language promises, and section 5's ablated lock shows the converse.
#
# SIX SECTIONS.
#
#   1. The toolchain. `opt`, `llc` and a clang whose TSan runtime links
#      and starts. On Linux a runtime that does not start is retried
#      under `setarch -R` (randomisation off), which is what the runtime
#      tries itself when its shadow does not fit the kernel's layout.
#      Under qemu's user-mode emulation that fails too (measured on a
#      linux-x86_64 container on an arm64 Mac: the runtime's own
#      `personality` call CHECK-fails), and the gate skips.
#   2. The CONTROL. tests/litmus/sync-load.ax `excl 0 N`: four bindings
#      add to one plain shared word with no lock. TSan must REPORT a
#      data race in `bump`, at --opt 0 and 2, with the suppression list
#      loaded. A detector that cannot see this race makes every clean
#      run below meaningless, so a silent control is a failure.
#   3. The clean runs, each answering what the program says it must and
#      each with no report: the same program under the mutex (`excl 1
#      N`), a stale guard presented under contention (`stale N`), the
#      channel under load (tests/litmus/chan-load.ax at capacities 1
#      and 64), examples/concurrency/pipeline.ax, and the seq_cst rows
#      of tests/litmus/atomics.ax (`sb sc`, `add sc`, `add cas`), all at
#      --opt 0 and 2. And `add split`, whose atomic load and atomic
#      store lose updates with no data race: TSan must say nothing,
#      because an atomicity violation made of atomics is not a race.
#   4. The suppression list, tests/litmus/tsan-suppressions.txt. Every
#      rule needs its reason in the comment above it, every rule must
#      have matched in sections 2 and 3 (a rule that matches nothing is
#      stale), and the locked and pipeline programs are run again
#      WITHOUT the list: TSan must report the race the rule names, and
#      nothing else. That race is MM-PAR-12's stated reliance: a plain
#      64-bit read in `sysWaitWordTimeout` of a word other bindings
#      write with atomics. TSan finds it unprompted.
#   5. Ablations, each on a copy, each required to turn a clean run into
#      a reported race with the list loaded: the mutex's compare-and-
#      swap (stdlib/Sync.ax, as scripts/check-task.sh cuts it), the
#      channel's lock (stdlib/Chan.ax, as scripts/check-chan.sh cuts
#      it), and `add sc`'s `atomicrmw` made a plain load and store in
#      the emitted IR.
#   6. AddressSanitizer, briefly. Axiom's heap is its own arena, carved
#      from pages the runtime maps itself, so ASan cannot see a heap
#      block's bounds or a freed block's reuse; it sees globals, and
#      the unsafe layer can read past one. A probe reads words past a
#      string literal's header: the reads inside must run clean and the
#      first read past the end must be reported as a
#      global-buffer-overflow. A read past a 16-byte heap block into
#      its arena neighbour is printed as the limit it is, not counted.
#
# WHAT A GREEN RUN SAYS, AND WHAT IT DOES NOT.
#   - TSan is dynamic. It saw the interleavings these runs made, on this
#     host, at these levels; a race on a path not taken is not seen.
#   - Threads only. The default lowering forks processes that share
#     only MAP_SHARED pages, and TSan's model is one process: races
#     between forked bindings, and the task pool (stdlib/Task.ax, which
#     forks), are outside it. The same mutex and channel code runs in
#     both lowerings.
#   - The instrumented build is not the shipped build: `mmap` and
#     `munmap` go through the C library, one function is not inlined,
#     and every access calls into the TSan runtime.
#   - TSan checks data races, not the atomics' ordering: a seq_cst
#     outcome the memory model forbids is scripts/check-atomics.sh's
#     subject, and `add split` above shows a lost update TSan passes.
#   - A suppression hides every report with that function in either
#     access's stack; section 4's unsuppressed runs are the check that
#     it hid nothing else on these runs, not a proof.
#
# FINDINGS. The one race in the runtime and standard library these
# programs reach is the suppressed reliance. tests/litmus/atomics.ax's
# `mp sc` row is not run: its reader loads the data word before it
# tests the flag, so in a round where the flag is not yet set that
# plain load races the writer's plain store, and TSan reports it
# (measured; 128 s under TSan at the program's fixed 500,000 rounds).
#
# SKIPS. With no TSan runtime for this clang, or one that cannot start,
# every section prints SKIP with the reason, counted apart and never as
# a pass. `AXIOM_TSAN_REQUIRED=1` makes that a failure instead; CI sets
# it, because CI provisions the runtime.
#
# Usage: check-race.sh
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH"; exit 1; }

failed=0
checks=0
skipped=0
ok()   { echo "ok   $*"; checks=$((checks + 1)); }
bad()  { echo "FAIL $*"; failed=$((failed + 1)); }
skip() { echo "SKIP $*"; skipped=$((skipped + 1)); }

supp="$repo_root/tests/litmus/tsan-suppressions.txt"
sync="$repo_root/tests/litmus/sync-load.ax"
chan="$repo_root/tests/litmus/chan-load.ax"
pipe="$repo_root/examples/concurrency/pipeline.ax"
atom="$repo_root/tests/litmus/atomics.ax"
reliance='Sys$sysWaitWordTimeout'
N=2000   # increments per binding in sync-load's modes
C=500    # words per producer in chan-load

# finish: the verdict. A SKIP is its own count, never a pass.
finish() {
  echo
  if (( failed > 0 )); then
    echo "check-race: $failed failed, $checks passed, $skipped skipped"
    exit 1
  fi
  if (( skipped > 0 )); then
    echo "check-race: $checks checks passed; $skipped SKIPPED - nothing was run under a"
    echo "            sanitizer for them, and they are not counted above"
    exit 0
  fi
  echo "check-race: $checks checks - TSan reports the unlocked control and the three"
  echo "            ablations, and nothing else but the one documented reliance, whose"
  echo "            suppression hides no other report; ASan sees a global overread"
  exit 0
}

# skip_all <reason>: no sanitizer can run here.
skip_all() {
  if [[ "${AXIOM_TSAN_REQUIRED:-}" == 1 ]]; then
    bad "AXIOM_TSAN_REQUIRED=1 and ThreadSanitizer cannot run here: $1"
  else
    skip "every section: $1"
  fi
  finish
}

# ---------------------------------------------------------------------
echo "== 1. the toolchain =="
cc="${AXIOM_TSAN_CC:-clang}"
for tool in opt llc "$cc"; do
  command -v "$tool" >/dev/null || skip_all "\`$tool\` is not on PATH"
done
case "$(uname -s)-$(uname -m)" in
  Darwin-*)        plat=darwin;        errfn=__error ;;
  Linux-aarch64)   plat=linux-aarch64; errfn=__errno_location ;;
  Linux-x86_64)    plat=linux-x86_64;  errfn=__errno_location ;;
  *) skip_all "no thread lowering to check on $(uname -s)-$(uname -m)" ;;
esac
# platnum <name>: the number `stdlib/Sys/Platform.<plat>.ax` answers.
platnum() {
  awk -v f="(pub fn ($1)" 'index($0, f) == 1 { getline; gsub(/[ )]/, ""); print; exit }' \
    "$repo_root/stdlib/Sys/Platform.$plat.ax"
}
nmmap="$(platnum sysMmapNum)"
nmunmap="$(platnum sysMunmapNum)"
if [[ ! "$nmmap" =~ ^[0-9]+$ || ! "$nmunmap" =~ ^[0-9]+$ ]]; then
  bad "no mmap/munmap numbers in stdlib/Sys/Platform.$plat.ax ('$nmmap', '$nmunmap')"; finish
fi
echo "   $plat: mmap $nmmap, munmap $nmunmap; $("$cc" --version | head -1)"

printf 'int main(void) { return 0; }\n' > "$work/probe.c"
if ! "$cc" -fsanitize=thread "$work/probe.c" -o "$work/probe" > "$work/probe.log" 2>&1; then
  skip_all "$cc -fsanitize=thread cannot link: $(grep -m1 -iE 'tsan|not found|cannot find|error' "$work/probe.log")"
fi
runner=()
if ! "$work/probe" > "$work/probe.run" 2>&1; then
  if [[ "$plat" == linux-* ]] && command -v setarch >/dev/null \
       && setarch "$(uname -m)" -R "$work/probe" >/dev/null 2>&1; then
    runner=(setarch "$(uname -m)" -R)
    echo "   a TSan program starts only with address-space randomisation off here: runs use setarch -R"
  else
    skip_all "a TSan-linked program does not start: $(head -1 "$work/probe.run")"
  fi
fi
ok "a TSan program links and starts ($cc)"

# The IR step, once, as a file every build runs.
cat > "$work/prep.py" <<'PY'
# prep.py <in.ll> <out.ll> <mmap> <munmap> <errno fn> <noinline fn>
import re, sys
src, dst, nmmap, nmunmap, errfn, keep = sys.argv[1:7]
s = open(src, encoding="utf-8").read()
s, groups = re.subn(r"^(attributes #\d+ = \{ )", r"\1sanitize_thread ", s, flags=re.M)
bare = [d for d in re.findall(r"^define [^\n]*", s, flags=re.M) if not re.search(r"#\d+", d)]
if groups == 0 or bare:
    sys.exit("attribute groups %d, definitions outside one %d" % (groups, len(bare)))
s, kept = re.subn(r"^(define [^\n]*@%s\([^\n]*\)) (#\d+)" % re.escape(keep), r"\1 noinline \2", s, flags=re.M)
call = re.compile(r'call i64 asm sideeffect "((?:[^"\\]|\\.)*)", "((?:[^"\\]|\\.)*)"\('
                  r'(i64 [^,()]+), (i64 [^,()]+), (i64 [^,()]+), (i64 [^,()]+), '
                  r'(i64 [^,()]+), (i64 [^,()]+), (i64 [^,()]+)\)')
shapes = set()
def route(m):
    if "svc" not in m.group(1) and "syscall" not in m.group(1):
        return m.group(0)
    shapes.add((m.group(1), m.group(2)))
    return "call i64 @__race_syscall(" + ", ".join(m.group(i) for i in range(3, 10)) + ")"
s, calls = call.subn(route, s)
if len(shapes) != 1:
    sys.exit("wanted one system-call shape, found %d" % len(shapes))
tmpl, cons = shapes.pop()
maps = len(re.findall(r"@__race_syscall\(i64 %s," % nmmap, s))
unmaps = len(re.findall(r"@__race_syscall\(i64 %s," % nmunmap, s))
if maps == 0 or unmaps == 0:
    sys.exit("no constant mmap (%d) or munmap (%d): the runtime's own calls moved" % (maps, unmaps))
s += f'''
declare ptr @mmap(ptr, i64, i32, i32, i32, i64)
declare i32 @munmap(ptr, i64)
declare ptr @{errfn}()

define internal i64 @__race_errno(i64 %r) {{
entry:
  %bad = icmp eq i64 %r, -1
  br i1 %bad, label %e, label %ok
e:
  %ep = call ptr @{errfn}()
  %ev = load i32, ptr %ep
  %ew = sext i32 %ev to i64
  %neg = sub i64 0, %ew
  ret i64 %neg
ok:
  ret i64 %r
}}

define internal i64 @__race_syscall(i64 %n, i64 %a, i64 %b, i64 %c, i64 %d, i64 %e, i64 %f) {{
entry:
  switch i64 %n, label %raw [ i64 {nmmap}, label %map
                              i64 {nmunmap}, label %unmap ]
map:
  %pa = inttoptr i64 %a to ptr
  %c32 = trunc i64 %c to i32
  %d32 = trunc i64 %d to i32
  %e32 = trunc i64 %e to i32
  %mp = call ptr @mmap(ptr %pa, i64 %b, i32 %c32, i32 %d32, i32 %e32, i64 %f)
  %mi = ptrtoint ptr %mp to i64
  %mr = call i64 @__race_errno(i64 %mi)
  ret i64 %mr
unmap:
  %pu = inttoptr i64 %a to ptr
  %u = call i32 @munmap(ptr %pu, i64 %b)
  %ui = sext i32 %u to i64
  %ur = call i64 @__race_errno(i64 %ui)
  ret i64 %ur
raw:
  %r = call i64 asm sideeffect "{tmpl}", "{cons}"(i64 %n, i64 %a, i64 %b, i64 %c, i64 %d, i64 %e, i64 %f)
  ret i64 %r
}}
'''
open(dst, "w", encoding="utf-8").write(s)
print("groups %d syscalls %d mmap %d munmap %d noinline %d" % (groups, calls, maps, unmaps, kept))
PY

# The reports, read by stack rather than by count alone.
cat > "$work/reports.py" <<'PY'
# reports.py <stderr> count | races <function> | reliance <function> | matched
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
acc = re.compile(r"^  (Previous )?(atomic )?(read|write) of size (\d+) at 0x[0-9a-f]+ by ", re.I)
reports = []
for chunk in text.split("==================\n"):
    m = re.search(r"WARNING: ThreadSanitizer: (.+?) \(pid=", chunk)
    if not m:
        continue
    accesses, cur = [], None
    for line in chunk.splitlines():
        a = acc.match(line)
        if a:
            cur = {"atomic": bool(a.group(2)), "op": a.group(3).lower(),
                   "size": int(a.group(4)), "frames": []}
            accesses.append(cur)
            continue
        f = re.match(r"^    #\d+ (\S+)", line) if cur is not None else None
        if f:
            cur["frames"].append(f.group(1))
        else:
            cur = None
    reports.append((m.group(1), accesses))
def reliance(kind, accs, fn):
    if kind != "data race" or len(accs) != 2:
        return False
    for mine, other in ((accs[0], accs[1]), (accs[1], accs[0])):
        if (not mine["atomic"] and mine["op"] == "read" and mine["size"] == 8
                and any(fr.startswith(fn) for fr in mine["frames"][:2])
                and other["atomic"] and other["op"] == "write"):
            return True
    return False
q = sys.argv[2]
if q == "count":
    print(len(reports))
elif q == "races":
    print(sum(1 for k, accs in reports if k == "data race"
              and any(fr == sys.argv[3] or fr.startswith(sys.argv[3] + ".")
                      for a in accs for fr in a["frames"])))
elif q == "reliance":
    hit = sum(1 for k, accs in reports if reliance(k, accs, sys.argv[3]))
    print(hit, len(reports) - hit)
elif q == "first":
    for k, accs in reports[:1]:
        print(k + ": " + " / ".join("%s%s %s" % ("atomic " if a["atomic"] else "", a["op"],
                                                 "<".join(a["frames"][:3]) or "?") for a in accs))
elif q == "matched":
    for m in re.finditer(r"^\s*(\d+) (race\S*:\S+)$", text, flags=re.M):
        print(m.group(1), m.group(2))
PY

# build <out> <source> <level> [stdlib]: the instrumented executable.
build() {
  local out="$1" src="$2" lvl="$3" lib="${4:-$repo_root/stdlib}"
  (cd "$repo_root" && AXIOM_STDLIB="$lib" "$axc" emit-llvm --threads "$src" -o "$out.ll") > "$out.log" 2>&1 || return 1
  from_ll "$out" "$out.ll" "$lvl"
}
# from_ll <out> <ll> <level>
from_ll() {
  local out="$1" ll="$2" lvl="$3" in
  python3 "$work/prep.py" "$ll" "$out.san.ll" "$nmmap" "$nmunmap" "$errfn" "$reliance" > "$out.prep" 2>> "$out.log" || return 1
  in="$out.san.ll"
  if (( lvl > 0 )); then
    opt "-O$lvl" "$in" -S -o "$out.opt.ll" 2>> "$out.log" || return 1
    in="$out.opt.ll"
  fi
  opt -passes='tsan-module,function(tsan)' "$in" -S -o "$out.tsan.ll" 2>> "$out.log" || return 1
  # Instrumented, or the run below would pass for want of looking.
  if (( $(grep -c 'call void @__tsan_func_entry' "$out.tsan.ll") == 0 \
        || $(grep -cE 'call void @__tsan_(unaligned_)?(read|write)8' "$out.tsan.ll") == 0 )); then
    echo "no TSan calls in the instrumented IR" >> "$out.log"; return 1
  fi
  llc "$out.tsan.ll" -filetype=obj "-O$lvl" -relocation-model=pic -o "$out.o" 2>> "$out.log" || return 1
  "$cc" -fsanitize=thread "$out.o" -o "$out" >> "$out.log" 2>&1
}
built() {  # built <out> <what>: 0 when it built, else a failure with its log
  if [[ -x "$1" ]]; then return 0; fi
  bad "$2 did not build under TSan"; sed 's/^/    /' "$1.log" 2>/dev/null | tail -8
  return 1
}

tsan_on="halt_on_error=0 abort_on_error=0 exitcode=66 print_suppressions=1 suppressions=$supp"
tsan_off="halt_on_error=0 abort_on_error=0 exitcode=66"
# run <tag> <options> <secs> <bin> <args...>: sets $rc, $out and $err
# (the path of TSan's stderr).
run() {
  local tag="$1" opts="$2" secs="$3"; shift 3
  err="$work/$tag.err"; rc=0
  out="$(gate_timeout "$secs" env TSAN_OPTIONS="$opts" ${runner[@]+"${runner[@]}"} "$@" 2> "$err")" || rc=$?
}
reports() { python3 "$work/reports.py" "$@"; }
matched_all=""
note_matched() { matched_all+="$(reports "$err" matched)"$'\n'; }

for lvl in 0 2; do
  build "$work/sync-O$lvl" "$sync" "$lvl"
  build "$work/chan-O$lvl" "$chan" "$lvl"
  build "$work/pipe-O$lvl" "$pipe" "$lvl"
  build "$work/atom-O$lvl" "$atom" "$lvl"
done
if [[ -f "$work/sync-O0.prep" ]]; then
  echo "   sync-load at -O0: $(cat "$work/sync-O0.prep")"
fi

# ---------------------------------------------------------------------
echo "== 2. the control: an unlocked shared word must be reported =="
for lvl in 0 2; do
  bin="$work/sync-O$lvl"
  built "$bin" "sync-load -O$lvl" || continue
  run "excl0-O$lvl" "$tsan_on" 120 "$bin" excl 0 "$N"; note_matched
  hits="$(reports "$err" races bump)"
  # The race is the unordered pair of accesses, not a lost update: a run
  # whose interleaving happened to lose nothing ('count 8000 ok', seen
  # once on linux-aarch64) races all the same, and TSan says so.
  if [[ "$out" == count\ * ]] && (( hits > 0 )); then
    ok "-O$lvl excl 0: TSan reported $hits race(s) on the plain word in bump ($out) - the detector sees an unlocked word"
  else
    bad "-O$lvl excl 0: no race reported in bump (exit $rc, '$out', $(reports "$err" count) report(s): $(reports "$err" first)) - the clean runs below cannot mean anything"
  fi
done

# ---------------------------------------------------------------------
echo "== 3. the synchronised programs are clean =="
# clean <tag> <what> <want: a bash pattern for stdout's last line> <bin> <args...>
clean() {
  local tag="$1" what="$2" want="$3"; shift 3
  run "$tag" "$tsan_on" 120 "$@"; note_matched
  local n last
  n="$(reports "$err" count)"; last="$(printf '%s\n' "$out" | tail -1)"
  if [[ "$n" == 0 && "$last" == $want ]] && (( rc == 0 )); then
    ok "$what: no report ($last)"
  else
    bad "$what: exit $rc, '$last', $n report(s): $(reports "$err" first)"
  fi
}
for lvl in 0 2; do
  bin="$work/sync-O$lvl"
  if built "$bin" "sync-load -O$lvl"; then
    clean "excl1-O$lvl" "-O$lvl excl 1 (the mutex)" "count $((4 * N)) ok" "$bin" excl 1 "$N"
    clean "stale-O$lvl" "-O$lvl stale (a stale guard under contention)" "stale-accepted 0 own-refused 0 count $((3 * N)) of $((3 * N)) ok" "$bin" stale "$N"
  fi
  bin="$work/chan-O$lvl"
  if built "$bin" "chan-load -O$lvl"; then
    clean "chan1-O$lvl" "-O$lvl chan-load stress 1 (a channel of one word)" "ok *" "$bin" stress 1 "$C"
    clean "chan64-O$lvl" "-O$lvl chan-load stress 64" "ok *" "$bin" stress 64 "$C"
  fi
  bin="$work/pipe-O$lvl"
  if built "$bin" "pipeline -O$lvl"; then
    clean "pipe-O$lvl" "-O$lvl examples/concurrency/pipeline.ax" "ok" "$bin"
  fi
  bin="$work/atom-O$lvl"
  if built "$bin" "atomics -O$lvl"; then
    clean "sbsc-O$lvl" "-O$lvl atomics sb sc" "0 *" "$bin" sb sc
    clean "addsc-O$lvl" "-O$lvl atomics add sc" "0 *" "$bin" add sc
    clean "addcas-O$lvl" "-O$lvl atomics add cas" "0 *" "$bin" add cas
    run "split-O$lvl" "$tsan_on" 120 "$bin" add split
    if [[ "$(reports "$err" count)" == 0 && "$out" =~ ^([0-9]+)\  ]] && (( rc == 0 )); then
      ok "-O$lvl atomics add split: no report, though ${BASH_REMATCH[1]} updates were lost - a lost update made of atomics is not a data race"
    else
      bad "-O$lvl atomics add split: exit $rc, '$out', $(reports "$err" count) report(s): $(reports "$err" first)"
    fi
  fi
done

# ---------------------------------------------------------------------
echo "== 4. the suppression list =="
rules="$(grep -vE '^[[:space:]]*(#|$)' "$supp")"
if [[ -z "$rules" ]]; then
  bad "tests/litmus/tsan-suppressions.txt holds no rule - section 4 checks nothing"
fi
reasonless="$(awk '/^[[:space:]]*$/ { prev = ""; next }
                  /^[[:space:]]*#/ { prev = "#"; next }
                  { if (prev != "#") print; prev = "r" }' "$supp")"
if [[ -n "$rules" && -z "$reasonless" ]]; then
  ok "every rule in the list has its reason directly above it"
elif [[ -n "$reasonless" ]]; then
  bad "rules with no reason above them: $(printf '%s' "$reasonless" | tr '\n' ' ')"
fi
while IFS= read -r rule; do
  [[ -n "$rule" ]] || continue
  times="$(printf '%s' "$matched_all" | awk -v r="$rule" '$2 == r { s += $1 } END { print s + 0 }')"
  if (( times > 0 )); then
    ok "'$rule' matched $times time(s) in sections 2 and 3 - not stale"
  else
    bad "'$rule' matched nothing in sections 2 and 3 - a stale suppression"
  fi
done <<< "$rules"
# Without the list: the rule's race, and nothing else. Each run must
# report nothing else; the race itself must be reported across the four.
# The pipeline's stall makes a waiter read the word in every run
# measured; the locked program reaches it only under contention, so a
# run of it that happens not to is not a failure on its own.
seen=0
for lvl in 0 2; do
  for prog in sync pipe; do
    bin="$work/$prog-O$lvl"
    [[ -x "$bin" ]] || continue
    args=(); [[ "$prog" == sync ]] && args=(excl 1 "$N")
    run "bare-$prog-O$lvl" "$tsan_off" 120 "$bin" ${args[@]+"${args[@]}"}
    read -r hit other <<< "$(reports "$err" reliance "$reliance")"
    seen=$((seen + hit))
    if (( other == 0 )); then
      ok "-O$lvl $prog without the list: $hit report(s), every one MM-PAR-12's plain read in $reliance against an atomic write"
    else
      bad "-O$lvl $prog without the list: $hit report(s) of the reliance and $other other(s): $(reports "$err" first)"
    fi
  done
done
if (( seen > 0 )); then
  ok "the race the rule names was reported $seen time(s) without the list - TSan finds MM-PAR-12's reliance unprompted"
else
  bad "no run without the list reported the race the rule names - the rule suppresses something these runs never show"
fi

# ---------------------------------------------------------------------
echo "== 5. ablations: each must be reported =="
# ablate <kind>: a copy of the stdlib with one rule removed.
ablate() {
  local kind="$1" dir="$work/abl-$1"
  rm -rf "$dir"; mkdir -p "$dir"
  cp -R "$repo_root/stdlib" "$dir/stdlib"
  python3 - "$dir/stdlib" "$kind" <<'PY'
import sys, os
root, kind = sys.argv[1], sys.argv[2]
cuts = {
  "lock": [("Sync.ax",
    "  (if (== (syncLoad m 3) 1)\n    (Err (mkError syncOwnerDead \"mutexLock: the holder died holding it\"))\n    (let ((me syncMe))\n      (if (== (syncCas m 0 me) 0)",
    "  (if (== (syncLoad m 3) 1)\n    (Err (mkError syncOwnerDead \"mutexLock: the holder died holding it\"))\n    (let ((me syncMe))\n      (if (== 0 0)")],
  "chan": [("Chan.ax", ";@axiom:effect(unsafe)\n(fn (chanLock ch)\n  (if (== (__atomic_cas ch 0 1) 0)", "(fn (chanLock ch)\n  (if (== 0 0)"),
           ("Chan.ax", "(fn (chanUnlock ch)\n  (if (== (__atomic_add ch (- 0 1)) 1)", "(fn (chanUnlock ch)\n  (if (== 1 1)")],
}[kind]
for f, old, new in cuts:
    p = os.path.join(root, f)
    s = open(p, encoding="utf-8").read()
    if s.count(old) != 1:
        sys.exit("seam %r in %s found %d times, wanted 1" % (old[:50], f, s.count(old)))
    open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
}
# red <what> <tag> <function the race must be in> <bin> <args...>
red() {
  local what="$1" tag="$2" fn="$3"; shift 3
  run "$tag" "$tsan_on" 60 "$@"
  local hits; hits="$(reports "$err" races "$fn")"
  if (( hits > 0 )); then
    ok "$what: red - TSan reported $hits race(s) in $fn (exit $rc, '$(printf '%s\n' "$out" | tail -1)')"
  else
    bad "$what: the ablated run was not reported in $fn (exit $rc, '$out', $(reports "$err" count) report(s): $(reports "$err" first))"
  fi
}
for kind in lock chan; do
  prog="$sync"; [[ "$kind" == chan ]] && prog="$chan"
  bin="$work/abl-$kind/prog"
  if ! ablate "$kind" 2> "$work/abl-$kind.log" || ! build "$bin" "$prog" 0 "$work/abl-$kind/stdlib"; then
    bad "$kind: the ablation did not apply or build"; cat "$work/abl-$kind.log" "$bin.log" 2>/dev/null | tail -6 | sed 's/^/    /'
    continue
  fi
  if cmp -s "$bin.ll" "$work/$( [[ "$kind" == lock ]] && echo sync || echo chan )-O0.ll"; then
    bad "$kind: the ablated build emitted the tree's IR - the copy was not what compiled"; continue
  fi
  if [[ "$kind" == lock ]]; then
    red "lock (stdlib/Sync.ax's compare-and-swap)" abl-lock bump "$bin" excl 1 "$N"
  else
    red "chan (stdlib/Chan.ax's lock)" abl-chan 'Chan$chanPut' "$bin" stress 1 "$C"
  fi
done
# The atomic add made a plain load and store in `addThread`'s IR.
if [[ -f "$work/atom-O0.ll" ]]; then
  if python3 - "$work/atom-O0.ll" "$work/abl-add.ll" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^define [^\n]*@addThread\(.*?^\}", s, flags=re.M | re.S)
if not m:
    sys.exit("no addThread in the IR")
n = [0]
def plain(a):
    n[0] += 1
    r, p, v = a.group(1), a.group(2), a.group(3)
    return (f"{r} = load i64, ptr {p}, align 8\n  %abl.{n[0]} = add i64 {r}, {v}\n"
            f"  store i64 %abl.{n[0]}, ptr {p}, align 8")
body = re.sub(r"(%[\w.]+) = atomicrmw add ptr (%[\w.]+), i64 ([\w.%-]+) seq_cst, align 8", plain, m.group(0))
if n[0] != 1:
    sys.exit("wanted one atomicrmw add in addThread, found %d" % n[0])
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(m.group(0), body))
PY
  then
    from_ll "$work/abl-add" "$work/abl-add.ll" 0 || true
    if built "$work/abl-add" "the ablated atomics program"; then
      red "atomic (add sc's atomicrmw made plain)" abl-add addThread "$work/abl-add" add sc
    fi
  else
    bad "atomic: the IR ablation did not apply"
  fi
fi

# ---------------------------------------------------------------------
echo "== 6. AddressSanitizer: what it can see here =="
if ! "$cc" -fsanitize=address "$work/probe.c" -o "$work/aprobe" > "$work/aprobe.log" 2>&1 \
     || ! env ASAN_OPTIONS=detect_leaks=0 "$work/aprobe" > /dev/null 2>&1; then
  if [[ "${AXIOM_TSAN_REQUIRED:-}" == 1 ]]; then
    bad "AXIOM_TSAN_REQUIRED=1 and no AddressSanitizer runtime for $cc: $(head -1 "$work/aprobe.log")"
  else
    skip "ASan: no AddressSanitizer runtime for $cc: $(head -1 "$work/aprobe.log")"
  fi
else
  cat > "$work/overread.ax" <<'AX'
; Read word K past a string literal's handle (`lit K`) or a 16-byte
; heap block (`heap K`), through the unsafe layer, and print it.
(import IO)
(import Sys)
(import Str)
(import Fmt)
(import Mem)

(:: peek (-> Int Int Int))
;@axiom:effect(unsafe)
;@axiom:precondition(the probe reads past `p` on purpose, for ASan to report)
(fn (peek p i)
  (__load64 p i))

(:: argInt (-> Int Int))
;@axiom:effect(io)
(fn (argInt i)
  (match (strParseInt (sysArg i))
    ((Some v) v)
    ((None) 0)))

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (main)
  (let (
    (k (argInt 2))
    (p (if (strEq (sysArg 1) "heap")
      (memAlloc 16)
      (cast Int "abcdefghijklmnop")))
  )
    {
      (println (fmtInt (peek p k)))
      0
    }))
AX
  abin="$work/overread"
  if (cd "$work" && "$axc" emit-llvm overread.ax -o "$abin.ll") > "$abin.log" 2>&1 \
     && sed -E 's/^(attributes #[0-9]+ = \{ )/\1sanitize_address /' "$abin.ll" > "$abin.san.ll" \
     && opt -passes=asan "$abin.san.ll" -S -o "$abin.asan.ll" 2>> "$abin.log" \
     && llc "$abin.asan.ll" -filetype=obj -O0 -relocation-model=pic -o "$abin.o" 2>> "$abin.log" \
     && "$cc" -fsanitize=address "$abin.o" -o "$abin" >> "$abin.log" 2>&1; then
    # The first word past the literal that ASan reports; every word before it must read clean.
    first=""; cleanrun=1
    for k in 0 1 2 3 4 5 6 7 8; do
      rc=0; gate_timeout 30 env ASAN_OPTIONS=detect_leaks=0:abort_on_error=0 "$abin" lit "$k" > "$abin.out" 2> "$abin.err" || rc=$?
      if grep -q 'ERROR: AddressSanitizer: global-buffer-overflow' "$abin.err"; then first="$k"; break; fi
      if (( rc != 0 )) || grep -q 'ERROR: AddressSanitizer' "$abin.err"; then cleanrun=0; break; fi
    done
    if [[ -n "$first" ]] && (( first > 0 && cleanrun )); then
      ok "ASan: words 0..$((first - 1)) past a string literal's handle read clean, and word $first is reported as a global-buffer-overflow"
    else
      bad "ASan: no clean prefix and reported overread past a string literal (first '$first', clean $cleanrun): $(grep -m1 ERROR "$abin.err")"
    fi
    rc=0; gate_timeout 30 env ASAN_OPTIONS=detect_leaks=0:abort_on_error=0 "$abin" heap 3 > "$abin.out" 2> "$abin.err" || rc=$?
    if grep -q 'ERROR: AddressSanitizer' "$abin.err"; then
      echo "note ASan: a read past a 16-byte heap block WAS reported: $(grep -m1 ERROR "$abin.err")"
    else
      echo "limit ASan: a read one word past a 16-byte heap block ran unreported (exit $rc) - the arena's blocks are invisible to it (not counted)"
    fi
  else
    bad "ASan: the overread probe did not build"; sed 's/^/    /' "$abin.log" | tail -6
  fi
fi

finish
