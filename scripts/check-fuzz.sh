#!/usr/bin/env bash
# Seeded compiler-input fuzzing: the fuzzing half of R-E1.
#
# WHY. Every other gate feeds the compiler programs somebody wrote on
# purpose - the corpus, the fixtures, the compiler's own source - and
# every one of those was fixed until it passed. What that cannot show is
# how the compiler behaves on the inputs nobody wrote: a form with one
# operand missing, a keyword where a name was, a byte that is not UTF-8,
# a let with five thousand bindings. `scripts/lib/fuzz.py` makes those
# from the corpus, deterministically, and this gate holds the compiler
# under test to three properties on every one:
#
#   P1  `axiom check` ANSWERS: exit 0 with no `error[AXnnnn]` line, or
#       exit 1 with at least one. Death by a signal (139 SIGSEGV, 134
#       abort, 138 SIGBUS), no answer by the deadline, a runtime trap's
#       status (70-79), a refusal that names no code, or an error
#       printed under exit 0 is a failure.
#   P2  a refusal says the same thing as JSON: `--diagnostic-format json
#       check` exits 1 too, and its stderr is well-formed JSON Lines as
#       docs/diagnostics.md states them (`json_ok` in fuzz.py spells the
#       contract out, the trailer line and the optional keys included).
#   P2h every answer `check` gives in the human format - a refusal, or
#       an acceptance that printed warnings - is safe to print to a
#       terminal: well-formed UTF-8, no control byte but the newline,
#       and no escape sequence but a colour from self_host/style.ax's
#       palette (`human_ok` in fuzz.py). Added 2026-09-27 when the
#       quoted source line was found echoing a mutant's raw NUL and ESC
#       bytes; a NUL cannot sit in a diagnostics fixture (the harness
#       reads lines through bash), and this is what pins it.
#   P3  a mutant `check` accepts is a mutant `emit-llvm` compiles (exit
#       0, IR written) and `llc` accepts - or one `emit-llvm` refuses
#       with AX4008 and nothing else. AX4008 is the one refusal decided
#       at emit rather than at check (it reads the module after
#       unreachable functions are pruned, so an uncalled helper is never
#       refused), and a bare-metal program - `tests/embedded/periodic.ax`
#       binds `isr(irq)` - checks OK and is refused for the host. Such a
#       mutant is counted apart, not as a pass: the `--long` run of
#       2026-09-28 met six. `emit-llvm` deliberately does
#       not require `main` (main.ax's `needMain`) while the prelude's
#       wrapper calls `@__axiom_user_main` unconditionally, so IR that
#       does not define it gets a stub definition before `llc` - measured
#       2026-09-27: all 115 corpus files with no `main` are llc-clean
#       with the stub and none of them is without it.
#
# SIX SECTIONS.
#
#   1. The generator: its selftest (splitmix64's published outputs, a
#      pinned digest of 200 mutants of an in-memory corpus - the check
#      that the same seed gives the same mutants on EVERY host, since a
#      digest of the tree's mutants moves with every `.ax` edit - the
#      scanner, and the JSON checker refusing twelve malformed reports),
#      then this run's mutants generated twice, in two processes under
#      two PYTHONHASHSEED values, and required byte-identical.
#   2. The run: every mutant through P1-P3. A failure prints the diff
#      against its corpus file, the tool's first lines and the one
#      command that reproduces it.
#   3. Stage floors: the run reached every stage - parsed, checked OK,
#      emitted, llc-accepted, refused, JSON-validated - at least once,
#      ran every mutant it generated, and at most 1% of mutants came out
#      identical to their source. A property no mutant reached was not
#      tested, and a green run that tested nothing is this repository's
#      commonest defect.
#   4. Controls: a planted wrapper compiler - the real one, except that
#      on seven chosen mutants it dies by SIGSEGV, sleeps past the
#      deadline, exits 1 in silence, exits with a trap's 77, answers a
#      real refusal with exit 0, appends a malformed line to its JSON,
#      or appends a raw NUL and an OSC escape to its human report; on
#      an eighth it appends a line that is not IR to what `emit-llvm`
#      wrote - is run through the SAME harness, which must report each
#      as the failure it is and must not excuse any of them as a known
#      one. Two more must NOT be reported: an untouched
#      mutant must still pass, and a real refusal with a raw NUL
#      appended to its report must still read as a refusal (grep reads
#      a file holding a NUL as binary and prints no match; that turned
#      a correct AX1001 into "no error line" on CI, 2026-09-28). If a
#      planted crash is not reported, the gate fails: without this, "no
#      mutant crashed" could mean "no crash can be seen".
#   5. Stored reproducers, `tests/fuzz/MANIFEST`: every crash the fuzzer
#      found, minimized, with a non-`.ax` extension so no census or
#      sweep reads it. A FIXED row must now pass P1-P3 (the regression
#      test). An OPEN row must still fail exactly as recorded - at its
#      stage, with the tool's own words matching its signature - and is
#      printed as XFAIL; if it stops failing, or fails differently, the
#      gate fails, so the list cannot go stale.
#   6. A tally of which OPEN rows excused mutants in section 2, where a
#      mutant failing at an OPEN row's stage with a message matching its
#      signature is printed as XFAIL and not counted red. A signature is
#      matched against the failure's DETAIL - the failing tool's own
#      first line, or for the JSON stage the validator's reason - never
#      the harness's summary sentence, and an empty detail matches
#      nothing: a silent signal death can never be excused. Section 5
#      refuses a signature that would match an empty message.
#
# LIMITS, stated because a green gate invites reading more into it.
# Green means: these mutants, at this seed, on this host, met P1-P3.
# Mutation explores the neighbourhood of the corpus, not the language:
# a crash that needs a construct no corpus file comes near is not
# found, and most mutants are refused before code generation (stage 3
# prints how many got there). P3 is `llc -O0` accepting the IR - it
# says nothing about what the IR computes; a miscompilation that yields
# valid IR is invisible here. The deadline measures hangs, not speed:
# the `long` edit is capped below a measured superlinear cliff (see
# fuzz.py `op_long`). Not fuzzed: `build`/`run` (linking, execution),
# the formatter, the LSP, the REPL, `--target` other than the host,
# and every command-line flag.
#
# Usage: check-fuzz.sh [--long] [--seed N] [--count N] [--only I] [--keep DIR]
#   --long     the scheduled budget: 6,000 mutants instead of 600
#   --seed N   another seed (the default is fixed, so CI is repeatable)
#   --count N  another count
#   --only I   generate and run mutant I of the seed alone - the
#              reproduce command every failure prints; skips 3-6
#   --keep DIR copy every failing mutant (with --only, that mutant
#              whatever its verdict) and its tool output into DIR
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

command -v llc >/dev/null || { echo "FAIL: llc is not on PATH"; exit 1; }
command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH"; exit 1; }

seed=20260927
count=600
diff_max=30
only=""
keep=""
while (( $# )); do
  case "$1" in
    --long) count=6000 diff_max=300 ;;
    --seed) seed="$2"; shift ;;
    --count) count="$2"; shift ;;
    --only) only="$2"; shift ;;
    --keep) keep="$2"; shift ;;
    *) echo "usage: $0 [--long] [--seed N] [--count N] [--only I] [--keep DIR]" >&2; exit 2 ;;
  esac
  shift
done
for v in "$seed" "$count" ${only:+"$only"}; do
  [[ "$v" =~ ^[0-9]+$ ]] || { echo "usage: --seed, --count and --only take a number, not '$v'" >&2; exit 2; }
done
[[ -n "$keep" ]] && { mkdir -p "$keep" || exit 2; keep="$(cd "$keep" && pwd)"; }

fuzz="$repo_root/scripts/lib/fuzz.py"
failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# The deadline per tool invocation. Measured 2026-09-27 on darwin-
# aarch64: over 9,000 mutants the slowest `check` of an ordinary one
# took 3.7s and the slowest emit-plus-llc 3.8s, but ONE took 35s and
# finished - `(import Vec)` mutated to `(import main)`, which the
# resolver's working-directory fallback answers with `self_host/main.ax`,
# so the mutant checked the whole compiler and drew 46 refusals. A 30s
# deadline called that a hang on this machine, and CI runners are
# slower. 120s is still a hang and not a slow input.
deadline=120

# ---------------------------------------------------------------------
# The harness. One function runs one input through P1-P3 and leaves its
# verdict in globals, so that the run, the controls and the stored
# reproducers are judged by the SAME code - a control that re-implemented
# the check would prove only that the control works.
#
# fuzz_one <compiler> <input.ax> <AXIOM_PATH> <deadline>
#   f_verdict  ok | refused | target (AX4008 at emit, P3's exception) | fail
#   f_stage    where it failed: check | json | emit | llc
#   f_why      the harness's sentence
#   f_detail   the failing tool's own first relevant line (for the JSON
#              stage, the validator's reason) - what signatures match
#   f_parsed f_ok f_emitted f_llc   the stages reached
#   f_json     for a refusal, the JSON report to validate (deferred, in
#              one python call per batch - see json_batch)
#   f_human    when `check` answered (refused, or accepted), its human
#              report, for P2h (deferred the same way - human_batch)
describe_rc() {  # <status> -> "exited N" / "killed by signal N (NAME)" / "timed out"
  local rc="$1"
  if (( rc == 124 )); then
    echo "timed out after ${deadline_used}s"
  elif (( rc > 128 )); then
    echo "killed by signal $((rc - 128)) (SIG$(kill -l $((rc - 128)) 2>/dev/null || echo '?'))"
  else
    echo "exited $rc"
  fi
}

first_line() {  # <file>: its first non-blank line, colour codes stripped, cut to 200
  { grep -a -m1 -v '^[[:space:]]*$' "$1" 2>/dev/null || true; } \
    | sed $'s/\x1b\\[[0-9;]*m//g' | cut -c1-200
}

fuzz_one() {
  local cc="$1" m="$2" ap="$3" rc=0 codes
  local b="${m%.ax}"
  deadline_used="$4"
  f_verdict=fail f_stage="" f_why="" f_detail="" f_json="" f_human=""
  f_parsed=0 f_ok=0 f_emitted=0 f_llc=0

  AXIOM_PATH="$ap" gate_timeout "$4" "$cc" check "$m" > "$b.cout" 2> "$b.cerr" < /dev/null || rc=$?
  if (( rc == 1 )); then
    # `-a`, and a code rather than any output: without `-a` a report
    # holding a NUL is "binary", and BSD grep then prints "Binary file
    # ... matches" where GNU grep prints nothing - one read as a code,
    # the other as silence, neither being what the report says.
    codes="$(grep -a -o 'error\[AX[0-9]\{4\}\]' "$b.cerr" || true)"
    if [[ "$codes" != *'error[AX'* ]]; then
      f_stage=check f_why="check exited 1 with no error[AXnnnn] line"
      f_detail="$(first_line "$b.cerr")"
      return
    fi
    f_human="$b.cerr"
    grep -q 'AX[12]' <<< "$codes" || f_parsed=1
    rc=0
    AXIOM_PATH="$ap" gate_timeout "$4" "$cc" --diagnostic-format json check "$m" \
      > "$b.jout" 2> "$b.jerr" < /dev/null || rc=$?
    if (( rc != 1 )); then
      f_stage=json f_why="--diagnostic-format json check $(describe_rc "$rc") where the human check exited 1"
      f_detail="$(first_line "$b.jerr")"
      return
    fi
    f_json="$b.jerr" f_verdict=refused
    return
  fi
  if (( rc != 0 )); then
    f_stage=check f_why="check $(describe_rc "$rc")"
    f_detail="$(first_line "$b.cerr")"
    return
  fi
  # The status and the report must agree: an error printed under exit 0
  # is a refusal a build script would read as success.
  if grep -a -q 'error\[AX[0-9]\{4\}\]' "$b.cerr"; then
    f_stage=check f_why="check exited 0 and printed an error[AXnnnn] line"
    f_detail="$( { grep -a -m1 'error\[AX' "$b.cerr" || true; } | sed $'s/\x1b\\[[0-9;]*m//g' | cut -c1-200)"
    return
  fi
  f_parsed=1 f_ok=1 f_human="$b.cerr"

  rc=0
  AXIOM_PATH="$ap" gate_timeout "$4" "$cc" emit-llvm "$m" -o "$b.ll" > "$b.eout" 2> "$b.eerr" < /dev/null || rc=$?
  # P3's one exception: exit 1 with AX4008 and no other error code.
  if (( rc == 1 )) && grep -a -q 'error\[AX4008\]' "$b.eerr" \
     && [[ -z "$(grep -a -o 'error\[AX[0-9]\{4\}\]' "$b.eerr" | grep -v 'AX4008' || true)" ]]; then
    f_verdict=target
    return
  fi
  if (( rc != 0 )); then
    f_stage=emit f_why="emit-llvm $(describe_rc "$rc") on a program check accepted"
    f_detail="$(first_line "$b.eerr")"
    return
  fi
  if [[ ! -s "$b.ll" ]]; then
    f_stage=emit f_why="emit-llvm exited 0 and wrote no IR"
    return
  fi
  f_emitted=1
  grep -a -q '^define [^@]*@__axiom_user_main(' "$b.ll" \
    || printf '\ndefine i64 @__axiom_user_main() {\n  ret i64 0\n}\n' >> "$b.ll"
  rc=0
  gate_timeout "$4" llc -O0 -filetype=obj "$b.ll" -o "$b.o" > "$b.lerr" 2>&1 || rc=$?
  rm -f "$b.o"
  if (( rc != 0 )); then
    f_stage=llc f_why="llc $(describe_rc "$rc") on the IR emit-llvm wrote"
    f_detail="$( { grep -a -m1 'error:' "$b.lerr" || true; } | sed 's/.*error: //' | cut -c1-200)"
    return
  fi
  f_llc=1 f_verdict=ok
  rm -f "$b.ll"
}

# fmt_one <compiler> <input.ax> <AXIOM_PATH>: P4 on one accepted mutant.
#   f4_verdict  ok | refused | fail;  f4_why, f4_detail as for fuzz_one
# `fmt` either refuses with a code, or writes a program that formatting
# again leaves byte-identical and that `check` still accepts. The
# formatter rewrites in place, so it only ever sees a copy.
fmt_one() {
  local cc="$1" m="$2" ap="$3" rc=0 b="${2%.ax}"
  deadline_used="$deadline"
  f4_verdict=fail f4_why="" f4_detail=""
  cp "$m" "$b.f1.ax"
  AXIOM_PATH="$ap" gate_timeout "$deadline" "$cc" fmt "$b.f1.ax" > "$b.f1.out" 2> "$b.f1.err" < /dev/null || rc=$?
  if (( rc != 0 )); then
    if (( rc == 1 )) && grep -a -q 'error\[AX[0-9]\{4\}\]' "$b.f1.err"; then
      f4_verdict=refused
    else
      f4_why="fmt $(describe_rc "$rc") on a program check accepted"
      f4_detail="$(first_line "$b.f1.err")"
    fi
    return
  fi
  cp "$b.f1.ax" "$b.f2.ax"
  rc=0
  AXIOM_PATH="$ap" gate_timeout "$deadline" "$cc" fmt "$b.f2.ax" > /dev/null 2> "$b.f2.err" < /dev/null || rc=$?
  if (( rc != 0 )) || ! cmp -s "$b.f1.ax" "$b.f2.ax"; then
    f4_why="fmt is not idempotent: formatting its own output $( (( rc != 0 )) && describe_rc "$rc" || echo "changed it")"
    f4_detail="$(diff "$b.f1.ax" "$b.f2.ax" 2>/dev/null | head -4 | tr '\n' ' ' | cut -c1-200)"
    return
  fi
  rc=0
  AXIOM_PATH="$ap" gate_timeout "$deadline" "$cc" check "$b.f1.ax" > /dev/null 2> "$b.f1.cerr" < /dev/null || rc=$?
  if (( rc != 0 )); then
    f4_why="the formatted program no longer checks (check $(describe_rc "$rc"))"
    f4_detail="$(first_line "$b.f1.cerr")"
    return
  fi
  f4_verdict=ok
}

# P5's eligibility: a mutant of a test program small enough to build
# twice, with a `main`, and naming nothing whose answer depends on the
# run (time, pids, arguments, input, concurrency) or that reaches outside
# the process (files, processes, the network, raw system calls, foreign
# code). Conservative by design: an excluded mutant is a comparison not
# made, never a failure excused.
diff_deny='parallel|__proc|__thread|__par_|Task|Chan|Sync|Micros|Nanos|GetPid|__argv|__argc|sysArg|sysEnv|readLine|readAll|sysRead|sysOpen|sysWrite[A-Z]|[Uu]nlink|[Rr]emove|[Mm]kdir|[Rr]ename|sysSpawn|sysRun|sysExec|writeFile|appendFile|__syscall|Http|Rpc|[Ss]ocket|sysKill|fetch|MapShared|sysChild|[Ff]fi|extern|__call_word'
diff_eligible() {  # <mutant.ax> <source path>
  [[ "$2" == tests/stdlib/* || "$2" == tests/selfhost/* ]] || return 1
  (( $(wc -c < "$1") <= 20000 )) || return 1
  grep -q '(fn (main' "$1" || return 1
  ! grep -qE -- "$diff_deny" "$1"
}

# diff_run <binary> <out>: run it where it can do no harm - a scratch
# directory, no input, 5 s, 1 MiB of output at most. Echoes its status.
diff_run() {
  local rc=0
  ( cd "$rundir" && ulimit -f 1024 && exec "$1" ) < /dev/null > "$2" 2> /dev/null &
  local pid=$!
  # The watchdog polls rather than sleeping 5 s: a `sleep` left behind
  # holds the caller's `$(...)` open until it ends, so every run would
  # take the whole deadline.
  ( for _ in {1..50}; do kill -0 "$pid" 2>/dev/null || exit 0; sleep 0.1; done
    kill -KILL "$pid" 2>/dev/null ) > /dev/null 2>&1 &
  local watch=$!
  wait "$pid" || rc=$?
  kill "$watch" 2>/dev/null; wait "$watch" 2>/dev/null
  echo "$rc"
}

# diff_one <compiler> <input.ax> <AXIOM_PATH>: P5, the miscompilation
# oracle. `--opt 0` and `--opt 2` builds of one program must answer the
# same stdout and exit status.
#   f5_verdict  agree | inconclusive | fail;  f5_why, f5_detail
# Inconclusive, and counted apart: a run cut short (killed by the 5 s
# deadline or the output limit), or an `--opt 0` binary that answers
# differently twice (its output depends on the run - an address, say).
# A build the `--opt 0` side refuses is inconclusive too; one only the
# `--opt 2` side refuses is a failure.
diff_one() {
  local cc="$1" m="$2" ap="$3" b="${2%.ax}" rc=0 r0 r0b r2
  deadline_used="$deadline"
  f5_verdict=inconclusive f5_why="" f5_detail=""
  AXIOM_PATH="$ap" gate_timeout "$deadline" "$cc" build --opt 0 --input "$m" --output "$b.o0" > "$b.b0" 2>&1 \
    || { f5_why="the --opt 0 build failed"; return; }
  AXIOM_PATH="$ap" gate_timeout "$deadline" "$cc" build --opt 2 --input "$m" --output "$b.o2" > "$b.b2" 2>&1 || rc=$?
  if (( rc != 0 )); then
    f5_verdict=fail f5_why="the --opt 2 build $(describe_rc "$rc") where --opt 0 built"
    f5_detail="$(first_line "$b.b2")"
    return
  fi
  r0="$(diff_run "$b.o0" "$b.r0")"
  r0b="$(diff_run "$b.o0" "$b.r0b")"
  r2="$(diff_run "$b.o2" "$b.r2")"
  for r in "$r0" "$r0b" "$r2"; do
    if (( r == 137 || r == 153 )); then f5_why="a run was cut short (status $r)"; return; fi
  done
  if [[ "$r0" != "$r0b" ]] || ! cmp -s "$b.r0" "$b.r0b"; then
    f5_why="the --opt 0 binary answered differently twice"; return
  fi
  if [[ "$r0" != "$r2" ]] || ! cmp -s "$b.r0" "$b.r2"; then
    f5_verdict=fail
    f5_why="--opt 0 and --opt 2 disagree: status $r0 against $r2"
    f5_detail="$(diff "$b.r0" "$b.r2" 2>/dev/null | head -4 | tr '\n' ' ' | cut -c1-200)"
    return
  fi
  f5_verdict=agree
}

# json_batch <list> <out>: validate every report named in <list>; <out>
# gets `<file><TAB><why>` for each malformed one. Answers the count
# checked in $json_checked.
json_batch() {
  local res
  res="$(python3 "$fuzz" json "$1")"
  json_checked="$(sed -n 's/^checked //p' <<< "$res")"
  grep -v '^checked ' <<< "$res" > "$2" || true
  [[ "$json_checked" =~ ^[0-9]+$ ]] || { bad "the JSON checker did not report a count: $res"; json_checked=0; }
}

# human_batch <list> <out>: the same for P2h's human reports; the count
# checked in $human_checked.
human_batch() {
  local res
  res="$(python3 "$fuzz" human "$1")"
  human_checked="$(sed -n 's/^checked //p' <<< "$res")"
  grep -v '^checked ' <<< "$res" > "$2" || true
  [[ "$human_checked" =~ ^[0-9]+$ ]] || { bad "the human checker did not report a count: $res"; human_checked=0; }
}

# The OPEN rows of tests/fuzz/MANIFEST, as `<stage><TAB><signature>`.
manifest="$repo_root/tests/fuzz/MANIFEST"
open_sigs="$work/open.sigs"
if [[ -f "$manifest" ]]; then
  awk -F'\t' '!/^#/ && NF >= 5 && $2 == "open" {print $4 "\t" $5 "\t" $1}' "$manifest" > "$open_sigs"
else
  : > "$open_sigs"
fi

# match_known: sets f_known to the reproducer whose OPEN row excuses
# this failure, or empty. The signature is an extended regex matched
# against f_detail - the failing tool's first line, or the JSON
# validator's reason - and an empty detail matches nothing, which is
# what keeps a silent SIGSEGV from ever being excused.
match_known() {
  local stage sig file
  f_known=""
  [[ "$f_verdict" == fail && -n "$f_detail" ]] || return 0
  while IFS=$'\t' read -r stage sig file; do
    [[ "$stage" == "$f_stage" && -n "$sig" ]] || continue
    if grep -qE -- "$sig" <<< "$f_detail"; then
      f_known="$file"
      return 0
    fi
  done < "$open_sigs"
}

# report_failure <name> <source> <ops> <mutant dir>
report_failure() {
  local name="$1" src="$2" ops="$3" dir="$4" f
  bad "$name ($src; $ops): $f_why${f_detail:+ - $f_detail}"
  echo "    reproduce: scripts/check-fuzz.sh --seed $seed --only $((10#${name#m})) --keep <dir>"
  python3 "$fuzz" diff --corpus-root "$repo_root" "$dir/manifest.tsv" "$dir" "$name" --lines 40 \
    | sed 's/^/    | /'
  for f in "$dir/$name.cerr" "$dir/$name.jerr" "$dir/$name.eerr" "$dir/$name.lerr"; do
    [[ -s "$f" ]] || continue
    echo "    ${f##*/}:"
    head -6 "$f" | sed $'s/\x1b\\[[0-9;]*m//g' | cut -c1-200 | sed 's/^/    > /'
  done
  if [[ -n "$keep" ]]; then
    cp "$dir/$name".* "$keep/" 2>/dev/null
    echo "    kept: $keep/$name.ax"
  fi
}

# ---------------------------------------------------------------------
echo "== 1. the generator: selftest, and one seed makes one set of mutants =="
if out="$(python3 "$fuzz" selftest 2>&1)"; then
  ok "$out"
else
  bad "the generator's selftest failed:"; echo "$out" | sed 's/^/    /'
fi

git ls-files '*.ax' > "$work/corpus.all" 2>"$work/corpus.err" \
  || { bad "git ls-files could not list the corpus: $(cat "$work/corpus.err")"; echo "check-fuzz: $checks passed, $failed failed"; exit 1; }
while IFS= read -r f; do [[ -f "$f" ]] && printf '%s\n' "$f"; done < "$work/corpus.all" > "$work/corpus"
ncorpus="$(wc -l < "$work/corpus" | tr -d ' ')"
if (( ncorpus == 0 )); then
  bad "the corpus is empty: git ls-files '*.ax' named no file on disk"
  echo "check-fuzz: $checks passed, $failed failed"; exit 1
fi

start=0
if [[ -n "$only" ]]; then start="$only"; count=1; fi
gen() {  # <out dir> <hash seed>
  PYTHONHASHSEED="$2" python3 "$fuzz" gen --seed "$seed" --count "$count" --start "$start" \
    --corpus "$work/corpus" --root "$repo_root" --out "$1"
}
mdir="$work/m"
if ! g1="$(gen "$mdir" 0 2>&1)" || ! g2="$(gen "$work/m2" 1 2>&1)"; then
  bad "the generator failed:"; printf '%s\n%s\n' "$g1" "${g2:-}" | sed 's/^/    /'
  echo "check-fuzz: $checks passed, $failed failed"; exit 1
fi
read -r _ digest _ identical <<< "$g1"
if [[ "$g1" == "$g2" ]] && diff -r "$mdir" "$work/m2" > /dev/null; then
  ok "seed $seed: $count mutants of $ncorpus corpus files, byte-identical from two processes (digest ${digest:0:16})"
else
  bad "seed $seed generated different mutants in two processes: '$g1' vs '$g2'"
fi
rm -rf "$work/m2"
echo "   reproduce any mutant I: scripts/check-fuzz.sh --seed $seed --only I --keep <dir>"

# ---------------------------------------------------------------------
echo "== 2. $count mutants through check, the JSON renderer, emit-llvm and llc =="
n_run=0 n_parsed=0 n_ok=0 n_emitted=0 n_llc=0 n_refused=0 n_fail=0 n_known=0 n_target=0
: > "$work/json.list"; : > "$work/json.names"
: > "$work/human.list"; : > "$work/human.names"
ok_names=() refused_names=()
t0=$SECONDS
while IFS=$'\t' read -r name src ops; do
  [[ -n "$name" ]] || continue
  fuzz_one "$axc" "$mdir/$name.ax" "$(dirname "$src")" "$deadline"
  n_run=$((n_run + 1))
  n_parsed=$((n_parsed + f_parsed)); n_ok=$((n_ok + f_ok))
  n_emitted=$((n_emitted + f_emitted)); n_llc=$((n_llc + f_llc))
  if [[ -n "$f_human" ]]; then
    printf '%s\n' "$f_human" >> "$work/human.list"
    printf '%s\t%s\t%s\n' "$name" "$src" "$ops" >> "$work/human.names"
  fi
  case "$f_verdict" in
    ok) ok_names+=("$name") ;;
    target) n_target=$((n_target + 1)) ;;
    refused)
      n_refused=$((n_refused + 1)); refused_names+=("$name")
      printf '%s\n' "$f_json" >> "$work/json.list"
      printf '%s\t%s\t%s\n' "$name" "$src" "$ops" >> "$work/json.names" ;;
    fail)
      match_known
      if [[ -n "$f_known" ]]; then
        n_known=$((n_known + 1))
        echo "XFAIL $name ($src): $f_stage - $f_detail [open: tests/fuzz/$f_known]" | tee -a "$work/xfail.log"
      else
        n_fail=$((n_fail + 1))
        report_failure "$name" "$src" "$ops" "$mdir"
      fi ;;
  esac
  if [[ -n "$only" && -n "$keep" ]]; then
    cp "$mdir/$name".* "$keep/" 2>/dev/null
    echo "   $name ($src; $ops): $f_verdict${f_why:+ - $f_why}; kept in $keep/$name.ax"
  elif [[ -n "$only" ]]; then
    echo "   $name ($src; $ops): $f_verdict${f_why:+ - $f_why}"
  fi
done < "$mdir/manifest.tsv"

json_batch "$work/json.list" "$work/json.bad"
n_json=$((json_checked))
while IFS=$'\t' read -r jf why; do
  [[ -n "$jf" ]] || continue
  n_json=$((n_json - 1))
  name="$(basename "$jf" .jerr)"
  IFS=$'\t' read -r _ src ops < <(grep "^$name	" "$work/json.names")
  f_verdict=fail f_stage=json f_why="the JSON report is malformed" f_detail="$why"
  match_known
  if [[ -n "$f_known" ]]; then
    n_known=$((n_known + 1))
    echo "XFAIL $name ($src): json - $why [open: tests/fuzz/$f_known]" | tee -a "$work/xfail.log"
  else
    n_fail=$((n_fail + 1))
    report_failure "$name" "$src" "$ops" "$mdir"
  fi
done < "$work/json.bad"

human_batch "$work/human.list" "$work/human.bad"
n_human=$((human_checked))
while IFS=$'\t' read -r hf why; do
  [[ -n "$hf" ]] || continue
  n_human=$((n_human - 1))
  name="$(basename "$hf" .cerr)"
  IFS=$'\t' read -r _ src ops < <(grep "^$name	" "$work/human.names")
  f_verdict=fail f_stage=human f_why="the human report is not safe to print to a terminal" f_detail="$why"
  match_known
  if [[ -n "$f_known" ]]; then
    n_known=$((n_known + 1))
    echo "XFAIL $name ($src): human - $why [open: tests/fuzz/$f_known]" | tee -a "$work/xfail.log"
  else
    n_fail=$((n_fail + 1))
    report_failure "$name" "$src" "$ops" "$mdir"
  fi
done < "$work/human.bad"

echo "   $n_run run in $((SECONDS - t0))s: $n_parsed parsed, $n_ok checked OK, $n_emitted emitted, $n_llc llc-accepted, $n_target refused at emit by AX4008 for this host, $n_refused refused ($n_json with well-formed JSON); $n_human human reports terminal-safe; $n_known known-open (XFAIL), $n_fail new failures"
if (( n_fail == 0 )); then
  ok "no mutant crashed, hung, refused without a code, broke the JSON contract, wrote an unsafe human report or produced IR llc rejects ($n_known known-open)"
fi

# ---------------------------------------------------------------------
echo "== 2b. the formatter (P4) and --opt 0 against --opt 2 (P5) on the accepted mutants =="
# P4 on every mutant P3 passed. P5 on those `diff_eligible` admits, up to
# $diff_max: each is built at `--opt 0` and `--opt 2`, run in a scratch
# directory, and the two must agree. Built programs cost seconds each,
# so the default run compares a sample and `--long` ten times as many.
rundir="$work/run"; mkdir -p "$rundir"
n4_ok=0 n4_refused=0 n4_fail=0 n5_eligible=0 n5_agree=0 n5_inconc=0 n5_fail=0
diff_names=()
for name in "${ok_names[@]}"; do
  IFS=$'\t' read -r _ src ops < <(grep "^$name	" "$mdir/manifest.tsv")
  fmt_one "$axc" "$mdir/$name.ax" "$(dirname "$src")"
  case "$f4_verdict" in
    ok) n4_ok=$((n4_ok + 1)) ;;
    refused) n4_refused=$((n4_refused + 1)) ;;
    *) n4_fail=$((n4_fail + 1)); f_why="P4: $f4_why" f_detail="$f4_detail"; report_failure "$name" "$src" "$ops" "$mdir" ;;
  esac
  if (( n5_eligible < diff_max )) && diff_eligible "$mdir/$name.ax" "$src"; then
    n5_eligible=$((n5_eligible + 1)); diff_names+=("$name")
    diff_one "$axc" "$mdir/$name.ax" "$(dirname "$src")"
    case "$f5_verdict" in
      agree) n5_agree=$((n5_agree + 1)) ;;
      inconclusive) n5_inconc=$((n5_inconc + 1)) ;;
      *) n5_fail=$((n5_fail + 1)); f_why="P5: $f5_why" f_detail="$f5_detail"; report_failure "$name" "$src" "$ops" "$mdir" ;;
    esac
    rm -f "$mdir/$name".o0 "$mdir/$name".o2
  fi
done
echo "   P4: ${#ok_names[@]} accepted mutants formatted: $n4_ok idempotent and still accepted, $n4_refused refused with a code, $n4_fail failed"
echo "   P5: $n5_eligible eligible (of at most $diff_max): $n5_agree agreed, $n5_inconc inconclusive, $n5_fail disagreed"
if (( n4_fail == 0 && n5_fail == 0 )); then
  ok "the formatter kept every accepted mutant accepted and was idempotent, and --opt 0 and --opt 2 agreed on every program compared"
fi

if [[ -n "$only" ]]; then
  echo
  echo "check-fuzz: $checks passed, $failed failed (--only $only: sections 3-6 skipped)"
  (( failed == 0 )); exit
fi

# ---------------------------------------------------------------------
echo "== 3. stage floors: every property was reached =="
floor() {  # <n> <what>
  if (( $1 >= 1 )); then ok "$2: $1 of $n_run"; else bad "$2: none of $n_run mutants - that property was not tested"; fi
}
if (( n_run == count )); then ok "all $count generated mutants ran"; else bad "$n_run of $count generated mutants ran"; fi
floor "$n_parsed" "reached the checker (parsed)"
floor "$n_ok" "checked OK"
floor "$n_emitted" "emitted IR"
floor "$n_llc" "llc accepted the IR"
floor "$n_refused" "refused with a code"
floor "$n_json" "refused with a well-formed JSON report"
floor "$n_human" "answered with a terminal-safe human report"
if (( identical * 100 < count )); then
  ok "$identical of $count mutants identical to their source (under 1%)"
else
  bad "$identical of $count mutants are identical to their source - the mutator is not mutating"
fi

# ---------------------------------------------------------------------
echo "== 4. controls: a planted wrapper compiler's failures are reported =="
# Targets from the run's own verdicts: two it checked OK (IR corruption,
# and the untouched control) and eight it refused (the NUL and
# bad-human-report controls).
if (( ${#ok_names[@]} < 2 || ${#refused_names[@]} < 8 )); then
  bad "the run produced ${#ok_names[@]} OK and ${#refused_names[@]} refused mutants; the controls need 2 and 8"
else
  c_badir="${ok_names[0]}" c_clean="${ok_names[1]}"
  c_crash="${refused_names[0]}" c_hang="${refused_names[1]}" c_mute="${refused_names[2]}"
  c_trap="${refused_names[3]}" c_badjson="${refused_names[4]}" c_lie="${refused_names[5]}"
  c_nul="${refused_names[6]}"
  c_badhuman="${refused_names[7]}"
  wrap="$work/planted-axc"
  cat > "$wrap" <<'SH'
#!/bin/sh
# The compiler under test, except on the inputs named in $FUZZ_*.
json=0 emit=0 fmtcmd=0 build=0 opt="" in="" out="" prev=""
for a in "$@"; do
  case "$a" in
    *.ax) in="$a" ;;
    json) [ "$prev" = --diagnostic-format ] && json=1 ;;
    emit-llvm) emit=1 ;;
    fmt) fmtcmd=1 ;;
    build) build=1 ;;
  esac
  [ "$prev" = -o ] && out="$a"
  [ "$prev" = --output ] && out="$a"
  [ "$prev" = --opt ] && opt="$a"
  prev="$a"
done
case "$(basename "$in" .ax)" in
  "$FUZZ_CRASH") kill -SEGV $$ ;;
  "$FUZZ_HANG") exec sleep 120 ;;
  "$FUZZ_MUTE") exit 1 ;;
  "$FUZZ_TRAP") echo "axiom: trap: planted by check-fuzz.sh" >&2; exit 77 ;;
  "$FUZZ_LIE") "$FUZZ_REAL" "$@"; exit 0 ;;
  "$FUZZ_NUL")
    # A real refusal whose report carries a raw NUL, as a renderer
    # echoing a mutant's source line does: still a refusal.
    "$FUZZ_REAL" "$@"; rc=$?
    printf 'raw \000 byte\n' >&2
    exit $rc ;;
  "$FUZZ_BADIR")
    if [ "$emit" = 1 ]; then
      "$FUZZ_REAL" "$@" || exit $?
      echo "this line is not LLVM IR" >> "$out"
      exit 0
    fi ;;
  "$FUZZ_BADJSON")
    if [ "$json" = 1 ]; then
      "$FUZZ_REAL" "$@"; rc=$?
      echo "{this line is not JSON" >&2
      exit $rc
    fi ;;
  "$FUZZ_FMTBREAK")
    # P4's control: the formatter's first pass writes a program that
    # `check` refuses (a signature with no definition, AX3015).
    if [ "$fmtcmd" = 1 ]; then
      "$FUZZ_REAL" "$@" || exit $?
      printf '\n(:: plantedByCheckFuzz Int)\n' >> "$in"
      exit 0
    fi ;;
  "$FUZZ_MISCOMPILE")
    # P5's control: the `--opt 2` binary prints one line more.
    if [ "$build" = 1 ] && [ "$opt" = 2 ]; then
      "$FUZZ_REAL" "$@" || exit $?
      mv "$out" "$out.real"
      printf '#!/bin/sh\n"%s" "$@"\nrc=$?\necho planted by check-fuzz.sh\nexit $rc\n' "$out.real" > "$out"
      chmod +x "$out"
      exit 0
    fi ;;
  "$FUZZ_BADHUMAN")
    if [ "$json" = 0 ] && [ "$emit" = 0 ]; then
      "$FUZZ_REAL" "$@"; rc=$?
      printf 'planted by check-fuzz.sh: \000 \033]0;title\007\n' >&2
      exit $rc
    fi ;;
esac
exec "$FUZZ_REAL" "$@"
SH
  chmod +x "$wrap"
  export FUZZ_REAL="$axc" FUZZ_CRASH="$c_crash" FUZZ_HANG="$c_hang" FUZZ_MUTE="$c_mute" \
         FUZZ_TRAP="$c_trap" FUZZ_BADIR="$c_badir" FUZZ_BADJSON="$c_badjson" FUZZ_LIE="$c_lie" \
         FUZZ_NUL="$c_nul" FUZZ_BADHUMAN="$c_badhuman"
  cdir="$work/control"
  mkdir -p "$cdir"
  cp "$mdir/manifest.tsv" "$cdir/"
  # <kind> <mutant> <deadline> <want stage> <want why (ERE)>
  while read -r kind name dl want_stage want_why; do
    cp "$mdir/$name.ax" "$cdir/$name.ax"
    src="$(awk -F'\t' -v n="$name" '$1 == n {print $2}' "$mdir/manifest.tsv")"
    fuzz_one "$wrap" "$cdir/$name.ax" "$(dirname "$src")" "$dl"
    if [[ "$kind" == badjson && "$f_verdict" == refused ]]; then
      printf '%s\n' "$f_json" > "$cdir/json.list"
      json_batch "$cdir/json.list" "$cdir/json.bad"
      if [[ -s "$cdir/json.bad" ]]; then
        f_verdict=fail f_stage=json f_why="the JSON report is malformed"
        f_detail="$(cut -f2- "$cdir/json.bad")"
      fi
    fi
    if [[ "$kind" == badhuman && "$f_verdict" == refused ]]; then
      printf '%s\n' "$f_human" > "$cdir/human.list"
      human_batch "$cdir/human.list" "$cdir/human.bad"
      if [[ -s "$cdir/human.bad" ]]; then
        f_verdict=fail f_stage=human f_why="the human report is not safe to print to a terminal"
        f_detail="$(cut -f2- "$cdir/human.bad")"
      fi
    fi
    match_known
    if [[ "$kind" == clean ]]; then
      if [[ "$f_verdict" == ok ]]; then
        ok "control clean: $name, untouched by the wrapper, still passes P1-P3"
      else
        bad "control clean: $name failed through the wrapper ($f_why) - the wrapper is not transparent"
      fi
    elif [[ "$kind" == nul ]]; then
      # grep reads a report holding a NUL as binary and prints no
      # match: the harness called a correct refusal mute (CI 2026-09-28,
      # m00088, a NUL inserted into a line the renderer echoes).
      if [[ "$f_verdict" == refused ]]; then
        ok "control nul: $name, a refusal whose report carries a raw NUL, is still read as a refusal"
      else
        bad "control nul: $name gave verdict '$f_verdict' ($f_why) - a report holding a NUL hides its error line from the harness"
      fi
    elif [[ "$f_verdict" == fail && "$f_stage" == "$want_stage" && -z "$f_known" ]] \
         && grep -qE -- "$want_why" <<< "$f_why $f_detail"; then
      ok "control $kind: $name reported at $f_stage - $f_why${f_detail:+ - ${f_detail:0:60}}"
    else
      bad "control $kind: $name gave verdict '$f_verdict' stage '$f_stage' known '${f_known:-}' ($f_why) - wanted a $want_stage failure matching /$want_why/; the harness cannot see this failure"
    fi
  done <<ROWS
crash $c_crash $deadline check signal.11.\(SIGSEGV\)
hang $c_hang 3 check timed.out
mute $c_mute $deadline check no.error\[AXnnnn\].line
trap $c_trap $deadline check exited.77
lie $c_lie $deadline check exited.0.and.printed.an.error
badir $c_badir $deadline llc this.line.is.not.LLVM.IR|expected
badjson $c_badjson $deadline json not.JSON
badhuman $c_badhuman $deadline human raw.control.byte.0x00
clean $c_clean $deadline - -
nul $c_nul $deadline - -
ROWS
  # P4 and P5 through the same wrapper: one accepted mutant whose
  # formatted copy is planted with a refusal, and one eligible mutant
  # whose `--opt 2` binary is planted with an extra line. Each must be
  # reported as its property's failure; the clean mutant must still
  # pass P4 through the wrapper.
  c_fmt="${ok_names[2]:-}"
  c_diff="${diff_names[0]:-}"
  if [[ -z "$c_fmt" || -z "$c_diff" ]]; then
    bad "the run left no mutant for the P4 or P5 control (${#ok_names[@]} accepted, ${#diff_names[@]} eligible for P5)"
  else
    export FUZZ_FMTBREAK="$c_fmt.f1" FUZZ_MISCOMPILE="$c_diff"
    for n in "$c_fmt" "$c_diff" "$c_clean"; do cp "$mdir/$n.ax" "$cdir/$n.ax"; done
    src="$(awk -F'\t' -v n="$c_fmt" '$1 == n {print $2}' "$mdir/manifest.tsv")"
    fmt_one "$wrap" "$cdir/$c_fmt.ax" "$(dirname "$src")"
    if [[ "$f4_verdict" == fail && "$f4_why" == *"no longer checks"* ]]; then
      ok "control fmtbreak: $c_fmt reported - $f4_why"
    else
      bad "control fmtbreak: $c_fmt gave '$f4_verdict' ($f4_why) - P4 cannot see a formatter that changes what checks"
    fi
    src="$(awk -F'\t' -v n="$c_clean" '$1 == n {print $2}' "$mdir/manifest.tsv")"
    fmt_one "$wrap" "$cdir/$c_clean.ax" "$(dirname "$src")"
    if [[ "$f4_verdict" == ok || "$f4_verdict" == refused ]]; then
      ok "control clean: $c_clean passes P4 through the wrapper ($f4_verdict)"
    else
      bad "control clean: $c_clean failed P4 through the wrapper ($f4_why) - the wrapper is not transparent"
    fi
    src="$(awk -F'\t' -v n="$c_diff" '$1 == n {print $2}' "$mdir/manifest.tsv")"
    diff_one "$wrap" "$cdir/$c_diff.ax" "$(dirname "$src")"
    if [[ "$f5_verdict" == fail && "$f5_why" == *disagree* ]]; then
      ok "control miscompile: $c_diff reported - $f5_why${f5_detail:+ - ${f5_detail:0:60}}"
    else
      bad "control miscompile: $c_diff gave '$f5_verdict' ($f5_why) - P5 cannot see an --opt 2 binary that answers differently"
    fi
    unset FUZZ_FMTBREAK FUZZ_MISCOMPILE
  fi
  unset FUZZ_REAL FUZZ_CRASH FUZZ_HANG FUZZ_MUTE FUZZ_TRAP FUZZ_BADIR FUZZ_BADJSON FUZZ_LIE FUZZ_NUL FUZZ_BADHUMAN
fi

# ---------------------------------------------------------------------
echo "== 5. stored reproducers (tests/fuzz/MANIFEST) =="
rdir="$work/repro"
mkdir -p "$rdir"
if [[ ! -f "$manifest" ]]; then
  bad "tests/fuzz/MANIFEST is missing"
else
  # Every stored reproducer is listed, and every listed one is stored.
  ls "$repo_root/tests/fuzz" | grep '\.axfuzz$' | LC_ALL=C sort > "$rdir/on-disk"
  awk -F'\t' '!/^#/ && NF {print $1}' "$manifest" | LC_ALL=C sort > "$rdir/listed"
  if cmp -s "$rdir/on-disk" "$rdir/listed"; then
    ok "tests/fuzz: $(wc -l < "$rdir/listed" | tr -d ' ') reproducers, each listed in MANIFEST once"
  else
    bad "tests/fuzz and its MANIFEST disagree:"; diff "$rdir/on-disk" "$rdir/listed" | sed 's/^/    /'
  fi
  while IFS=$'\t' read -r file status ap stage sig what; do
    [[ -z "$file" || "$file" == \#* ]] && continue
    [[ -f "$repo_root/tests/fuzz/$file" ]] || continue
    stem="${file%.axfuzz}"
    cp "$repo_root/tests/fuzz/$file" "$rdir/$stem.ax"
    [[ "$ap" == - ]] && ap=""
    fuzz_one "$axc" "$rdir/$stem.ax" "$ap" "$deadline"
    if [[ "$f_verdict" == refused ]]; then
      printf '%s\n' "$f_json" > "$rdir/json.list"
      json_batch "$rdir/json.list" "$rdir/json.bad"
      if [[ -s "$rdir/json.bad" ]]; then
        f_verdict=fail f_stage=json f_why="the JSON report is malformed"
        f_detail="$(cut -f2- "$rdir/json.bad")"
      fi
    fi
    if [[ ( "$f_verdict" == refused || "$f_verdict" == ok ) && -n "$f_human" ]]; then
      printf '%s\n' "$f_human" > "$rdir/human.list"
      human_batch "$rdir/human.list" "$rdir/human.bad"
      if [[ -s "$rdir/human.bad" ]]; then
        f_verdict=fail f_stage=human f_why="the human report is not safe to print to a terminal"
        f_detail="$(cut -f2- "$rdir/human.bad")"
      fi
    fi
    case "$status" in
      fixed)
        if [[ "$f_verdict" == ok || "$f_verdict" == refused ]]; then
          ok "fixed $file: $f_verdict - $what"
        else
          bad "REGRESSION $file: $f_why${f_detail:+ - $f_detail} (was fixed: $what)"
        fi ;;
      open)
        if [[ ! "$stage" =~ ^(check|json|human|emit|llc)$ ]] || [[ -z "$sig" ]] || grep -qE -- "$sig" <<< ""; then
          bad "$file: an OPEN row needs a stage (check, json, human, emit or llc) and a signature that does not match an empty message - got '$stage' /$sig/"
        elif [[ "$f_verdict" == fail && "$f_stage" == "$stage" && -n "$f_detail" ]] \
           && grep -qE -- "$sig" <<< "$f_detail"; then
          ok "XFAIL $file: still fails at $stage - $f_detail (OPEN: $what)"
        elif [[ "$f_verdict" == fail ]]; then
          bad "$file fails DIFFERENTLY: $f_stage - $f_why${f_detail:+ - $f_detail}; MANIFEST says $stage /$sig/"
        else
          bad "$file no longer fails ($f_verdict): mark it fixed in tests/fuzz/MANIFEST and docs/assurance/verification.md"
        fi ;;
      *) bad "$file: status '$status' is neither fixed nor open" ;;
    esac
  done < "$manifest"
fi

# ---------------------------------------------------------------------
echo "== 6. the open rows that excused mutants in section 2 =="
# Informational, and deliberately not a check: every excusal already
# printed an XFAIL line naming its row, and section 5 holds each row to
# failing exactly as recorded.
while IFS=$'\t' read -r stage sig file; do
  n="$(grep -a -c "\[open: tests/fuzz/$file\]" "$work/xfail.log" 2>/dev/null || true)"
  echo "   OPEN tests/fuzz/$file ($stage /$sig/): excused ${n:-0} of this run's mutants"
done < "$open_sigs"

echo
echo "check-fuzz: $checks passed, $failed failed"
(( failed == 0 ))
