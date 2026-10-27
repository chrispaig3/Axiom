#!/usr/bin/env bash
# A PROGRAM CONTAINS ONLY WHAT IT USES.
#
# Measured on trunk 2026-08-30, before `pruneDeadDefs` in
# core/codegen.ax existed:
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
# The independent walk roots only entry and FFI symbols. It follows
# function addresses through global initializers without rooting every
# global. The late backtrace table's address/name/length triples are
# checked as reflection metadata before their function edges are omitted.
# The compiler also preserves externally observable top-level
# roots, including llvm.used; the structural probe below tests those.
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

(:: main ())

;@axiom:effect(io)
(fn (main)
  {
    (println "hello")
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

(:: quoted! (-> Int Int))
(fn (quoted! n) n)

(:: applyIt (-> (-> Int Int) Int Int))

(fn (applyIt f n) (f n))

(:: desc (-> Int Int Int))

(fn (desc a b) (- b a))

(:: neverUsed (-> Int Int))
(fn (neverUsed n) (+ n 17))

(:: unusedCaller (-> Int Int))
(fn (unusedCaller n) (applyIt neverUsed n))

(:: main ())

;@axiom:effect(io)
(fn (main)
  ; THE FIRST PUSH IS IN THE BINDING, and that is a type obligation
  ; rather than a style: `vecNew` is `(Vec a)`, and a `let` that binds
  ; it bare hands every later use its own fresh `a`. The pushes still
  ; pin the binding - `check-type-pinning.sh` measures that, and writing
  ; an `Int` and then a `String` into this same `v` is refused - but
  ; pinning is what the checker REFUSES on, not a substitution the
  ; hole rendering can read: `(vecGet v 0)` off a bare `vecNew` reaches `println` as a
  ; type variable and is AX3025. Threading one push through the binding
  ; makes the element type `Int` at the binding itself, which is the
  ; shape the standard library's own fixtures use.
  { (let v (vecPush vecNew 3))
    {
      (vecPush v 1)
      (vecPush v 2)
      (vecSortBy v (lambda (a b) (desc a b)))
      {
        (let x (vecGet v 0))
        (let y (vecGet v 1))
        (let z (vecGet v 2))
        (let q (applyIt quoted! 21))
        (let d (applyIt dbl q))

        (println "{x}{y}{z} {d}")
      }
    }
  }
)
PROBE

# The walk. Roots are the entry symbol and the three C-ABI symbols a
# linked host calls - `pkg/axiom-oxide/examples/demo/src/lib.rs` states their
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

GLOBAL = re.compile(r'@' + SYM + r'\s*=')

def balance(line):
    # LLVM quoted names and c-strings may contain delimiter bytes. A
    # semicolon outside a quote starts a comment, not an initializer.
    line = re.sub(r'"(?:[^"\\]|\\..)*"', '', line)
    line = line.split(';', 1)[0]
    return sum(line.count(c) for c in '([{<') - sum(line.count(c) for c in ')]}>')

nodes, order, cur = {}, [], None
heads_seen = globals_seen = globals_read = depth = 0
kind = None
for ln in text.split("\n"):
    if cur is not None:
        nodes[cur].append(ln)
        if kind == "function":
            if ln == "}":
                cur = None
        else:
            depth += balance(ln)
            if depth == 0:
                cur = None
        continue
    if ln.startswith("define "):
        heads_seen += 1
        m = HEAD.match(ln)
        if m:
            cur, kind = m.group(1), "function"
            nodes[cur] = [ln]
            order.append(cur)
    elif ln.startswith("@"):
        globals_seen += 1
        m = GLOBAL.match(ln)
        if m:
            globals_read += 1
            symbol = m.group(1)
            nodes[symbol] = [ln]
            depth = balance(ln)
            if depth > 0:
                cur, kind = symbol, "global"

# The late backtrace symbol table records addresses for display. Its
# function edges are reflective metadata, not executable callbacks; they
# pinned every dead function before pruning existed. Recognise the table
# by its complete address/name/length triples and verify every name byte.
# Ordinary function descriptors do not have this representation and keep
# all of their initializer edges.
TABLE = re.compile(r'@' + SYM + r' = internal constant \[(\d+) x i64\] \[')
ADDRESS = r'ptrtoint \(ptr @' + SYM + r' to i64\)'
RELATIVE = r'sub \(i64 ' + ADDRESS + r', i64 ' + ADDRESS + r'\)'
ROW = re.compile(r'  i64 ' + ADDRESS + r', i64 ' + ADDRESS + r', i64 (\d+),?')
RELROW = re.compile(r'  i64 ' + RELATIVE + r', i64 ' + RELATIVE + r', i64 (\d+),?')
STRING = re.compile(r'@' + SYM + r' = private unnamed_addr constant '
                    r'\[(\d+) x i8\] c"((?:[^"\\]|\\[0-9A-Fa-f]{2})*)"')

def llvm_bytes(value):
    return re.sub(rb'\\([0-9A-Fa-f]{2})',
                  lambda match: bytes([int(match[1], 16)]), value.encode())

reflections = set()
for symbol, lines in nodes.items():
    head = TABLE.fullmatch(lines[0])
    relative = lines[-1] == '], section "__TEXT,__const"'
    if not head or (not relative and lines[-1] != "]"):
        continue
    rows = [(RELROW if relative else ROW).fullmatch(line) for line in lines[1:-1]]
    if not rows or any(row is None for row in rows):
        continue
    if int(head[2]) != len(rows) * 3:
        continue
    for row in rows:
        if relative:
            function, function_base, name, name_base, length = row.groups()
            if function_base != symbol or name_base != symbol:
                break
        else:
            function, name, length = row.groups()
        if function not in order or name not in nodes:
            break
        literal = STRING.fullmatch(nodes[name][0])
        if not literal:
            break
        value = llvm_bytes(literal[3])
        spelling = function[1:-1] if function.startswith('"') else function
        if value != llvm_bytes(spelling) or len(value) != int(length) or len(value) != int(literal[2]):
            break
    else:
        reflections.add(symbol)
assert len(reflections) == 1, "expected one structurally verified backtrace symbol table"

roots = [r for r in ("main", "mainCRTStartup",
                     "axiom_alloc", "axiom_retain", "axiom_release")
         if r in nodes]
live, stack = set(roots), list(roots)
while stack:
    node = stack.pop()
    if node in reflections:
        continue
    for ln in nodes[node]:
        for symbol in REF.findall(ln):
            if symbol in nodes and symbol not in live:
                live.add(symbol)
                stack.append(symbol)

# `nm` prefixes every symbol with `_` on Mach-O and nothing on ELF, so
# both spellings are folded before comparing - stripping unconditionally
# would eat a real leading underscore on ELF.
def plain(s, ir=False):
    if ir:
        return (llvm_bytes(s[1:-1]).decode("utf-8", errors="surrogateescape")
                if s.startswith('"') else s)
    return s[1:] if sys.platform == "darwin" and s.startswith("_") else s

nm = subprocess.run(["nm", binary], capture_output=True, text=True).stdout
names = {p[-1] for p in (l.split() for l in nm.split("\n")) if len(p) >= 2}

defined = {plain(d, ir=True) for d in order}
reached = {plain(d, ir=True) for d in live}
ir_dead = [d for d in order if d not in live]
nm_dead = sorted(n for n in names if plain(n) in defined and plain(n) not in reached)

# THE COUNT THIS WALK IS ALLOWED TO MISS IS ZERO. A `define` whose
# header shape the regex above cannot read is not a define this walk
# may quietly skip: its body's calls vanish and its callees are
# reported dead, which is a FALSE accusation against the emitter
# rather than a missed one. Printed so the shell can refuse it.
print("define_lines %d" % heads_seen)
print("defines %d" % len(order))
print("global_lines %d" % globals_seen)
print("globals %d" % globals_read)
print("reachable %d" % sum(d in live for d in order))
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
global_lines="$(sed -n 's/^global_lines //p' "$work/report")"
globals="$(sed -n 's/^globals //p' "$work/report")"
if [[ "$global_lines" == "$globals" ]]; then
  ok "the walk parsed all $globals global headers in the module"
else
  bad "the walk parsed $globals of $global_lines global headers"
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
# Read the complete output before searching it. With pipefail, an
# early grep match can make nm's SIGPIPE look like a missing symbol.
if ! nm "$work/hello" > "$work/hello.nm" 2>/dev/null; then
  bad "nm could not read the hello-world binary"
  exit 1
fi
for sym in 'Err$addChecked' 'Err$andThen' 'Err$divChecked' 'Err$errContextOf'; do
  if grep -qF "$sym" "$work/hello.nm"; then
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
# `println` expands to `writeOut`, which writes through `ioWriteAll`
# with no `File` (7ccb5228); `writeStr` takes a `File` and is not on
# this path any more.
for sym in 'IO$writeOut' 'IO$ioWriteAllFrom' 'Str$strLen' 'axiom_alloc'; do
  grep -qF "$sym" "$work/hello.nm" || kept="$kept $sym"
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
(:: main ())

(fn (main) ())
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
  if ! nm "$work/sorted" > "$work/sorted.nm" 2>/dev/null; then
    bad "nm could not read the callback binary"
    exit 1
  fi
  gone=""
  for sym in desc dbl 'quoted!'; do
    grep -qF "$sym" "$work/sorted.nm" || gone="$gone $sym"
  done
  if [[ -z "$gone" ]]; then
    ok "named, quoted and lambda callbacks keep their target symbols"
  else
    bad "stripped:$gone - the runs above went through a pointer into removed code"
  fi
  python3 "$work/walk.py" "$work/sorted.ll" "$work/sorted" > "$work/sorted.report"
  if [[ "$(sed -n 's/^define_lines //p' "$work/sorted.report")" == "$(sed -n 's/^defines //p' "$work/sorted.report")" ]] \
     && [[ "$(sed -n 's/^global_lines //p' "$work/sorted.report")" == "$(sed -n 's/^globals //p' "$work/sorted.report")" ]] \
     && [[ -z "$(sed -n 's/^ir_dead //p' "$work/sorted.report")" ]] \
     && [[ -z "$(sed -n 's/^nm_dead //p' "$work/sorted.report")" ]]; then
    ok "the independent walk reaches every live callback through its initializer edges"
  else
    bad "the callback graph has unread or unreachable definitions"
    cat "$work/sorted.report"
  fi
  if ! grep -qE '^define .*@(neverUsed|unusedCaller)\(' "$work/sorted.ll" \
     && ! grep -qE 'neverUsed|unusedCaller' "$work/sorted.nm"; then
    ok "an unused address-taken callback and its caller are absent from IR and the binary"
  else
    bad "an unused callback descriptor still pins unreachable code"
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
echo "--- 6. global initializer boundaries and observable roots ---"
cat > "$work/graph.ax" <<'PROBE'
(import codegen)
(import IO)
(import Vec)
(import Str)

(:: has (-> (Vec String) String Bool))
(fn (has lines wanted)
  {
    (let mut found false)
    (let mut i 0)
    (while (< i (vecLen lines))
      {
        (if (strEq (vecGet lines i) wanted) (set found true))
        (set i (+ i 1))
      })
    found
  })

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let lines (vecPush vecNew "declare void @external()"))
    (vecPush lines "@deadPrivate = private constant ptr @deadCallback")
    (vecPush lines "@deadInternal = internal global ptr @deadCallback")
    (vecPush lines "; axiom-extern-lib probe_library")
    (vecPush lines "; axiom-device-refused probe_device")
    (vecPush lines "@visible = global ptr @visibleCallback")
    (vecPush lines "@llvm.used = appending global [1 x ptr] [ptr @irq], section \"llvm.metadata\"")
    (vecPush lines "@live = private constant [2 x ptr] [")
    (vecPush lines "  ptr @\"q\\31\",")
    (vecPush lines "  ptr @arena")
    (vecPush lines "]")
    (vecPush lines "@arena = internal global { ptr, i64 }")
    (vecPush lines "{ ptr @arenaPayload, i64 7 }")
    (vecPush lines ", align 8")
    (vecPush lines "@arenaPayload = internal global [1 x ptr]")
    (vecPush lines "[ptr @liveCallback]")
    (vecPush lines "@splitPointer = internal global ptr")
    (vecPush lines "@splitCallback")
    (vecPush lines "%Cell = type { ptr }")
    (vecPush lines "@named = internal global")
    (vecPush lines "%Cell { ptr @liveCallback }")
    (vecPush lines "@annotated = private global i64 7,")
    (vecPush lines "!associated !0")
    (vecPush lines "!0 = !{ptr @liveCallback}")
    (vecPush lines "@text = private constant [9 x i8] c\"<[{)]}>\\22\\00\"")
    (vecPush lines "define i64 @main() {")
    (vecPush lines "  %a = ptrtoint ptr @live to i64")
    (vecPush lines "  %b = ptrtoint ptr @splitPointer to i64")
    (vecPush lines "  %c = ptrtoint ptr @text to i64")
    (vecPush lines "  %d = ptrtoint ptr @named to i64")
    (vecPush lines "  %e = ptrtoint ptr @annotated to i64")
    (vecPush lines "  ret i64 0")
    (vecPush lines "}")
    (vecPush lines "define i64 @\"q\\31\"() {")
    (vecPush lines "  ret i64 0")
    (vecPush lines "}")
    (vecPush lines "define i64 @liveCallback() {")
    (vecPush lines "  ret i64 0")
    (vecPush lines "}")
    (vecPush lines "define i64 @splitCallback() {")
    (vecPush lines "  ret i64 0")
    (vecPush lines "}")
    (vecPush lines "define i64 @visibleCallback() {")
    (vecPush lines "  ret i64 0")
    (vecPush lines "}")
    (vecPush lines "define i64 @irq() {")
    (vecPush lines "  ret i64 0")
    (vecPush lines "}")
    (vecPush lines "define i64 @deadCallback() {")
    (vecPush lines "  ret i64 0")
    (vecPush lines "}")
    (vecPush lines "define i64 @_start() {")
    (vecPush lines "  ret i64 0")
    (vecPush lines "}")
    (vecPush lines "define i64 @axiom_alloc() {")
    (vecPush lines "  ret i64 0")
    (vecPush lines "}")
    (vecPush lines "define i64 @axiom_retain() {")
    (vecPush lines "  ret i64 0")
    (vecPush lines "}")
    (vecPush lines "define i64 @axiom_release() {")
    (vecPush lines "  ret i64 0")
    (vecPush lines "}")
    (let cg newCG)
    (set cg.lines lines)
    (pruneDeadDefs cg)
    (let out cg.lines)
    (if cgStaticlib
      (println (== (vecLen out) (vecLen lines)))
      {
        ; live aggregate callback
        (println (has out "define i64 @liveCallback() {"))
        ; quoted callback
        (println (has out "define i64 @\"q\\31\"() {"))
        ; internal chain
        (println (has out "@arenaPayload = internal global [1 x ptr]"))
        ; multiline type and value
        (println (has out "[ptr @liveCallback]"))
        ; trailing attribute
        (println (has out ", align 8"))
        ; bare pointer continuation
        (println (has out "@splitCallback"))
        ; pointer callback
        (println (has out "define i64 @splitCallback() {"))
        ; externally visible initializer root
        (println (has out "define i64 @visibleCallback() {"))
        ; llvm.used root
        (println (has out "define i64 @irq() {"))
        ; dead private global
        (println (! (has out "@deadPrivate = private constant ptr @deadCallback")))
        ; dead internal global
        (println (! (has out "@deadInternal = internal global ptr @deadCallback")))
        ; dead callback
        (println (! (has out "define i64 @deadCallback() {")))
        ; declaration boundary
        (println (has out "declare void @external()"))
        ; allocator ABI root
        (println (has out "define i64 @axiom_alloc() {"))
        ; retain ABI root
        (println (has out "define i64 @axiom_retain() {"))
        ; release ABI root
        (println (has out "define i64 @axiom_release() {"))
        (println (has out "; axiom-extern-lib probe_library"))
        (println (has out "; axiom-device-refused probe_device"))
        (println (has out "%Cell { ptr @liveCallback }"))
        (println (has out "!associated !0"))
        ; target-specific entry
        (println (! (has out "define i64 @_start() {")))
        (let bare newCG)
        (set bare.lines lines)
        (set bare.target 7)
        (pruneDeadDefs bare)
        (println (has bare.lines "define i64 @_start() {"))
      })
  })
PROBE
if AXIOM_PATH="$repo_root/core" "$axc" --diagnostic-format=ai build \
     --input "$work/graph.ax" --output "$work/graph" > "$work/graph.log" 2>&1; then
  graph_out="$("$work/graph" 2>&1)"; graph_rc=$?
  expected_graph="$(printf 'true\n%.0s' {1..22})"
  if [[ "$graph_rc" == 0 && "$graph_out" == "$expected_graph" ]]; then
    ok "private/internal initializer chains, quoted names, split values and attributes preserve exactly the live graph"
  else
    bad "the initializer graph probe exited $graph_rc or disagreed with its 22 obligations"
    printf '%s\n' "$graph_out"
  fi
  archive_out="$("$work/graph" --emit-staticlib 2>&1)"; archive_rc=$?
  if [[ "$archive_rc" == 0 && "$archive_out" == true ]]; then
    ok "static-library mode preserves every definition for external callers"
  else
    bad "static-library mode pruned the graph: '$archive_out' (exit $archive_rc)"
  fi
else
  bad "the global initializer graph probe would not build"
  sed 's/^/     /' "$work/graph.log" | head -20
fi

echo
echo "--- 7. driver directives and late thread backtrace edges ---"
cat > "$work/extern.c" <<'C'
long dce_twice(long n) { return n * 2; }
C
cat > "$work/extern.ax" <<'PROBE'
(import IO)
(extern "dce_probe"
  (twice :: (-> Int Int) (symbol "dce_twice")))
(:: deadLiteral String)
(fn (deadLiteral) "this unused final literal must not own the extern directive")
(:: main ())
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (main) (println (twice 21)))
PROBE
if cc -c "$work/extern.c" -o "$work/extern.o" \
   && ar rcs "$work/libdce_probe.a" "$work/extern.o" \
   && "$axc" --diagnostic-format=ai build --input "$work/extern.ax" \
        --output "$work/extern" --emit-llvm --link-lib dce_probe --link-search "$work" \
        > "$work/extern.log" 2>&1; then
  extern_out="$("$work/extern" 2>&1)"; extern_rc=$?
  if [[ "$extern_out" == 42 && "$extern_rc" == 0 ]] \
     && grep -q '^; axiom-extern-lib dce_probe$' "$work/extern.ll" \
     && ! grep -q '^define .*@deadLiteral(' "$work/extern.ll"; then
    ok "a live extern call links and runs after the preceding unused string is pruned"
  else
    bad "the extern directive or live call was lost ('$extern_out', exit $extern_rc)"
  fi
else
  bad "the native extern probe would not build"
  sed 's/^/     /' "$work/extern.log" | head -20
fi

cat > "$work/dead-thread.ax" <<'PROBE'
(:: unusedThread (-> Int Int))
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (unusedThread n)
  (__thread_join (__thread_spawn (lambda (word) (+ word 1)) n)))
(:: main Int)
(fn (main) 0)
PROBE
if "$axc" --diagnostic-format=ai build --input "$work/dead-thread.ax" \
     --output "$work/dead-thread" --emit-llvm > "$work/dead-thread.log" 2>&1; then
  "$work/dead-thread"; thread_rc=$?
  if [[ "$thread_rc" == 0 ]] \
     && ! grep -qE '^define .*@(unusedThread|__axiom_par_entry)\(' "$work/dead-thread.ll"; then
    ok "an unused thread body is removed and the late backtracer references no deleted entry"
  else
    bad "the dead thread survived or the program exited $thread_rc"
  fi
else
  bad "the unused thread probe would not build"
  sed 's/^/     /' "$work/dead-thread.log" | head -20
fi

cat > "$work/live-thread.ax" <<'PROBE'
(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  (- (__thread_join (__thread_spawn (lambda (word) (+ word 1)) 41)) 42))
PROBE
if "$axc" --diagnostic-format=ai build --input "$work/live-thread.ax" \
     --output "$work/live-thread" --emit-llvm > "$work/live-thread.log" 2>&1; then
  "$work/live-thread"; thread_rc=$?
  if [[ "$thread_rc" == 0 ]] \
     && grep -q '^define .*@__axiom_par_entry(' "$work/live-thread.ll" \
     && grep -q '%pe = ptrtoint ptr @__axiom_par_entry to i64' "$work/live-thread.ll"; then
    ok "a live thread runs and keeps the backtracer's entry stop"
  else
    bad "the live thread or its backtrace entry stop was lost (exit $thread_rc)"
  fi
else
  bad "the live thread probe would not build"
  sed 's/^/     /' "$work/live-thread.log" | head -20
fi

cat > "$work/name-control.ax" <<'PROBE'
(:: __axiom_par_entry (-> Int Int))
(fn (__axiom_par_entry n) (+ n 1))
(:: main Int)
(fn (main) (- (__axiom_par_entry 41) 42))
PROBE
if "$axc" --diagnostic-format=ai build --input "$work/name-control.ax" \
     --output "$work/name-control" --emit-llvm > "$work/name-control.log" 2>&1; then
  "$work/name-control"; name_rc=$?
  if [[ "$name_rc" == 0 ]] \
     && ! grep -q '%pe = ptrtoint ptr @__axiom_par_entry to i64' "$work/name-control.ll"; then
    ok "a same-named ordinary function does not enable the thread backtrace stop"
  else
    bad "the thread backtrace stop was enabled in a non-threaded module"
  fi
else
  bad "the ordinary-function name control would not build"
  sed 's/^/     /' "$work/name-control.log" | head -20
fi

echo
echo "--- 8. the ablation: with the pass off, §2 and §3 must go red ---"
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
cp -R "$repo_root/core" "$repo_root/stdlib" "$abl/"
seam='(pub fn (pruneDeadDefs cg)
  (if cgStaticlib'
n_seam="$(grep -c -F 'pub fn (pruneDeadDefs cg)' "$abl/core/codegen.ax" || true)"
if [[ "$n_seam" != 1 ]]; then
  bad "core/codegen.ax holds $n_seam copies of the ablation seam; this gate expects exactly 1"
else
  python3 - "$abl/core/codegen.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = "(pub fn (pruneDeadDefs cg)\n  (if cgStaticlib\n"
new = "(pub fn (pruneDeadDefs cg)\n  (if (|| cgStaticlib true)\n"
assert s.count(old) == 1, s.count(old)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  if ! gate_build_tree "$axiom" "$abl" "$AXIOM_STDLIB" "$work/axc-abl" \
       > "$work/abl.build.log" 2>&1; then
    bad "the ablated compiler would not build"
    sed 's/^/     /' "$work/abl.build.log" | head -10
  else
    if "$work/axc-abl" --diagnostic-format=ai build --input "$work/hello.ax" --output "$work/hello-abl" \
         --emit-llvm > "$work/abl.hello.log" 2>&1 \
       && python3 "$work/walk.py" "$work/hello-abl.ll" "$work/hello-abl" > "$work/abl.report" 2>&1; then
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
    else
      bad "the ablated hello world or its independent walk failed before measurement"
      head -20 "$work/abl.hello.log" "$work/abl.report" 2>/dev/null
    fi
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
