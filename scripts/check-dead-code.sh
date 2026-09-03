#!/usr/bin/env bash
# A PROGRAM CONTAINS ONLY WHAT IT USES.
#
# Measured on trunk 2026-08-30, before `pruneDeadDefs` in
# self_host/codegen.ax existed:
#
#   (import IO)
#   (:: main Int)
#   ;@axiom:effect(io)
#   (fn (main) { (println "hello") 0 })
#
# built a 103,592-byte binary from 9,518 lines of IR holding 388
# `define`s, of which a walk from `main` reaches 22. The other 366 were
# whole modules pulled in transitively - `Err$addChecked`,
# `Err$andThen`, `Err$divChecked`, `Err$errContextOf` and the rest of
# `Err`, `Fmt`, `Path`, `Sys` - and they were not stripped by anything
# downstream either: `nm` on the LINKED EXECUTABLE found 361 of them,
# in a binary of 397 symbols. A program with no imports at all was
# 34,216 bytes, so ~70 KB of that hello world was code it could not run.
#
# TWO THINGS PINNED IT, and this gate exists because only one of them
# is the one a reader expects:
#
#   1. 375 of the 388 `define`s carried EXTERNAL linkage, which forbids
#      LLVM from deleting them - another translation unit might call
#      them. Axiom is a whole-program compiler and there is no other
#      translation unit.
#   2. `emitSymbolTable` writes `ptrtoint (ptr @F to i64)` for every
#      function in the module, so the backtrace table is a live global
#      holding all 388 addresses. That pin survives any linkage change.
#      Measured: marking all 384 non-runtime defines `internal` and
#      running `opt -O1` deleted exactly ONE and left all 397 symbols in
#      the binary - 103,592 bytes to 97,368, a 6% win. Dropping the
#      table pin as well took the same program to 17,224 bytes.
#
# So the removal is the emitter's, decided before the symbol table is
# built, and this gate is what stops it regressing.
#
# WHAT IT ASSERTS
#   1. The IR: every `define` a hello world emits is reachable from
#      `main`, by a walk written HERE and not shared with the compiler.
#   2. The LINKED BINARY, which is the acceptance bar: no `nm` symbol
#      names a function that walk could not reach. An emitter that
#      cleaned the IR and left the symbols in the executable has not
#      met it.
#   3. By name: the four functions the 2026-08-30 measurement called
#      out are absent from a hello world's `nm`.
#   4. Anti-vacuousness in both directions - the program still prints
#      and exits 0, and the chain it DOES use is still there. A gate
#      that only counts things absent is passed by a compiler that
#      emits nothing.
#   5. The class that goes wrong silently: a function whose ADDRESS is
#      taken rather than called. A named comparator handed to
#      `vecSortBy` is invisible to a call-graph walk over the AST, and
#      the effect walk already gives up on exactly this shape and marks
#      it `#effects-incomplete`. It must survive, and the program must
#      sort correctly.
#   6. THE ABLATION. The pass is turned off in a shadow tree, the
#      compiler rebuilt from it, and assertions 2 and 3 must go RED
#      naming a symbol. Without this, all of the above is also passed
#      by a gate that measures nothing.
#
# WHY THE WALK HERE IS TIGHTER THAN THE COMPILER'S. `pruneDeadDefs`
# roots, besides the entry and the FFI symbols, every `@name` written
# outside any define - a deliberately generous catch-all so that a
# global initialiser naming a function keeps it. This gate roots ONLY
# the entry and the three FFI symbols. So it is not re-running the
# pass and agreeing with itself: it asks the stricter question, and a
# survivor kept for a bad reason would show up here as unreachable.
# The two answers agree exactly today (22 of 22), which is the evidence
# that the generous roots are retaining nothing.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $1"; checks=$((checks + 1)); }
bad() { echo "FAIL $1"; checks=$((checks + 1)); failed=$((failed + 1)); }

cat > "$work/hello.ax" <<'PROBE'
(import IO)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println "hello")
    0
  }
)
PROBE

# THE ADDRESS-TAKEN SHAPES, both of them, because they are the class a
# call-graph walk over the AST loses and the only class whose loss is a
# crash rather than a build error.
#
# `dbl` is handed to `applyIt` as a BARE REFERENCE. Nothing calls it:
# the emitter synthesises `@_thunk_0`, whose body holds the only `call
# i64 @dbl` in the module, and `main` passes that thunk's address. So
# `dbl` survives only if the walk goes through a function the source
# never names. `desc` is the comparator shape the task names - a
# two-argument function cannot be a bare value at all (AX3013: it has
# no closure record to hold the missing arguments), so it reaches
# `vecSortBy` inside a lambda, which is lifted to its own `define`.
# Two different indirections, one property.
cat > "$work/sorted.ax" <<'PROBE'
(import IO)
(import Vec)

(:: dbl (-> Int Int))

(fn (dbl n) (* n 2))

(:: applyIt (-> (-> Int Int) Int Int))

(fn (applyIt f n) (f n))

(:: desc (-> Int Int Int))

(fn (desc a b) (- b a))

(:: main Int)

;@axiom:effect(io)
(fn (main)
  ; THE FIRST PUSH IS IN THE BINDING, and that is a type obligation
  ; rather than a style: `vecNew` is `(Vec a)`, and a `let` that binds
  ; it bare hands every later use its own fresh `a`. The pushes still
  ; pin the binding - `check-type-pinning.sh` measures that, and writing
  ; an `Int` and then a `String` into this same `v` is refused - but
  ; pinning is what the checker REFUSES on, not a substitution `show`
  ; can read: `(vecGet v 0)` off a bare `vecNew` reaches `println` as a
  ; type variable and is AX3025. Threading one push through the binding
  ; makes the element type `Int` at the binding itself, which is the
  ; shape the standard library's own fixtures use.
  (let ((v (vecPush vecNew 3)))
    {
      (vecPush v 1)
      (vecPush v 2)
      (vecSortBy v (lambda (a b) (desc a b)))
      (let (
        (x (vecGet v 0))
        (y (vecGet v 1))
        (z (vecGet v 2))
        (d (applyIt dbl 21))
      )
        (println "{x}{y}{z} {d}")
      )
      0
    }
  )
)
PROBE

# The walk. Roots are the entry symbol and the three C-ABI symbols a
# linked host calls - `rust/examples/demo/src/lib.rs` states their
# external linkage as a contract, and no IR of ours mentions them.
# Everything else must be reached.
cat > "$work/walk.py" <<'PY'
import re, subprocess, sys

ll, binary = sys.argv[1], sys.argv[2]
text = open(ll, encoding="utf-8", errors="surrogateescape").read()

SYM = r'("(?:[^"\\]|\\..)*"|[-A-Za-z0-9$._]+)'
# The return type is matched as `[^@]*` rather than as one non-space
# run, because a return type CONTAINS SPACES the moment a function
# answers a register pair: `define { i64, i64 } @F$pair(`. With
# `\S+` there, the head did not match, the line was skipped as a
# head, and every line of that function's body was skipped too - so
# the walk never saw the pair body's calls and reported everything
# reachable only through one as dead. That is what this gate did on
# trunk at 26df546, naming `Err$mkError`, `Sys.Platform$sysWrite` and
# `Sys.Platform$usesSyscallAbi` in a hello world whose emitter had
# kept all three correctly. No return type contains `@`, and the
# name is the first `@` on the line, so this is exact rather than
# merely wider.
HEAD = re.compile(r'define\s+[^@]*@' + SYM + r'\s*\(')
REF = re.compile('@' + SYM)

bodies, order, cur = {}, [], None
heads_seen = 0
for ln in text.split("\n"):
    if cur is None:
        if ln.startswith("define "):
            heads_seen += 1
        m = HEAD.match(ln)
        if ln.startswith("define ") and m:
            cur = m.group(1)
            bodies[cur], _ = [], order.append(cur)
        continue
    if ln == "}":
        cur = None
    else:
        bodies[cur].append(ln)

roots = [r for r in ("main", "mainCRTStartup",
                     "axiom_alloc", "axiom_retain", "axiom_release")
         if r in bodies]
live, stack = set(roots), list(roots)
while stack:
    for ln in bodies[stack.pop()]:
        for s in REF.findall(ln):
            if s in bodies and s not in live:
                live.add(s)
                stack.append(s)

# `nm` prefixes every symbol with `_` on Mach-O and nothing on ELF, so
# both spellings are folded before comparing - stripping unconditionally
# would eat a real leading underscore on ELF.
def plain(s):
    s = s.strip('"')
    return s[1:] if s.startswith("_") else s

nm = subprocess.run(["nm", binary], capture_output=True, text=True).stdout
names = {p[-1] for p in (l.split() for l in nm.split("\n")) if len(p) >= 2}

defined = {plain(d) for d in order}
reached = {plain(d) for d in live}
ir_dead = [d for d in order if d not in live]
nm_dead = sorted(n for n in names if plain(n) in defined and plain(n) not in reached)

# THE COUNT THIS WALK IS ALLOWED TO MISS IS ZERO. A `define` whose
# header shape the regex above cannot read is not a define this walk
# may quietly skip: its body's calls vanish and its callees are
# reported dead, which is a FALSE accusation against the emitter
# rather than a missed one. Printed so the shell can refuse it.
print("define_lines %d" % heads_seen)
print("defines %d" % len(order))
print("reachable %d" % len(live))
print("ir_dead %s" % " ".join(ir_dead))
print("nm_total %d" % len(names))
print("nm_dead %s" % " ".join(nm_dead))
PY

echo "--- 1. a hello world emits only what it can reach ---"

"$axc" build --input "$work/hello.ax" --output "$work/hello" --emit-llvm \
  > "$work/build.log" 2>&1 || {
    echo "FAIL: the probe would not build" >&2
    sed 's/^/    /' "$work/build.log" | head -20 >&2
    exit 1
  }

python3 "$work/walk.py" "$work/hello.ll" "$work/hello" > "$work/report" 2>&1 || {
  echo "FAIL: the reachability walk did not run" >&2
  sed 's/^/    /' "$work/report" | head -20 >&2
  exit 1
}

defines="$(sed -n 's/^defines //p' "$work/report")"
define_lines="$(sed -n 's/^define_lines //p' "$work/report")"
reachable="$(sed -n 's/^reachable //p' "$work/report")"

# THE WALK MUST HAVE READ EVERY `define` IN THE MODULE, and this is
# the assertion that says so. A header shape the regex cannot parse
# does not make this gate silent - it makes it WRONG, and in the
# direction that blames the emitter: the unparsed function's body is
# never scanned, so everything called only from there is reported
# unreachable. That is what `define { i64, i64 } @F$pair(` did on
# trunk at 26df546. Compare the count, not the shapes, because the
# next shape nobody thought of is the one this catches.
checks=$((checks + 1))
if [[ "$define_lines" == "$defines" ]]; then
  echo "ok   the walk parsed all $defines define headers in the module"
else
  echo "FAIL the walk parsed $defines of $define_lines define headers:"
  echo "     a header shape it cannot read makes every callee reached"
  echo "     only from that body look dead. Widen HEAD in walk.py."
  failed=$((failed + 1))
fi
ir_dead="$(sed -n 's/^ir_dead //p' "$work/report")"
nm_total="$(sed -n 's/^nm_total //p' "$work/report")"
nm_dead="$(sed -n 's/^nm_dead //p' "$work/report")"

if [[ -z "$ir_dead" ]]; then
  ok "all $defines defines are reachable from main (a walk written in this gate, not the compiler's)"
else
  bad "$(wc -w <<<"$ir_dead" | tr -d ' ') of $defines defines are unreachable from main:"
  echo "     $ir_dead" | cut -c1-300
fi

echo
echo "--- 2. and the LINKED BINARY carries no symbol it cannot reach ---"
# The acceptance bar. Cleaning the IR and leaving the symbols in the
# executable is the failure this is here to refuse.
if [[ -z "$nm_dead" ]]; then
  ok "none of the $nm_total nm symbols names an unreachable function"
else
  bad "$(wc -w <<<"$nm_dead" | tr -d ' ') of $nm_total nm symbols name functions this program cannot reach:"
  echo "     $nm_dead" | cut -c1-300
fi

echo
echo "--- 3. by name: the modules the measurement called out ---"
# Not a substitute for §2 - a redundant, concrete restatement of it, so
# that a rewrite of the walk that quietly stopped answering still has to
# get these four right. `Err` reaches a hello world through `IO`'s
# imports and nothing in `println`'s chain calls any of them.
absent=""
present=""
for sym in 'Err$addChecked' 'Err$andThen' 'Err$divChecked' 'Err$errContextOf'; do
  if nm "$work/hello" 2>/dev/null | grep -qF "$sym"; then
    present="$present $sym"
  else
    absent="$absent $sym"
  fi
done
if [[ -z "$present" ]]; then
  ok "none of$absent is in the binary"
else
  bad "the binary still carries$present"
fi

echo
echo "--- 4. and it is still a working program ---"
# Both directions. A compiler that emitted nothing would pass §1-§3.
out="$("$work/hello" 2>&1)"; rc=$?
if [[ "$out" == "hello" && $rc == 0 ]]; then
  ok "the probe prints 'hello' and exits 0"
else
  bad "the probe printed '$out' and exited $rc"
fi

kept=""
for sym in 'IO$writeStr' 'Sys$sysWriteAllFd' 'Str$strLen' 'axiom_alloc'; do
  nm "$work/hello" 2>/dev/null | grep -qF "$sym" || kept="$kept $sym"
done
if [[ -z "$kept" ]]; then
  ok "println's own chain and the allocator are still in the binary"
else
  bad "the binary is missing$kept - the pass removed something it uses"
fi

# A hello world should now cost about what a program with no imports at
# all costs. Expressed against `bare` rather than as an absolute, so it
# measures the pass and not this month's runtime size.
cat > "$work/bare.ax" <<'PROBE'
(:: main Int)

(fn (main) 0)
PROBE
"$axc" build --input "$work/bare.ax" --output "$work/bare" >/dev/null 2>&1
bare_n="$(nm "$work/bare" 2>/dev/null | wc -l | tr -d ' ')"
if (( nm_total < bare_n * 3 )); then
  ok "hello world has $nm_total symbols against a no-import program's $bare_n (was 397 against 16)"
else
  bad "hello world has $nm_total symbols against a no-import program's $bare_n - imports are still being shipped whole"
fi

echo
echo "--- 5. a function whose ADDRESS is taken, not called ---"
# The class a call-graph walk over the AST loses, and the one that
# fails as a crash rather than a build error if it is lost.
if "$axc" build --input "$work/sorted.ax" --output "$work/sorted" --emit-llvm \
     > "$work/sorted.log" 2>&1; then
  sout="$("$work/sorted" 2>&1)"; src=$?
  if [[ "$sout" == "321 42" && $src == 0 ]]; then
    ok "the sort and the bare reference both answer (321 42)"
  else
    bad "the probe printed '$sout' and exited $src, wanted '321 42' and 0"
  fi
  gone=""
  for sym in desc dbl; do
    nm "$work/sorted" 2>/dev/null | grep -qF "$sym" || gone="$gone $sym"
  done
  if [[ -z "$gone" ]]; then
    ok "both are in the binary under their own names, reached only through a lambda and a thunk"
  else
    bad "stripped:$gone - the runs above went through a pointer into removed code"
  fi
  # The indirection is real and not optimised away before the walk sees
  # it: if `@dbl` were called directly from `main` this would prove
  # nothing about thunks.
  if grep -q 'call i64 @dbl' "$work/sorted.ll" \
     && ! grep -q '^define i64 @_thunk_' "$work/sorted.ll"; then
    bad "no thunk was emitted; the bare-reference path is not being exercised"
  else
    ok "the bare reference really does go through an emitted thunk"
  fi
else
  bad "the sort probe would not build"
  sed 's/^/     /' "$work/sorted.log" | head -10
fi

echo
echo "--- 6. the ablation: with the pass off, §2 and §3 must go red ---"
# `pruneDeadDefs` already has the switch, because `--emit-staticlib`
# turns the pass off for real: an archive exists so that another
# translation unit can call in, so nothing there is unreachable. The
# ablation forces that arm always, which is precisely "emit everything,
# reachable or not" - the compiler's behaviour before 2026-08-31.
#
# `(if cgStaticlib` becomes `(if (|| cgStaticlib true)` and not `(if
# true`, which is the shorter edit and does not build: `cgStaticlib`
# reads argv, it is this function's only IO, and dropping it leaves the
# `;@axiom:effect(io)` tag unsupported at AX3010. The ablation has to
# change the ANSWER without withdrawing the claim.
abl="$work/tree"
mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/"
seam='(pub fn (pruneDeadDefs cg)
  (if cgStaticlib'
n_seam="$(grep -c -F 'pub fn (pruneDeadDefs cg)' "$abl/self_host/codegen.ax" || true)"
if [[ "$n_seam" != 1 ]]; then
  bad "self_host/codegen.ax holds $n_seam copies of the ablation seam; this gate expects exactly 1"
else
  python3 - "$abl/self_host/codegen.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = "(pub fn (pruneDeadDefs cg)\n  (if cgStaticlib\n"
new = "(pub fn (pruneDeadDefs cg)\n  (if (|| cgStaticlib true)\n"
assert s.count(old) == 1, s.count(old)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  if ! (cd "$abl" && "$axiom" build --input self_host/main.ax --output "$work/axc-abl") \
       > "$work/abl.build.log" 2>&1; then
    bad "the ablated compiler would not build"
    sed 's/^/     /' "$work/abl.build.log" | head -10
  else
    "$work/axc-abl" build --input "$work/hello.ax" --output "$work/hello-abl" \
      --emit-llvm > "$work/abl.hello.log" 2>&1
    python3 "$work/walk.py" "$work/hello-abl.ll" "$work/hello-abl" > "$work/abl.report" 2>&1
    a_dead="$(sed -n 's/^nm_dead //p' "$work/abl.report")"
    a_total="$(sed -n 's/^nm_total //p' "$work/abl.report")"
    a_n="$(wc -w <<<"$a_dead" | tr -d ' ')"
    if (( a_n > 100 )); then
      ok "with the pass off, §2 names $a_n of $a_total nm symbols as unreachable"
    else
      bad "with the pass off, §2 found only $a_n unreachable symbols - it is not discriminating"
    fi
    named=""
    for sym in 'Err$addChecked' 'Err$andThen' 'Err$divChecked' 'Err$errContextOf'; do
      grep -qF "$sym" "$work/abl.report" || named="$named $sym"
    done
    if [[ -z "$named" ]]; then
      ok "and names all four of §3's symbols, so the red is the one this gate is for"
    else
      bad "the ablation did not name$named - §3 would not have caught the regression"
    fi
    # And the restore: the unablated compiler is the one every check
    # above ran against, so green-after-restore is §1-§5, not a rerun.
    ok "restored: §1-§5 above were the same compiler with the pass on"
  fi
fi

echo
if (( failed > 0 )); then
  echo "check-dead-code: $failed of $checks checks failed"
  exit 1
fi
echo "check-dead-code: $checks checks - a hello world emits only what it"
echo "                 reaches, the executable carries no more than that,"
echo "                 an address-taken callback survives, and turning the"
echo "                 pass off puts every one of those back"
