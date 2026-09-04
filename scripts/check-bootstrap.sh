#!/usr/bin/env bash
# The self-hosting fixpoint, rooted at the committed seed.
#
#   seed    bootstrap/axiom-<target>.ll - a previous compiler, as LLVM
#           IR, committed and hash-pinned. The only rung of this ladder
#           that is not built from the tree in front of you.
#   stage1  the current self_host/, compiled by the seed
#   stage2  the current self_host/, compiled by stage1 through stage1's
#           OWN driver
#   stage3  the same source again, compiled by stage2
#
# Self-hosting is reached when stage2 and stage3 are byte-identical: at
# that point the compiler reproduces itself exactly, so nothing about it
# depends on the seed any longer except the trust placed in it.
# Comparing stage1 against stage2 would prove less - stage1 was built by
# a different compiler and may legitimately differ - which is why the
# classic criterion starts one stage later.
#
# WHAT THIS USED TO PIN. The first rung was `"$axiom" build --input
# self_host/main.ax` with `$axiom` defaulting to target/release/axiom,
# and `cargo build --release` when that was missing: stage0, the Rust
# compiler, built stage1, and every rung above it was climbed on its
# credit. That compiler is being deleted, and the hazard is that a
# ladder DOES NOT FAIL when its root goes away. Repoint `$axiom` at a
# self-hosted binary and this script still climbs, still reaches a
# fixpoint, still exits 0 - while quietly no longer saying the thing it
# existed to say, which is that the compiler comes from this tree and
# not from a binary somebody already had. The root is now
# bootstrap/axiom-<target>.ll, which a clone has and cannot fake: it is
# checked against bootstrap/SHA256SUMS before it is used.
#
# WHAT IT PINS NOW, and what each half fails for.
#
#   the ladder    the seed compiles self_host/ into stage1 with `llc`
#                 and `cc` (NOT at -O0 - see the comment on the
#                 invocation), and from there the compiler builds
#                 itself twice THROUGH ITS OWN DRIVER. stage2 and
#                 stage3 must be byte-identical binaries, and the IR
#                 each driver run kept (`--emit-llvm`) byte-identical
#                 too. Nothing here is stored, so there is nothing to
#                 re-bless: every byte compared is recomputed from
#                 self_host/ on the run.
#
#   the corpus    the cases of tests/selfhost/ (151 today, floor 135),
#                 built end to end by
#                 stage3 and RUN, each checked against the exit status
#                 a human wrote on the case's own first line
#                 (`; expect N`). This is the half a re-bless cannot
#                 satisfy, in the strongest form available to a
#                 bootstrap gate: the expected answers were not
#                 produced by any compiler, they are part of the
#                 fixture's source bytes, and they carry 50 distinct
#                 values (floor 45) - so a compiler cannot
#                 pass them by answering one number. It is what
#                 notices a ladder that converged on a WRONG compiler,
#                 which byte-identity cannot: two compilers agreeing
#                 byte for byte on their own source says only that
#                 they agree.
#
#   fmt           stage2's `fmt` turns tests/fmt/syntax-zoo.ax into
#                 tests/fmt/syntax-zoo.expected.ax, and leaves that
#                 golden alone when re-run on it.
#
#   memory        one self-compile's peak RSS, under a ceiling (340
#                 MiB today; every move of it is dated and measured
#                 at the constant itself) and over an 8 MiB floor,
#                 with the IR it produced compared against the IR
#                 the ladder already has.
#
# WHAT IS DELIBERATELY NOT HERE. scripts/bootstrap-from-seed.sh already
# runs the OTHER ladder - seed -> stage1 -> stage2 -> stage3 with this
# script's `llc` and `cc`, and the same byte-identity check on the
# result. Repeating it would be two copies of one fact. What that
# script never does is let the compiler drive itself: its stages write
# LLVM to stdout and it finishes the job for them. So the ladder is
# split at the seam that matters - the seed builds stage1 here because
# the `llc` reasoning below has to live somewhere it is used, and
# everything above stage1 goes through `axiom build`, which is the part
# no other gate reaches. In CI the two run back to back in one job
# (.github/workflows/ci.yml, `Self-hosting fixpoint`), which is the
# other reason not to repeat its ladder: it has just been run, on this
# checkout, minutes earlier.
#
# WHY THE REPLACEMENT IS ADEQUATE. The only stored artefact this gate
# compares against is the zoo golden, which belongs to
# check-fmt-selfhost.sh and is defended there by a preservation
# verifier that reads the source bytes. Everything else - the fixpoint,
# the corpus answers, the memory ceiling, the running program - is
# recomputed, and the corpus answers are not derived from a compiler at
# all. A wrong compiler that re-blessed every golden in this repository
# would still have to answer 26 different numbers correctly on 90
# programs, print `self-hosted` from a 91st, and reproduce itself
# exactly twice.
#
# `$axiom` is provisioned the way every other gate provisions it, and
# is used here for one thing only: a third witness on the zoo golden.
# It is deliberately NOT the ladder's root. Rooting this gate at a
# compiler that is already installed is precisely the failure described
# above, and a clone that needs to bootstrap does not have one.
#
# THE DRILL, run rather than assumed. The tree was copied and ONE token
# changed in the copy: `fbinopToLLVM` in self_host/codegen.ax mapping
# `*` to `fadd` instead of `fmul`, so float multiplication adds. The
# compiler never multiplies floats itself, so the mutation is invisible
# to everything except a program that does - which is the interesting
# kind of wrong compiler, not the kind that fails to build. Pointed at
# that copy, this script said:
#
#   the seed built stage1     ok
#   stage2 == stage3          ok - identical IR (61,686 lines) and
#                             byte-identical binaries. The fixpoint is
#                             a fixpoint of a wrong compiler.
#   the zoo golden            ok, three times: stage2 produced it, the
#                             golden was a fixed point of it, and the
#                             installed compiler agreed. NOTHING had to
#                             be re-blessed for that - `fmt` is not
#                             codegen, so the stored artefact was
#                             already satisfied by the broken build.
#   the corpus                4 cases answered the wrong number:
#                             330-float said 48 where its first line
#                             says 52, 410-float-fields 10 for 26,
#                             510-mut-float 41 for 48, 550-field-chain
#                             9 for 22. Exit 1.
#
# Every check the pre-conversion script had would have passed that
# build. Putting the token back and re-running the same copy: every
# check green, exit 0.
#
# Requires: llc, cc. Not cargo, not rustc.
#
# Usage:  scripts/check-bootstrap.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

fail() { echo "FAIL: $*" >&2; exit 1; }

command -v llc >/dev/null || fail "llc is not on PATH"
command -v cc  >/dev/null || fail "cc is not on PATH"

# The LLVM middle end, which this ladder used to skip. `llc` does
# instruction selection and its own backend passes; it does not do the
# middle end, and nothing here ran `opt`, so every stage was built
# without it. Measured on one emitted compiler, 67,029 lines, built two
# ways and each then asked to compile self_host/main.ax: 16.52s with
# `llc` alone against 1.72s with `opt -O1` in front of it. This gate
# builds three stages and runs two of them over the whole compiler and
# 99 conformance cases, so it paid that 9.6x several times over.
#
# `opt` stays OPTIONAL, as `driver.ax` treats it - a PATH without it
# warns and builds, correct but slower - which is why it is not in the
# `command -v` checks above. The `llc` invocations are untouched; the
# reasoning about their level, recorded at the seed build below, still
# applies unchanged.
#
# Both stages go through the identical path, so the byte-identity this
# gate exists to check is unaffected.
have_opt=0
command -v opt >/dev/null && have_opt=1
[[ $have_opt -eq 1 ]] || echo "warn: opt is not on PATH - the ladder will be correct but far slower" >&2

optimised() {
  local in="$1" out="$2"
  if [[ $have_opt -eq 1 ]] && opt -O1 "$in" -S -o "$out" 2>/dev/null; then
    printf '%s' "$out"
  else
    printf '%s' "$in"
  fi
}

# Every stage resolves `(import Foo)` against `self_host/` and `stdlib/`
# relative to its working directory.
ln -s "$repo_root/stdlib" "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"

# ---------------------------------------------------------------
# The seed, and the fact that it is the seed.
#
# bootstrap-from-seed.sh checks these sums too, and this is not a
# duplicate of that check so much as a refusal to skip it: this script
# reads bootstrap/*.ll directly, so it owns the question of whether
# what it read is what the tree says. It is a corruption check, not a
# trust check - a committed hash and a committed file move together
# under any edit - and its value is that it names the file that
# changed, which a link error three steps later does not.
# ---------------------------------------------------------------
case "$(uname -s)" in
  Darwin)  os=darwin ;;
  Linux)   os=linux ;;
  FreeBSD) os=freebsd ;;
  *) fail "unsupported OS $(uname -s): the seeds cover darwin, linux and freebsd" ;;
esac
case "$(uname -m)" in
  arm64|aarch64) arch=aarch64 ;;
  x86_64|amd64)  arch=x86_64 ;;
  *) fail "unsupported architecture $(uname -m)" ;;
esac
target="$os-$arch"
seed_ll="bootstrap/axiom-$target.ll"
[[ -f "$seed_ll" ]] || fail "no seed for this host at $seed_ll"

[[ -f bootstrap/SHA256SUMS ]] \
  || fail "bootstrap/SHA256SUMS is missing: an unverifiable seed is not a seed"
if command -v sha256sum >/dev/null; then
  sumcheck() { sha256sum -c SHA256SUMS; }
else
  sumcheck() { shasum -a 256 -c SHA256SUMS; }
fi
(cd bootstrap && sumcheck) >"$work/sums.log" 2>&1 \
  || { sed 's/^/    /' "$work/sums.log" >&2; fail "a bootstrap seed does not match its recorded hash"; }
# All four seeds are checked, not just this host's: the sums file names
# them all, and a corrupt seed for another target is a fact about this
# checkout worth hearing here rather than on someone else's machine.
echo "ok   the seeds match bootstrap/SHA256SUMS ($seed_ll is this host's)"

# `llc` carries an explicit relocation model, which axiom-cli documents
# as required of every `llc` invocation in the project including these.
#
# It deliberately does NOT carry -O0, even though the emitted bump
# allocator is miscompiled by `llc` at -O1 and above (two consecutive
# `memAlloc 64` calls come back a whole 1 MiB chunk apart). The two
# hazards pull opposite ways: at -O0 the allocator is correct but there
# is no tail-call elimination, and a stage compiling its own source
# overflows its stack - measured, it segfaults. That is not a stale
# note: a change that lengthened one table made a stage SIGSEGV right
# here, because a linear scan over it cost one stack frame per entry.
# `axiom build` escapes both by running `opt` over the IR before `llc`,
# which these scripts cannot assume is installed (axiom-cli treats a
# missing `opt` as a warning) - so the rungs BELOW `axiom build` stay
# opt-free, and adding `opt` here to "fix" something is the wrong fix
# twice over. Small programs get -O0 in check-stdlib-selfhost.sh, where
# the allocator matters and the stack does not.
llc -filetype=obj -relocation-model=pic "$(optimised "$seed_ll" "$work/seed.opt.ll")" \
    -o "$work/seed.o" 2>"$work/llc.err" \
  || { head -3 "$work/llc.err" >&2; fail "llc rejected $seed_ll"; }
cc "$work/seed.o" -o "$work/seed" $link_entry 2>"$work/cc.err" \
  || { head -3 "$work/cc.err" >&2; fail "could not link the seed"; }
echo "ok   seed built for $target from $seed_ll (no Rust, no cargo)"

# Build the next stage from a stage that has no driver yet: the stage
# compiles the file it is given and writes LLVM to stdout, so compiling
# the compiler means feeding it its own entry point.
build_next() {
  local from="$1" out_ll="$2" out_bin="$3"
  cp "$repo_root/self_host/main.ax" "$work/in.ax"
  (cd "$work" && "./$from" in.ax >"$out_ll" 2>"$out_ll.err") \
    || { head -5 "$work/$out_ll.err" >&2; fail "$from could not compile self_host/main.ax"; }
  # Blame the stage that produced the garbage, not the tool that chokes
  # on it: without these two lines a seed that was a valid Axiom
  # program but not a compiler failed as "llc rejected the IR", which
  # is true and points at the wrong file.
  grep -q "^target triple" "$work/$out_ll" \
    || fail "$from emitted no LLVM module - it is not a compiler"
  (( $(wc -l <"$work/$out_ll") > 10000 )) \
    || fail "$from emitted only $(wc -l <"$work/$out_ll") lines for the compiler - the emit was truncated"
  llc -filetype=obj -relocation-model=pic \
      "$(optimised "$work/$out_ll" "$work/$out_bin.opt.ll")" \
      -o "$work/$out_bin.o" 2>"$work/llc.err" \
    || { head -3 "$work/llc.err" >&2; fail "llc rejected the IR $from produced"; }
  cc "$work/$out_bin.o" -o "$work/$out_bin" $link_entry 2>"$work/cc.err" \
    || { head -3 "$work/cc.err" >&2; fail "could not link $out_bin"; }
}

# A stage has to compile and run something real, not just reproduce
# itself. stage1 gets this probe because it is the rung where a failure
# is cheapest to read; stage2 and stage3 get more than a probe below -
# the zoo, the corpus, and a program that prints.
check_runs() {
  local stage="$1"
  cat >"$work/in.ax" <<'CASE'
(:: add (-> Int Int Int))
(fn (add x y) (+ x y))
(:: main Int)
(fn (main) (add 40 2))
CASE
  (cd "$work" && "./$stage" in.ax >"prog.ll" 2>/dev/null) || fail "$stage could not compile the probe"
  llc -filetype=obj -relocation-model=pic "$work/prog.ll" -o "$work/prog.o" 2>/dev/null || fail "$stage emitted IR llc rejects"
  cc "$work/prog.o" -o "$work/prog" $link_entry 2>/dev/null || fail "$stage emitted an object that will not link"
  (cd "$work" && ./prog)
  local got=$?
  [[ "$got" == 42 ]] || fail "a program built by $stage answered $got, want 42"
  echo "ok   $stage compiles and runs a program correctly"
}

# ---------------------------------------------------------------
# The seed compiles the tree. This is also the staleness check, and it
# is the whole reason the seed is allowed to lag the source: if
# self_host/ starts using a construct the committed seed cannot
# compile, it fails HERE, naming the construct, and scripts/reseed.sh
# is the fix.
# ---------------------------------------------------------------
build_next seed stage1.ll stage1
echo "ok   the seed compiled the current self_host/ into stage1"
check_runs stage1

# ---------------------------------------------------------------
# The ladder, driven by the compiler itself.
#
# Everything a stage does above is `llc` and `cc` run on its behalf by
# this script: what that demonstrates is that a stage emits good IR,
# not that it can produce an executable. For most of this project's
# life stage1 could not - it wrote LLVM text to stdout and stopped, and
# every gate finished the job for it.
#
# `axiom build` does the whole job: writes the IR, runs `opt`, runs
# `llc`, runs `cc`, and cleans up after itself, spawning each child
# through `Sys.sysRunPath`. Both rungs above stage1 go through it, so
# the fixpoint being asserted is a fixpoint of the compiler AS SHIPPED,
# driver included.
#
# The two stages are built to the same BASENAME in different
# directories, and that is load-bearing on macOS: `ld` derives the
# Mach-O `LC_UUID` from the output path, so building `stage2` and
# `stage3` side by side makes two byte-identical compilers differ in 48
# bytes - 16 of UUID and the ad-hoc code signature that covers it -
# for a reason neither compiler caused. Measured; the emitted IR was
# identical throughout.
# ---------------------------------------------------------------
mkdir -p "$work/d2" "$work/d3"

if ! "$work/stage1" build --input "$repo_root/self_host/main.ax" \
     --output "$work/d2/axc" --emit-llvm >"$work/drv2.log" 2>&1; then
  sed 's/^/    /' "$work/drv2.log" | head -5 >&2
  fail "stage1 could not build stage2 through its own driver"
fi
echo "ok   stage2 built by stage1's own driver - no llc or cc from this script"

if ! "$work/d2/axc" build --input "$repo_root/self_host/main.ax" \
     --output "$work/d3/axc" --emit-llvm >"$work/drv3.log" 2>&1; then
  sed 's/^/    /' "$work/drv3.log" | head -5 >&2
  fail "stage2 could not build its own successor"
fi
echo "ok   stage3 built by stage2, with no Rust compiler anywhere in the chain"

# Anti-vacuousness before the comparison, not after it: `cmp` is
# happiest when both files are empty, and two missing compilers are
# byte-identical. The binary is 1.5 MB today and the IR 152,202 lines
# (re-measured 2026-08-24; the figures here read 588 KB and 61,688 and
# had been stale for long enough to be worth nothing as a floor's
# justification); the floors sit far below both and far above anything
# a failed build leaves behind.
for stage in d2 d3; do
  [[ -x "$work/$stage/axc" ]] || fail "$stage/axc is not an executable file"
  (( $(wc -c <"$work/$stage/axc") > 100000 )) \
    || fail "$stage/axc is $(wc -c <"$work/$stage/axc") bytes - too small to be the compiler"
  [[ -f "$work/$stage/axc.ll" ]] || fail "$stage/axc.ll was not kept - --emit-llvm did nothing"
  (( $(wc -l <"$work/$stage/axc.ll") > 10000 )) \
    || fail "$stage/axc.ll is $(wc -l <"$work/$stage/axc.ll") lines - the emit was truncated"
done

if ! cmp -s "$work/d2/axc.ll" "$work/d3/axc.ll"; then
  # `cmp a b >&2 | head -3`, which this used to be and which
  # bootstrap-from-seed.sh still is, pipes an already-redirected stdout
  # into a `head` that reads nothing. The report is wanted, so it is
  # spelled so that it arrives.
  cmp "$work/d2/axc.ll" "$work/d3/axc.ll" 2>&1 | head -3 | sed 's/^/    /' >&2
  fail "stage2 and stage3 emit different IR"
fi
echo "ok   stage2 and stage3 emit identical IR ($(wc -l <"$work/d2/axc.ll" | tr -d ' ') lines)"

if ! cmp -s "$work/d2/axc" "$work/d3/axc"; then
  fail "stage2 and stage3 IR matched but their binaries differ"
fi
echo "ok   stage2 and stage3 are byte-identical binaries - the fixpoint holds from the seed"

# ---------------------------------------------------------------
# stage2's formatter produces the golden zoo.
#
# check-fmt-selfhost.sh proves that the `fmt` in a compiler built by
# `$axiom` is the function the goldens describe. Nothing there runs the
# printer AS COMPILED BY A COMPILER THAT CAME FROM THE SEED: a
# miscompile of format.ax would leave the fixpoint intact - stage2 and
# stage3 are built by equally-affected parents - while stage2's `fmt`
# writes different bytes. One zoo pass through stage2 closes that hole:
# same golden, third compiler. `fmt` resolves no imports, so it needs
# none of the module plumbing the compile steps set up.
#
# The golden is also required to be a fixed point of itself, which is
# not a golden fact but a computed one: a printer that formats its own
# output differently is wrong however the golden was produced.
# ---------------------------------------------------------------
zoo="$repo_root/tests/fmt/syntax-zoo.ax"
zoo_golden="$repo_root/tests/fmt/syntax-zoo.expected.ax"
[[ -f "$zoo" && -f "$zoo_golden" ]] || fail "the fmt zoo or its golden is missing"
(( $(wc -l <"$zoo_golden") > 200 )) \
  || fail "$zoo_golden is $(wc -l <"$zoo_golden") lines - a golden that small pins nothing"

cp "$zoo" "$work/zoo2.ax"
(cd "$work" && "./d2/axc" fmt zoo2.ax >/dev/null 2>&1) \
  || fail "stage2's fmt refused the zoo that check-fmt-selfhost.sh formats"
cmp -s "$work/zoo2.ax" "$zoo_golden" \
  || { diff "$zoo_golden" "$work/zoo2.ax" | head -10 | sed 's/^/     /' >&2
       fail "stage2's fmt does not produce the golden zoo"; }
echo "ok   stage2's fmt produces the golden zoo"

cp "$zoo_golden" "$work/zoo3.ax"
(cd "$work" && "./d2/axc" fmt zoo3.ax >/dev/null 2>&1) \
  || fail "stage2's fmt refused the golden it just produced"
cmp -s "$work/zoo3.ax" "$zoo_golden" || fail "the zoo golden is not a fixed point of stage2's fmt"
echo "ok   the zoo golden is a fixed point of stage2's fmt"

# The third witness, and the only thing `$axiom` is used for. Not a
# differential - both compilers are checked against the golden, so a
# bug they share shows up as two failures rather than as agreement.
cp "$zoo" "$work/zoo4.ax"
("$axiom" fmt "$work/zoo4.ax" >/dev/null 2>&1) \
  || fail "the installed compiler at $axiom refused the zoo"
cmp -s "$work/zoo4.ax" "$zoo_golden" \
  || fail "the installed compiler at $axiom does not produce the golden zoo - it predates a formatter change, or one of the two is wrong"
echo "ok   the installed compiler produces the same golden zoo"

# ---------------------------------------------------------------
# The corpus, answered by a compiler that came from the seed.
#
# This is the half a re-bless cannot satisfy. Every case in
# tests/selfhost/ carries its expected exit status on its own first
# line as `; expect N` - written by a person, describing what the
# program means, and stored in the file whose behaviour it describes.
# There is no golden here to regenerate: satisfying this by editing
# means editing 90 fixtures to agree with a broken compiler, one at a
# time, each next to the source that contradicts it.
#
# It is not check-self-host.sh repeated. That gate runs the corpus
# through a stage1 built by whatever `$axiom` is, on the raw `llc`
# path. These are the first questions ever put to a compiler that came
# from the SEED and was built by its own driver - and they are the only
# thing in this script that can tell a converged ladder from a
# converged CORRECT one. The old script put one question (40 + 2) to
# each of the three stages; this puts 90 to stage3, and keeps the
# 40 + 2 for stage1, where a failure is cheapest to read.
#
# Cases are copied to `in.ax` because some of them read it: 250-readfile
# opens "in.ax" and asserts it is non-empty, which is a statement about
# the case's own bytes and fails everywhere else.
# ---------------------------------------------------------------
sweep="$work/sweep"
mkdir -p "$sweep"
ln -s "$repo_root/stdlib" "$sweep/stdlib"
ln -s "$repo_root/self_host" "$sweep/self_host"
# Helper modules a case imports as a sibling; digit-prefixed files are
# the cases themselves.
cp "$repo_root"/tests/selfhost/[A-Z]*.ax "$sweep/" 2>/dev/null || true

swept=0; corpus_failed=0
: > "$work/wants"
for case_file in "$repo_root"/tests/selfhost/[0-9]*.ax; do
  name="$(basename "$case_file" .ax)"
  # A case missing its expectation is a FAILURE, not a skip: a case
  # that stops being checked reports nothing, and nothing is what
  # success looks like.
  want="$(sed -n '1s/^; expect \([0-9]*\).*/\1/p' "$case_file")"
  if [[ -z "$want" ]]; then
    echo "FAIL $name: no '; expect N' on the first line, so nothing was checked" >&2
    corpus_failed=$((corpus_failed + 1))
    continue
  fi
  swept=$((swept + 1))
  echo "$want" >> "$work/wants"
  cp "$case_file" "$sweep/in.ax"
  # The previous case's binary is removed rather than overwritten: a
  # build that fails after `continue` would otherwise leave a program
  # behind for the next case to run, and a stale 42 is indistinguishable
  # from a fresh one.
  rm -f "$sweep/prog"
  if ! (cd "$sweep" && "$work/d3/axc" build --input in.ax --output prog) >"$sweep/build.log" 2>&1; then
    echo "FAIL $name: stage3 could not build it" >&2
    sed 's/^/    /' "$sweep/build.log" | head -3 >&2
    corpus_failed=$((corpus_failed + 1))
    continue
  fi
  (cd "$sweep" && ./prog >/dev/null 2>&1); got=$?
  if [[ "$got" != "$want" ]]; then
    echo "FAIL $name: a program built by stage3 answered $got, the case says $want" >&2
    corpus_failed=$((corpus_failed + 1))
  fi
done

# Floors. 157 cases carrying 53 distinct expectations today; a sweep
# that reads fewer than 60, or one whose expectations collapse to a
# handful of values, has lost its corpus or its parser - and either
# reads exactly like a compiler that answers everything correctly.
distinct="$(sort -u "$work/wants" | grep -c .)"
# Floor re-derived 2026-08-16 against 144 cases; it was 60, set when
# the tree held ~65, so more than half the corpus could have gone
# missing with the gate still green.
if (( swept < 135 )); then
  fail "the sweep ran only $swept cases; the floor is 135 - tests/selfhost/ moved or the glob broke"
fi
if (( distinct < 45 )); then
  fail "the $swept cases carry only $distinct distinct expected statuses; the floor is 45 (50 today) - a compiler that answers one number would pass"
fi
if (( corpus_failed > 0 )); then
  fail "$corpus_failed of $swept conformance cases disagree with the status their own source declares"
fi
echo "ok   $swept conformance cases, built and run by stage3, answer what their source says ($distinct distinct statuses)"

# And a program that PRINTS, because every case above communicates
# through its exit status alone and a compiler can get those right with
# its string handling entirely broken.
mkdir -p "$work/e2e"
ln -s "$repo_root/stdlib" "$work/e2e/stdlib"
cat >"$work/e2e/prog.ax" <<'CASE'
(import IO)
(:: main Int)
;@axiom:effect(io)
(fn (main) { (println "self-hosted") 42 })
CASE
(cd "$work/e2e" && "$work/d3/axc" build --input prog.ax --output prog >build.log 2>&1) \
  || { sed 's/^/    /' "$work/e2e/build.log" | head -5 >&2; fail "stage3 could not build a program that prints"; }
out="$("$work/e2e/prog")"; got=$?
[[ "$got" == 42 && "$out" == "self-hosted" ]] \
  || fail "a program built end to end by stage3 said '$out'/$got, want 'self-hosted'/42"
echo "ok   a program built end to end by stage3 prints and exits correctly"

# ---------------------------------------------------------------
# What one self-compile costs.
#
# This exists because the cost was once 16.9 GB and nothing said so.
# `renderCG` left-folded `strConcat` over the emitted line vector, which
# is one allocation and one full copy of everything emitted so far per
# line, over an allocator that never frees - so peak was the SUM of every
# intermediate rather than the largest, and it grew with the SQUARE of
# the compiler's own size. Measured on the same input before and after
# the two-pass join: 16,973,522,240 -> 72,958,912 bytes of peak
# footprint, 11.54 s -> 0.85 s, with byte-identical output.
#
# A ceiling rather than a benchmark: the number to protect is the shape,
# not the constant. Quadratic growth crosses 400 MB long before it
# crosses a CI runner's limit, and it presents as SIGKILL in an
# unrelated-looking job - which is why this is a gate and not a note.
#
# It measures rather than assumes it can: a platform where neither
# `time` spelling works fails here, because a resource check that
# silently skips is the failure this repository has hit twice. For the
# same reason there is a FLOOR as well as a ceiling, and the IR the
# measured run produced is compared against the IR the ladder already
# holds: a compiler that died on the first line would peak at nothing
# and pass a ceiling. The run measured is stage2 emitting the compiler
# - the driver-built configuration the project ships, and the same
# source the 16.9 GB was measured on.
# ---------------------------------------------------------------
peak_rss_kb() {
  # Darwin's `time -l` reports bytes; GNU's `time -v` reports kilobytes,
  # and so does FreeBSD's `time -l` - `ru_maxrss` is the kernel's unit,
  # bytes on Darwin alone, so the divisor is keyed on the kernel and
  # not on which flag answered (see `max_rss_kb` in check-recover.sh
  # for the measurement that found this).
  local div=1
  [[ "$(uname -s)" == Darwin ]] && div=1024
  if /usr/bin/time -l true >/dev/null 2>&1; then
    /usr/bin/time -l "$@" 2>&1 >"$work/peak.ll" \
      | awk -v div="$div" '/maximum resident set size/ { print int($1 / div) }'
  elif /usr/bin/time -v true >/dev/null 2>&1; then
    /usr/bin/time -v "$@" 2>&1 >"$work/peak.ll" \
      | awk '/Maximum resident set size/ { print $NF }'
  fi
}

cp "$repo_root/self_host/main.ax" "$work/in.ax"
peak="$(cd "$work" && peak_rss_kb ./d2/axc in.ax)"
if [[ -z "$peak" ]]; then
  fail "could not measure the self-compile's peak memory (no usable /usr/bin/time)"
fi
if ! cmp -s "$work/peak.ll" "$work/d3/axc.ll"; then
  fail "the measured self-compile did not emit the compiler - the number below would be of something else"
fi
floor=8192       # 8 MiB
# 400 -> 460 MiB on 2026-08-15, measured before moved: the evidence
# slice (MM-LIFE-2d) grew self_host by 969 lines and the peak from
# 392 to 414 MiB - 14.24 -> 14.37 KiB per source line, i.e. the
# LINEAR shape this ceiling exists to protect, held flat; the same
# source under the pre-evidence compiler peaks within 4 MiB of the
# evidence one, so the cost is input size, not machinery.
#
# 460 -> 540 MiB later the same day, and this one is a PER-ALLOCATION
# constant rather than source growth, measured three ways on one
# input before it was moved: the `Str` header grew from two words to
# three (MM-VAL-7's owner word), which crosses an allocator size
# class - 32-byte block to 48 - and the peak went 416 -> 475 MiB.
# Widening the header one class FURTHER, as a probe, cost another
# 63 MB (475 -> 535), and the pre-slice compiler on the same source
# peaks at 416. So each 16 bytes of `Str` header costs ~62 MB, which
# says this self-compile allocates ~3.9 MILLION string headers and
# frees none of them yet - the count is what the number measures,
# and the shape is still exactly linear. When MM-LIFE-2c's releases
# reach `Str` headers this comes back down; until then the ceiling
# leaves ~12% of headroom and a quadratic still crosses it in one
# slice.
#
# 540 -> 420 MiB on 2026-08-16, and the interesting half is what the
# old number had become. It was set with ~12% of headroom over 475;
# by the time it next failed the measurement was 534 and the headroom
# was 1%, eaten a slice at a time by commits that each passed. A
# ceiling only reports the run that crosses it, so the margin it is
# leaving is invisible until there is none - which is why this number
# now carries the measurement it was set from, and why moving it DOWN
# after a win is part of taking the win.
#
# The win: `escBody` (codegen.ax) escaped a string literal by growing
# an accumulator one byte at a time, quadratic in the literal's
# length, on every literal the compiler emits. Counting the bytes
# first and filling a single allocation took the same self-compile,
# on the same input, from 542 to 393 MiB - 27% - with BYTE-IDENTICAL
# IR out. It was found by the failure text below being right: a
# 1.4 KB addition to one diagnostic's prose in `explain.ax`, zero new
# lines, had moved the peak 5.3 MiB.
#
# 420 -> 384 MiB on 2026-08-22, and this file's own rule is why: "moving
# it DOWN after a win is part of taking the win". The measured peak is
# 301 MiB - the escBody fix that set the 420 figure was followed by the
# release-first and intrusive-dead-list work, and nobody moved the
# ceiling after them, so a 39% regression could have landed green.
# 340 leaves ~13% over the measured 301, which still catches the 38%
# the quadratic costs on its first run.
#
# 340 -> 384 MiB on 2026-08-24, and the drift this one records is the
# thing the entry above predicted. The type-namespace slice failed
# here at 340.6 MiB, and the three measurements that priced it say the
# machinery is not what grew:
#
#   HEAD's compiler on HEAD's source          333,648 KiB
#   HEAD's compiler on the NEW source         348,560 KiB   +4.47%
#   the NEW compiler on the NEW source        348,784 KiB   +0.06%
#
# The compiler CHANGE costs 0.06% on identical input; the other 4.47%
# is 623 more source lines to compile. And the shape the ceiling
# actually guards was measured rather than assumed, on synthetic
# inputs of 2,000 / 4,000 / 8,000 declarations:
#
#   before   36,240 -> 70,176 -> 137,792 KiB   (x1.937, x1.963)
#   after    36,352 -> 70,400 -> 138,304 KiB   (x1.937, x1.965)
#
# Doubling the input doubles the peak, at both compilers. Linear.
#
# The OTHER number this move records is that 301 had already become
# 325.8 MiB by 2026-08-24 - eaten by commits that each passed, which
# is exactly the invisible-margin failure the 540 -> 420 entry above
# describes and which nothing in this script had ever reported. The
# `ok` line now prints the headroom, so the next reader sees the
# margin shrinking instead of only the run that finally crosses it.
# And it came back DOWN the same day, without the ceiling moving: 340.6
# -> 323 MiB, measured by this gate against the container work
# (MM-LIFE-2h). Growth used to abandon a `Vec`'s old data block, and
# this compiler is made of vectors; doubling one now hands the old block
# to the allocator's free list. That is a 5% cut to the peak on a tree
# that had GROWN by two more slices of compiler source in between, so
# the reclamation more than paid for both. The ceiling stays at 384
# because 323 leaves it 15% of headroom, which is the margin this
# number is set to keep - and the `ok` line prints that margin now, so
# the next reader watches it shrink instead of meeting the run that
# finally crosses it.
#
# 384 -> 448 MiB on 2026-08-30, and this is the entry the one above
# predicted it would have to write: "the next reader watches it shrink
# instead of meeting the run that finally crosses it" - nobody watched,
# and the run that finally crossed it was a clean checkout of trunk.
# Measured here rather than assumed, because the failure text says
# "suspect an accumulator that copies" and that is a claim to answer:
#
#   clean trunk (ddc4430), this gate           384 MiB  -> FAILS
#   the same tree plus the AX3053 slice        385 MiB
#
# so the ceiling was already crossed by a tree with nothing new in it.
# The three-way split the 340 -> 384 entry established, on the
# `axiom build`-produced binary rather than the ladder's:
#
#   trunk's compiler on trunk's source        394,304 KiB
#   the NEW compiler on trunk's source        394,304 KiB   +0.00%
#   trunk's compiler on the NEW source        395,424 KiB   +0.28%
#   the NEW compiler on the NEW source        395,424 KiB   +0.28%
#
# The compiler CHANGE costs EXACTLY nothing on identical input - the
# two pairs are byte-for-byte equal - and the 0.28% is 366 more source
# lines. And the shape the ceiling actually guards, on synthetic inputs
# of 2,000 / 4,000 / 8,000 independent declarations:
#
#   before   68,112 -> 117,040 -> 215,696 KiB   (x1.72, x1.84)
#   after    68,112 -> 117,040 -> 215,696 KiB   (x1.72, x1.84)
#
# Identical at every size, and sub-linear in the declaration count.
# Nothing here copies.
#
# WHAT ACTUALLY MOVED IS THE COMPILER'S OWN SIZE, and it moved a long
# way. `self_host/` was 64,490 lines on 2026-08-25, when 323 MiB was
# measured and 384 was set to leave 15% over it; it is 81,138 lines on
# trunk today. That is +25.8% of source against +18.9% of peak, so the
# cost per source line FELL - 5.13 KiB/line then, 4.85 KiB/line now -
# which is the opposite of the regression this number exists to catch,
# and it is why the answer is a bigger ceiling rather than a hunt.
# 448 leaves 14% over the measured 385, the margin the entries above
# settled on.
#
# 448 -> 512 MiB on 2026-09-03, at the `parallel` slice, and the entry
# above wrote this one too: "448 leaves 14% over the measured 385" was
# true the day it was set and the margin was 0.7% by the day this ran -
# the tree BEFORE the slice peaked at 444.9 MiB against the 448
# ceiling, eaten by the Vec port and the `for` keyword and everything
# between, each of which passed. The slice crossed it at 449.9 MiB, and
# the three-way split says what moved, the same way both entries above
# said it:
#
#   base compiler on base source              455,616 KiB
#   the NEW compiler on base source           455,632 KiB   +0.004%
#   base compiler on the NEW source           460,704 KiB   +1.12%
#   the NEW compiler on the NEW source        460,720 KiB   +1.12%
#
# The compiler CHANGE - a thread and a process runtime, a keyword's
# parser, two primitives' emitters - costs 16 KiB on identical input.
# The 1.12% is 1,209 more source lines to compile, 4.2 KiB per line
# against the 4.85 the entry above measured, so the cost per line fell
# again. Nothing here copies. 512 leaves 13.8% over the measured 450,
# the margin these entries keep, and the `ok` line still prints it.

# 448 -> 512 MiB on 2026-09-03, and the margin was gone before this
# slice arrived: trunk at 6355946 (the `Vec` port landed) already
# peaks at 444.7 MiB under this gate's own compiler - 0.7% under the
# ceiling, eaten by the slices between 2026-08-30 and here, exactly
# the way the 540 -> 420 entry describes. The regions stage (S3 of
# docs/memory-model-v2-design.md) added 2,005 lines to self_host/ and
# crossed it at 454 MiB. Priced the way the two entries above price a
# move, on `axiom build`-produced binaries, in KiB:
#
#   trunk's compiler on trunk's source        455,360
#   the NEW compiler on trunk's source        455,440   +0.02%
#   trunk's compiler on the NEW source        465,184   +2.16%
#   the NEW compiler on the NEW source        465,280   +2.18%
#
# The compiler CHANGE costs 0.02% on identical input - the region pass
# does not run for a program whose signatures name no region, and this
# is that number - and the 2.16% is 2,005 more source lines out of
# 91,342, which is 2.2%. 4.98 KiB per source line before, 4.98 after:
# the linear shape, held flat, and the failure text's accumulator was
# looked for and is not there. 512 leaves 12.7% over the measured
# 454.4, inside the 12-15% band the entries above keep - and the
# reader this entry is for is the one merging three more slices onto
# the same trunk, who should expect to watch the margin again.
# NOT MOVED on 2026-09-04, and the number is here because the entries
# above all end by telling the next reader to watch the margin. The
# `.axir` record file started writing block bodies, which put
# `self_host/mir.ax` inside `self_host/main.ax`'s import closure - 1,824
# more source lines for a self-compile to read. Priced the same way, on
# `emit-llvm self_host/main.ax`, in KiB:
#
#   HEAD's compiler on HEAD's source          496,560
#   the NEW compiler on HEAD's source         496,560   +0.00%
#   HEAD's compiler on the NEW source         505,152   +1.73%
#   the NEW compiler on the NEW source        505,152   +1.73%
#
# The compiler CHANGE costs EXACTLY nothing on identical input - the two
# pairs are equal to the KiB - and the 1.73% is 4.7 KiB per added source
# line, against the 4.98 the entry above measured. The linear shape held.
# This gate's own measurement path reports 493 MiB against the 512
# ceiling, 3% of headroom, and HEAD's margin was already thin before
# this landed: the ceiling is left where it is because nothing here
# regressed, and the next slice onto this trunk should expect to be the
# one that has to move it and say why.
ceiling=524288   # 512 MiB, over a measured 454
if (( peak < floor )); then
  fail "the self-compile peaked at $peak KiB, under the $((floor / 1024)) MiB floor - that is not a measurement of compiling 73,298 source lines"
fi
if (( peak > ceiling )); then
  fail "one self-compile peaked at $((peak / 1024)) MiB, over the $((ceiling / 1024)) MiB ceiling - suspect an accumulator that copies"
fi
echo "ok   one self-compile peaks at $((peak / 1024)) MiB, under the $((ceiling / 1024)) MiB ceiling ($(( (ceiling - peak) * 100 / ceiling ))% headroom)"

echo
echo "fixpoint reached from $seed_ll: the Axiom compiler reproduces itself, builds itself, and answers $swept cases correctly"

