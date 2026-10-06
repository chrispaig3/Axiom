#!/usr/bin/env bash
# Check that degenerate input gets a diagnostic and never kills the
# compiler with a signal.
#
# A process killed by a signal prints nothing, so it passes every check
# written as "the output must not contain X". Suites that compare output
# with a golden, a second implementation or the compiler itself cannot
# see a crash. This gate asserts on the process instead:
#
#   1. No run of `check`, `fmt --check` or `symbols` is killed by a
#      signal, on any case. This cannot be blessed or satisfied by
#      silence.
#   2. A refusal says why: exit 1 needs an `E AX....` line the user can
#      act on.
#   3. An acceptance prints no error.
#   4. Each case's `check` status is pinned, so changing one is a visible
#      decision.
#
# The parser must never report success with node handle 0, the value
# every producer in `parser.ax` uses for "no node here". Nothing
# downstream guards a node it was told it has, so `checkExpr` and
# `emitExpr` would dereference it.
#
# `axiom lsp` runs `check` on every keystroke, and `()` is what a buffer
# holds before the user types anything else. A crash there ends the
# editing session, so the last section drives the language server too.
#
# The bank is wider than any one defect. Code in `tests/` and
# `self_host/` is written to solve problems and holds no empty forms, so
# a sweep over it cannot find what these small adversarial inputs do.
#
# Requires: a compiler. Builds the one under test from `self_host/`, so
# `AXIOM=<any working compiler>` tests the tree, not the binary.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

# Build the compiler under test from the tree, so an ablation of
# `self_host/` shows here. `AXIOM` only supplies a compiler to build with.
gate_build_axc axc "$work/axiom"

cases=0; failed=0; signals=0; accepted=0; refused=0; codes=""
mkdir -p "$work/c"

# deg <name> <expected `check` status>; the source arrives on stdin.
deg() {
  local name="$1" want="$2" out st fmtst symst
  cases=$((cases + 1))
  cat > "$work/c/p.ax"

  # Capture first, then test. Under `pipefail`, `if ! cmd | grep -q`
  # reads backwards whenever `cmd` fails, which in this bank is most of
  # the time.
  out="$( (cd "$work/c" && "$axc" --diagnostic-format=ai check p.ax) 2>&1 )"; st=$?
  ( cd "$work/c" && "$axc" fmt --check p.ax ) >/dev/null 2>&1; fmtst=$?
  ( cd "$work/c" && "$axc" --diagnostic-format=ai symbols p.ax ) >/dev/null 2>&1; symst=$?

  # 1. No signal. The shell reports a killed child as 128+n, and no
  #    compiler subcommand chooses an exit status above 4.
  local sig=0
  for pair in "check:$st" "fmt:$fmtst" "symbols:$symst"; do
    if [[ ${pair#*:} -ge 128 ]]; then
      echo "FAIL $name: ${pair%%:*} was killed by a signal (exit ${pair#*:})"
      sig=1
    fi
  done
  if [[ $sig -eq 1 ]]; then
    signals=$((signals + 1)); failed=$((failed + 1)); return
  fi

  # 4. The pinned status.
  if [[ $st -ne $want ]]; then
    echo "FAIL $name: check exited $st, want $want"
    head -1 <<<"$out" | sed 's/^/     /'
    failed=$((failed + 1)); return
  fi

  # 2 and 3. A refusal says why; an acceptance says nothing.
  if [[ $st -eq 1 ]]; then
    refused=$((refused + 1))
    if ! grep -qE '^E AX[0-9]{4} ' <<<"$out"; then
      echo "FAIL $name: refused with no diagnostic to act on"
      head -2 <<<"$out" | sed 's/^/     /'
      failed=$((failed + 1)); return
    fi
    codes="$codes$(grep -oE '^E AX[0-9]{4}' <<<"$out" | head -1 | cut -d' ' -f2)"$'\n'
  elif [[ $st -eq 0 ]]; then
    accepted=$((accepted + 1))
    if grep -qE '^E ' <<<"$out"; then
      echo "FAIL $name: accepted, and printed an error anyway"
      failed=$((failed + 1)); return
    fi
  fi
  echo "ok   $name (check $st)"
}

echo "== degenerate forms: none may die by signal =="

# The empty form `()` in every position an expression can appear, each
# refused with a diagnostic, and a few `if` and `cond` shapes beside them.
deg empty-body 1 <<'AXEOF'
(:: main Int)
(fn (main) ())
AXEOF
deg empty-arg 1 <<'AXEOF'
(:: main Int)
(fn (main) (+ 1 ()))
AXEOF
deg empty-let-val 1 <<'AXEOF'
(:: main Int)
(fn (main) (let ((x ())) 0))
AXEOF
deg empty-let-body 1 <<'AXEOF'
(:: main Int)
(fn (main) (let ((x 1)) ()))
AXEOF
deg empty-if-test 1 <<'AXEOF'
(:: main Int)
(fn (main) (if () 1 2))
AXEOF
deg empty-if-then 1 <<'AXEOF'
(:: main Int)
(fn (main) (if true () 2))
AXEOF
deg empty-block 1 <<'AXEOF'
(:: main Int)
(fn (main) { () 0 })
AXEOF
deg empty-block-tail 1 <<'AXEOF'
(:: main Int)
(fn (main) { 0 () })
AXEOF
deg empty-nested 1 <<'AXEOF'
(:: main Int)
(fn (main) (()))
AXEOF
deg empty-head 1 <<'AXEOF'
(:: main Int)
(fn (main) (() 1))
AXEOF
deg empty-match-scrut 1 <<'AXEOF'
(:: main Int)
(fn (main) (match () ((_) 0)))
AXEOF
deg empty-match-arm 1 <<'AXEOF'
(:: main Int)
(fn (main) (match 1 ((_) ())))
AXEOF
deg empty-while-test 1 <<'AXEOF'
(:: main Int)
(fn (main) (while () 0))
AXEOF
deg empty-while-body 1 <<'AXEOF'
(:: main Int)
(fn (main) (while false ()))
AXEOF
deg empty-set-val 1 <<'AXEOF'
(:: main Int)
(fn (main) (let mut ((x 1)) { (set x ()) x }))
AXEOF
deg empty-ascribe 1 <<'AXEOF'
(:: main Int)
(fn (main) (:: () Int))
AXEOF
deg even-if-operands 1 <<'AXEOF'
(:: main Int)
(fn (main) (if true 1 false 2))
AXEOF
deg variadic-if-ok 0 <<'AXEOF'
(:: main Int)
(fn (main) (if true 1 false 2 3))
AXEOF
deg cond-removed 1 <<'AXEOF'
(:: main Int)
(fn (main) (cond (else 2)))
AXEOF
deg empty-lambda-body 1 <<'AXEOF'
(:: main Int)
(fn (main) ((lambda (x) ()) 1))
AXEOF
deg empty-deep 1 <<'AXEOF'
(:: main Int)
(fn (main) (+ 1 (+ 2 (+ 3 ()))))
AXEOF
deg empty-toplevel 1 <<'AXEOF'
()
(:: main Int)
(fn (main) 0)
AXEOF
deg empty-toplevel-twice 1 <<'AXEOF'
()
()
(:: main Int)
(fn (main) 0)
AXEOF
deg empty-fn-body-decl 1 <<'AXEOF'
(:: main Int)
(fn (main) 0)
(:: g Int)
(fn (g) ())
AXEOF
deg empty-in-macro-tpl 1 <<'AXEOF'
(macro (m x) ())
(:: main Int)
(fn (main) (m 1))
AXEOF
deg empty-macro-arg 1 <<'AXEOF'
(macro (m x) x)
(:: main Int)
(fn (main) (m ()))
AXEOF

# Other degenerate bracketings, and declaration forms with an empty
# body, pinned so a change to any of them is a visible decision.
deg empty-brace 1 <<'AXEOF'
(:: main Int)
(fn (main) {})
AXEOF
deg empty-brackets 1 <<'AXEOF'
(:: main Int)
(fn (main) [])
AXEOF
deg bracket-one 1 <<'AXEOF'
(:: main Int)
(fn (main) [1])
AXEOF
deg empty-struct-decl 0 <<'AXEOF'
(struct S)
(:: main Int)
(fn (main) 0)
AXEOF
deg empty-data-decl 0 <<'AXEOF'
(data D)
(:: main Int)
(fn (main) 0)
AXEOF
deg empty-let-binds 0 <<'AXEOF'
(:: main Int)
(fn (main) (let () 0))
AXEOF
# A lambda with no parameters can never be called, since `(f)` and `f`
# are the same expression, so it is refused with AX3068. The case pins
# that the empty parameter list does not take the compiler down.
deg empty-lambda-params 1 <<'AXEOF'
(:: main Int)
(fn (main) ((lambda () 1)))
AXEOF
deg empty-match-arms 0 <<'AXEOF'
(:: main Int)
(fn (main) (match 1))
AXEOF
deg bare-cond-removed 1 <<'AXEOF'
(:: main Int)
(fn (main) (cond))
AXEOF
deg empty-block-only 1 <<'AXEOF'
(:: main Int)
(fn (main) { })
AXEOF
deg empty-handle 1 <<'AXEOF'
(:: main Int)
(fn (main) (handle 1))
AXEOF
deg empty-import 1 <<'AXEOF'
(import)
(:: main Int)
(fn (main) 0)
AXEOF
deg import-empty-names 0 <<'AXEOF'
(import IO ())
(:: main Int)
(fn (main) 0)
AXEOF
# `(trait T)`, `(impl T)` and `(type)` are a known keyword in a shape the
# parser cannot read. Each is refused with AX2003, spanning the keyword.
# `skipUnknownDecl` must not answer `TAG_NIL` for them: a successful
# parse of nothing lets a declaration vanish at exit 0.
deg empty-trait 1 <<'AXEOF'
(trait T)
(:: main Int)
(fn (main) 0)
AXEOF
deg empty-impl 1 <<'AXEOF'
(impl T)
(:: main Int)
(fn (main) 0)
AXEOF
deg empty-macro-params 0 <<'AXEOF'
(macro (m) 1)
(:: main Int)
(fn (main) (m))
AXEOF
deg empty-macro-name 1 <<'AXEOF'
(macro () 1)
(:: main Int)
(fn (main) 0)
AXEOF
deg empty-fn-head 1 <<'AXEOF'
(fn () 0)
(:: main Int)
(fn (main) 0)
AXEOF
deg empty-sig 1 <<'AXEOF'
(:: )
(:: main Int)
(fn (main) 0)
AXEOF
deg empty-type-decl 1 <<'AXEOF'
(type)
(:: main Int)
(fn (main) 0)
AXEOF

# Type position. `()` is a type, the empty tuple. `ascribe-unit` shows
# the two positions are separate: `(:: 1 ())` parses its type with
# `parseExpr`.
# `sig-unit-type` is AX3004: the body answers `Int` under a declared
# `()`. No body can satisfy that signature, because `()` in expression
# position is AX2001. The case pins that the compiler answers with a
# diagnostic.
deg sig-unit-type 1 <<'AXEOF'
(:: main ())
(fn (main) 0)
AXEOF
deg sig-arrow-empty 1 <<'AXEOF'
(:: main (-> ))
(fn (main) 0)
AXEOF
deg sig-ptr-empty 1 <<'AXEOF'
(:: main (* ))
(fn (main) 0)
AXEOF
deg sig-list-empty 1 <<'AXEOF'
(:: main [])
(fn (main) 0)
AXEOF
deg sig-nested-unit 0 <<'AXEOF'
(:: f (-> () Int))
(fn (f x) 0)
(:: main Int)
(fn (main) 0)
AXEOF
deg ascribe-unit 1 <<'AXEOF'
(:: main Int)
(fn (main) (:: 1 ()))
AXEOF

# Nesting, well inside the parser's depth guard (AX2005), which fires
# somewhere between 1,000 and 5,000 levels.
deg deep-parens-200 0 <<'AXEOF'
(:: main Int)
(fn (main) (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 0))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
AXEOF
deg deep-brace-200 0 <<'AXEOF'
(:: main Int)
(fn (main) { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { { 0 } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } })
AXEOF
deg deep-list-200 1 <<'AXEOF'
(:: main Int)
(fn (main) [[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[1]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]])
AXEOF
# The body is `0` and the declared result is 200 levels deep, so this is
# AX3004. The case is about depth: 200 nested constructors must not
# exhaust the parser's or the checker's stack. The type error shows the
# checker walked the whole type to compare it.
deg deep-type-200 1 <<'AXEOF'
(:: main (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* (* Int)))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
(fn (main) 0)
AXEOF

# Truncated and unterminated input.
deg unterminated-paren 1 <<'AXEOF'
(:: main Int)
(fn (main) (+ 1 2)
AXEOF
deg unterminated-brace 1 <<'AXEOF'
(:: main Int)
(fn (main) { 1 
AXEOF
deg unterminated-string 1 <<'AXEOF'
(:: main Int)
(fn (main) "abc
AXEOF
deg unterminated-char 1 <<'AXEOF'
(:: main Int)
(fn (main) 'a
AXEOF
deg unterminated-blockcomment 0 <<'AXEOF'
#| unterminated
(:: main Int)
(fn (main) 0)
AXEOF
deg stray-rparen 1 <<'AXEOF'
(:: main Int)
(fn (main) 0))
AXEOF
deg stray-rbrace 1 <<'AXEOF'
(:: main Int)
(fn (main) 0)}
AXEOF
deg stray-rbracket 1 <<'AXEOF'
(:: main Int)
(fn (main) 0)]
AXEOF
deg only-rparen 1 <<'AXEOF'
)
AXEOF
deg empty-file 0 <<'AXEOF'
AXEOF
deg whitespace-only 0 <<'AXEOF'
   
	
AXEOF
deg comment-only 0 <<'AXEOF'
; nothing here
AXEOF

# Literal boundaries.
deg int-max 0 <<'AXEOF'
(:: main Int)
(fn (main) 9223372036854775807)
AXEOF
deg int-overflow 1 <<'AXEOF'
(:: main Int)
(fn (main) 9223372036854775808)
AXEOF
deg int-huge 1 <<'AXEOF'
(:: main Int)
(fn (main) 9999999999999999999999999999999999999999)
AXEOF
deg neg-int-min 1 <<'AXEOF'
(:: main Int)
(fn (main) (- 0 9223372036854775808))
AXEOF
deg float-huge 1 <<'AXEOF'
(:: main Int)
(fn (main) 1e400)
AXEOF
deg float-nan-ish 1 <<'AXEOF'
(:: main Int)
(fn (main) 0.0e)
AXEOF
deg char-empty 1 <<'AXEOF'
(:: main Int)
(fn (main) '')
AXEOF
deg char-multi 1 <<'AXEOF'
(:: main Int)
(fn (main) 'ab')
AXEOF
deg string-escape-bad 1 <<'AXEOF'
(:: main Int)
(fn (main) "\q")
AXEOF
deg ident-dot 1 <<'AXEOF'
(:: main Int)
(fn (main) (let ((tmp.1 5)) tmp.1))
AXEOF
deg ident-only-colons 1 <<'AXEOF'
(:: main Int)
(fn (main) ::)
AXEOF
deg qualified-nothing 1 <<'AXEOF'
(:: main Int)
(fn (main) Mod::)
AXEOF
deg qualified-empty-mod 1 <<'AXEOF'
(:: main Int)
(fn (main) ::name)
AXEOF

# Patterns. `parseArmPattern` falls back to `parseExpr`, so an empty
# pattern is the same defect reached through another door.
deg match-empty-pat 1 <<'AXEOF'
(:: main Int)
(fn (main) (match 1 (() 0)))
AXEOF
deg match-nested-empty 1 <<'AXEOF'
(:: main Int)
(fn (main) (match 1 ((Just ()) 0)))
AXEOF
deg match-dup-binder 0 <<'AXEOF'
(:: main Int)
(fn (main) (match 1 ((x) 0)))
AXEOF
deg match-literal-pat 0 <<'AXEOF'
(:: main Int)
(fn (main) (match 1 ((1) 0) ((_) 1)))
AXEOF

# Struct construction and field access.
deg field-of-empty 1 <<'AXEOF'
(:: main Int)
(fn (main) (. () x))
AXEOF
deg struct-empty-args 1 <<'AXEOF'
(struct P (x : Int))
(:: main Int)
(fn (main) (. (struct P) x))
AXEOF
deg field-missing 1 <<'AXEOF'
(struct P (x : Int))
(:: main Int)
(fn (main) (. (struct P (x 1)) y))
AXEOF

# A NUL byte in the middle of a source file cannot survive a heredoc, so
# this one case is written by printf. The lexer's fallthrough decides it.
printf '(:: main Int)\n(fn (main) 0)\n\000' > "$work/nul.ax"
deg nul-byte 1 < "$work/nul.ax"

# ---------------------------------------------------------------
# Floors. Most cases pass silently, and a `deg` that stopped being
# called would be just as silent, so check the counts.
# ---------------------------------------------------------------
echo "     $cases cases: $accepted accepted, $refused refused, $signals killed by a signal"
if [[ $cases -lt 80 ]]; then
  echo "FAIL: the bank has $cases cases; the floor is 80"
  failed=$((failed + 1))
fi
if [[ $accepted -eq 0 || $refused -eq 0 ]]; then
  echo "FAIL: the bank produced one outcome only ($accepted accepted, $refused refused)"
  failed=$((failed + 1))
fi
# A bank that refuses everything with one code has stopped telling its
# cases apart. The floor sits below the number of codes the bank draws,
# so one case moving to another code does not fail the gate.
distinct="$(sort -u <<<"$codes" | grep -c 'AX' || true)"
if [[ $distinct -lt 6 ]]; then
  echo "FAIL: the refusals name $distinct distinct diagnostic codes; the floor is 6"
  failed=$((failed + 1))
else
  echo "ok   the refusals name $distinct distinct diagnostic codes"
fi

# ---------------------------------------------------------------
# The language server survives the same input.
#
# A crash in `check` costs one diagnostic. A crash in the server costs
# the editing session. The document holds `()` for one edit, which is
# how typing a form looks to the server, and the server must answer
# every `didChange` and then its own shutdown.
#
# The shutdown reply is the assertion that matters. A server that dies
# after its first diagnostics still prints plausible stdout; only the
# reply to the last request shows it was alive at the end.
# ---------------------------------------------------------------
echo "== the language server survives an unfinished form =="
lsp_out="$(python3 - "$axc" "$work" <<'PY' 2>&1
import json, os, subprocess, sys
axc, work = sys.argv[1], sys.argv[2]
d = os.path.join(work, "lsp"); os.makedirs(d, exist_ok=True)
uri = "file://" + os.path.join(d, "doc.ax")

def frame(o):
    b = json.dumps(o).encode()
    return b"Content-Length: " + str(len(b)).encode() + b"\r\n\r\n" + b

# Version 2 is the one that matters: a document with an empty form in it.
texts = ["(:: main Int)\n(fn (main) 0)\n",
         "(:: main Int)\n(fn (main) (let ((x ())) 0))\n",
         "(:: main Int)\n(fn (main) ())\n",
         "(:: main Int)\n(fn (main) {})\n",
         "(:: main Int)\n(fn (main) 1)\n"]
msgs = [{"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"processId": None, "rootUri": None, "capabilities": {}}},
        {"jsonrpc": "2.0", "method": "initialized", "params": {}},
        {"jsonrpc": "2.0", "method": "textDocument/didOpen",
         "params": {"textDocument": {"uri": uri, "languageId": "axiom",
                                     "version": 1, "text": texts[0]}}}]
for i, t in enumerate(texts[1:], start=2):
    msgs.append({"jsonrpc": "2.0", "method": "textDocument/didChange",
                 "params": {"textDocument": {"uri": uri, "version": i},
                            "contentChanges": [{"text": t}]}})
msgs += [{"jsonrpc": "2.0", "id": 2, "method": "shutdown", "params": None},
         {"jsonrpc": "2.0", "method": "exit", "params": None}]

p = subprocess.run([axc, "lsp"], input=b"".join(frame(m) for m in msgs),
                   capture_output=True, timeout=120, cwd=d)
if p.returncode < 0:
    print(f"FAIL lsp: the server was killed by signal {-p.returncode}")
    sys.exit(1)
if p.returncode != 0:
    print(f"FAIL lsp: the server exited {p.returncode}")
    sys.exit(1)
body = p.stdout.decode("utf-8", "replace")
published = body.count('"method":"textDocument/publishDiagnostics"')
if published != len(texts):
    print(f"FAIL lsp: {published} publishDiagnostics for {len(texts)} document versions")
    sys.exit(1)
if '"id":2' not in body.replace(" ", ""):
    print("FAIL lsp: the server never answered the shutdown request")
    sys.exit(1)
print(f"ok   the server answered {published} versions and its shutdown")
PY
)"; lsp_st=$?
echo "$lsp_out" | sed 's/^/     /'
if [[ $lsp_st -ne 0 ]]; then failed=$((failed + 1)); fi

# ---------------------------------------------------------------
echo
if [[ $failed -eq 0 ]]; then
  echo "PASS: $cases degenerate inputs, every one answered by a diagnostic or an acceptance"
  exit 0
fi
echo "FAIL: $failed of $cases checks failed"
exit 1
