#!/usr/bin/env bash
# Degenerate input answers with a diagnostic, not with a signal.
#
# `axiom check` on `(fn (main) ())` died of SIGSEGV: exit 139, no output,
# no diagnostic, nothing on stderr. So did twenty-two other programs, all
# of them the same two characters in a different position, and seven of
# them inside `check` itself - which is the entry point `axiom lsp` calls
# for every keystroke, so an editor buffer holding the parenthesis pair a
# user types before they type anything else killed the language server
# mid-session (measured: returncode -11 after the second `didChange`).
#
# The cause was a sentinel travelling in the success channel. `parseInner`
# answered `(pOk 0 (advance pos))` for `()` - a SUCCESSFUL parse whose
# node handle is 0, which is the handle every producer in `parser.ax` uses
# to mean "there is no node here". Nothing downstream guards a node it was
# told it has, so `checkExpr` and `emitExpr` both dereferenced it.
#
# THE POINT OF THIS GATE IS NOT THE EMPTY FORM. It is that no gate in this
# repository asked the question the empty form answers wrongly. Every other
# suite compares the compiler with a golden, with a second implementation,
# or with itself - and a process that dies by signal produces no output, so
# it satisfies every check written as "the output must not contain X". That
# is exactly how it survived: `check-fmt-selfhost.sh` §5b re-reads every
# formatted output and fails if it carries an AX1xxx or AX2xxx, and
# `tests/fmt/parity/170-empty-tuple.axp` is the file `(fn (f) ())`. The
# formatted output was fed to `check`, `check` died before printing
# anything, the grep found no diagnostic, and the case passed - in CI, for
# as long as that case has existed.
#
# So the assertions here are about the PROCESS, not about its output:
#
#   1. no invocation may be killed by a signal - `check`, `fmt --check`
#      and `symbols`, on every case. This one cannot be blessed, cannot be
#      satisfied by silence, and is the whole reason the file exists.
#   2. a refusal must SAY something: exit 1 with no `E AX....` line is a
#      refusal the user cannot act on, and is how `dieImport` used to read.
#   3. an acceptance must not print an error.
#   4. the pinned exit status per case, so a change to any of them is
#      deliberate rather than noticed later.
#
# The bank is deliberately wider than the bug. Two thirds of these cases
# were already correct when it was written; they are here because this
# project's history is that the next defect of a class arrives in the
# member nobody probed, and a standing bank of small adversarial inputs
# catches what a sweep over real code cannot - every file in `tests/` and
# `self_host/` is written by someone solving a problem, so it contains no
# empty forms at all.
#
# Requires: a compiler. Builds the one under test from `self_host/`, so
# `AXIOM=<any working compiler>` measures the tree, not the binary.

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/.axiom-bin/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "no compiler at $axiom - building one from the committed seed" >&2
  "$repo_root/scripts/bootstrap-from-seed.sh" --install "$repo_root/.axiom-bin" >&2 \
    || { echo "FAIL: could not bootstrap a compiler from bootstrap/" >&2; exit 1; }
fi
export AXIOM_STDLIB="$repo_root/stdlib"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The compiler under test is built from the tree, the way every other
# self-hosting gate does it: `AXIOM` supplies *a* compiler, not *the*
# compiler, so an ablation of `self_host/` is visible here.
axc="$work/axiom"
if ! "$axiom" build --input self_host/main.ax --output "$axc" >"$work/build.log" 2>&1; then
  sed 's/^/    /' "$work/build.log" | head -8 >&2
  echo "FAIL: could not build the compiler under test from self_host/" >&2
  exit 1
fi

cases=0; failed=0; signals=0; accepted=0; refused=0; codes=""
mkdir -p "$work/c"

# deg <name> <expected `check` status>; the source arrives on stdin.
deg() {
  local name="$1" want="$2" out st fmtst symst
  cases=$((cases + 1))
  cat > "$work/c/p.ax"

  # Captured first, then tested. A pipeline's status is its LAST command's,
  # and under `pipefail` `if ! cmd | grep -q` reads backwards the moment
  # `cmd` fails - which for this bank is most of the time.
  out="$( (cd "$work/c" && "$axc" --diagnostic-format=ai check p.ax) 2>&1 )"; st=$?
  ( cd "$work/c" && "$axc" fmt --check p.ax ) >/dev/null 2>&1; fmtst=$?
  ( cd "$work/c" && "$axc" --diagnostic-format=ai symbols p.ax ) >/dev/null 2>&1; symst=$?

  # 1. No signal. 128+n is how the shell reports a killed child, and no
  #    subcommand of this compiler exits above 4 on purpose.
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

# The empty form `()` in every position an expression can appear.
# Twenty of these; every one of them was a SIGSEGV with no diagnostic
# before the parser stopped answering `pOk 0` for it.
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
deg empty-cond-test 1 <<'AXEOF'
(:: main Int)
(fn (main) (cond (() 1) (else 2)))
AXEOF
deg empty-cond-body 1 <<'AXEOF'
(:: main Int)
(fn (main) (cond (true ()) (else 2)))
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

# Other degenerate bracketings, and the declaration forms with an
# empty body. Most of these were already right; they are here so a
# change to one of them has to be deliberate.
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
# Refused, not accepted, since 2026-08-10: a lambda with no parameters
# can never be called - `(f)` and `f` are the same expression - so this
# used to check clean and evaluate to the closure record's ADDRESS. A
# clean AX3008 is the outcome this bank exists to prefer; what it pins
# either way is that the empty parameter list does not take the
# compiler down.
deg empty-lambda-params 1 <<'AXEOF'
(:: main Int)
(fn (main) ((lambda () 1)))
AXEOF
deg empty-match-arms 0 <<'AXEOF'
(:: main Int)
(fn (main) (match 1))
AXEOF
deg empty-cond 0 <<'AXEOF'
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
# `(trait T)`, `(impl T)` and `(type)` are a recognised keyword with a
# shape the parser cannot read, and they used to be ACCEPTED - these three
# expectations were `0`. That was `skipUnknownDecl` swallowing the form
# and answering `TAG_NIL`, a successful parse of nothing, which is the
# same tolerance that made four DOCUMENTED declarations vanish at exit 0
# (self-hosting.md §35). It is a refusal now, so these are `1`: AX2003
# with a span on the keyword, and no signal.
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

# Type position. `()` IS a type - the empty tuple - and stays one.
# `ascribe-unit` is the case that proves the two positions are
# separate: `(:: 1 ())` parses its type with `parseExpr`.
deg sig-unit-type 0 <<'AXEOF'
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

# Nesting, well inside the parser's depth guard (which fires between
# 1,000 and 5,000 - AX2005, measured).
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
deg deep-type-200 0 <<'AXEOF'
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
# Floors. This section reports mostly by silence, and a `deg` that
# stopped being called reports the same silence from zero cases.
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
# A bank that refuses everything with one code is a bank that stopped
# distinguishing its cases. Nine distinct codes were measured when this
# was written; the floor is deliberately below that.
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
# This is the user-visible half, and it is not implied by the section
# above: `check` is a process that exits, so a crash there costs one
# diagnostic; the server is a process that must still be there for the
# next keystroke, so a crash there costs the session. The document below
# holds `()` for exactly one edit - which is what typing a form looks
# like from the server's side - and the server has to answer every
# `didChange` and then its own shutdown.
#
# "Answered the shutdown" is the load-bearing assertion. A server that
# dies quietly after publishing its first diagnostics still produces a
# plausible-looking stdout; only the reply to the last request proves it
# was alive at the end.
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
