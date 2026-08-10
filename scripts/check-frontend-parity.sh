#!/usr/bin/env bash
# ---------------------------------------------------------------------
# The frontend has five consumers and nothing compared them.
#
# `check`, `symbols`, `fmt`, the REPL's `:load` and the language server
# all drive the same `parseModuleWith` / `resolveImports` / `checkModule`
# trio, and every one of them reaches it through its own call site -
# `resolveImports` from five, `checkModule` from six. Three of the four
# defects this gate is seeded with exist because a NEW consumer
# re-derived a rule the frontend already had:
#
#   * trait dispatch rewrote a call head with no scope lookup, where
#     `checkVar` twenty lines away had always asked (010, 020);
#   * an effect operation was registered with arity -1, so saturation
#     had no bound to check (030);
#   * a source type variable matched anything, so a signature's `a` was
#     weaker than its `Int` (040, 050);
#   * `:load` handed the entry declarations to `checkModule` as the
#     whole program, so every import was unresolved and 196 of the 219
#     corpus files `check` accepts were refused (070).
#
# WHAT IT ASSERTS, per program in tests/frontend/:
#
#   1  `check --diagnostic-format=ai` gives the reference set of
#      (severity, code, line) triples.
#   2  `axiom symbols` agrees on the VERDICT - it refuses exactly the
#      programs `check` refuses. (It is a different entry path into the
#      same checker; a tolerance in one and not the other is the shape
#      that hid the vanished `trait` declarations.)
#   3  `:load` in the REPL agrees on the verdict.
#   4  the language server publishes the same (severity, code, line)
#      SET on `didOpen`. Columns are deliberately not compared here -
#      `check-lsp-selfhost.sh` owns the UTF-16 conversion and derives
#      it from the fixture's own bytes, and restating that derivation
#      badly would be a second implementation of the thing it exists to
#      check.
#   5  `fmt` does not change the verdict or the diagnostic set.
#   6  the VALUE. A `; expect N` program must run to exit N. This is
#      the assertion none of the others can make and the one that
#      matters: every defect above passed `check` at exit 0 and differed
#      only in what the program then computed.
#
# WHY A VALUE AND NOT AN EXIT STATUS: a SIGSEGV is a nonzero exit, so an
# exit-status gate cannot separate "correctly refused" from "crashed".
# Every `; refuse` case here is additionally required to have produced
# at least one diagnostic, and every `; expect` case to have exited with
# its own number rather than merely nonzero.
#
# ABLATION: revert any one of the three compiler slices this is seeded
# with and a value case goes wrong while every exit status stays 0 -
# which is precisely the failure the other gates could not see. Run
# with a compiler built from a tree with `traitNameFree` deleted: 010
# answers 333 instead of 42.
#
#   scripts/check-frontend-parity.sh            # all
#   scripts/check-frontend-parity.sh 010        # one, by prefix
# ---------------------------------------------------------------------
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1

axiom="${AXIOM:-$repo_root/.axiom-bin/axiom}"
filter="${1:-}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [[ ! -x "$axiom" ]]; then
  echo "FAIL: no compiler at $axiom"; exit 1
fi

# Build the compiler under test from the CURRENT sources, the way every
# other *-selfhost gate does: $AXIOM is the builder, never the subject.
echo "== building the compiler under test from self_host/ =="
if ! "$axiom" build --input self_host/main.ax -o "$work/axc" > "$work/build.log" 2>&1; then
  echo "FAIL: could not build the compiler under test"; sed 's/^/    /' "$work/build.log" | head -20; exit 1
fi
axc="$work/axc"

# stdlib and self_host have to be reachable from the work directory,
# because `:load` and the server resolve imports relative to the FILE
# and `check` relative to the entry file's directory.
ln -s "$repo_root/stdlib" "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"

pass=0; fail=0; swept=0

# (severity, code, line) triples, sorted, one per line.
triples() { sed 's/\x1b\[[0-9;]*m//g' | awk '$1 ~ /^[EWNH]$/ {split($3,p,":"); print $1, $2, p[2]}' | sort; }

for src in tests/frontend/*.ax; do
  name="$(basename "$src" .ax)"
  [[ -n "$filter" && "$name" != "$filter"* ]] && continue
  swept=$((swept + 1))
  ok=1
  cp "$src" "$work/$name.ax"

  ann="$(head -1 "$src")"
  want_exit=""
  case "$ann" in
    "; expect "*) want_exit="${ann#"; expect "}" ;;
    "; refuse"*)  want_exit="" ;;
    *) echo "FAIL $name (first line is neither \`; expect N\` nor \`; refuse\`)"; fail=$((fail+1)); continue ;;
  esac

  # 1. the reference
  ( cd "$work" && "$axc" check --diagnostic-format=ai "$name.ax" >/dev/null 2>"$work/$name.axdl" )
  check_st=$?
  ref="$(triples < "$work/$name.axdl")"
  nerr="$(grep -c '^E ' "$work/$name.axdl" 2>/dev/null || true)"

  if [[ -n "$want_exit" ]]; then
    if [[ $check_st -ne 0 ]]; then
      echo "FAIL $name (\`; expect $want_exit\` but check refused it)"
      sed 's/^/    /' "$work/$name.axdl" | head -4; ok=0
    fi
  else
    if [[ $check_st -eq 0 ]]; then
      echo "FAIL $name (\`; refuse\` but check accepted it)"; ok=0
    elif [[ "$nerr" -lt 1 ]]; then
      # A refusal with no diagnostic is a crash wearing a refusal's
      # exit status. This is the assertion that a signal cannot satisfy.
      echo "FAIL $name (refused with no error diagnostic - exit $check_st)"; ok=0
    fi
  fi

  # 2. symbols agrees on the verdict
  ( cd "$work" && "$axc" symbols "$name.ax" >/dev/null 2>&1 )
  sym_st=$?
  if [[ $((check_st == 0)) -ne $((sym_st == 0)) ]]; then
    echo "FAIL $name (check exit $check_st, symbols exit $sym_st - the two entry paths disagree on well-formedness)"; ok=0
  fi

  # 3. the REPL's :load agrees on the verdict
  load_out="$( cd "$work" && printf ':load %s\n:quit\n' "$name.ax" | "$axc" repl 2>&1 )"
  if grep -q "OK: Loaded" <<<"$load_out"; then load_ok=0; else load_ok=1; fi
  if [[ $((check_st == 0)) -ne $((load_ok == 0)) ]]; then
    echo "FAIL $name (check exit $check_st, :load $( ((load_ok==0)) && echo accepted || echo refused ))"
    grep -m3 'error\|Type error\|Parse error' <<<"$load_out" | sed 's/^/    /'
    ok=0
  fi

  # 4. the language server publishes the same (severity, code, line) set
  lsp="$(SERVER="$axc" FILE="$work/$name.ax" python3 - <<'PY'
import json, os, subprocess, sys
srv, path = os.environ["SERVER"], os.environ["FILE"]
text = open(path, encoding="utf-8").read()
uri = "file://" + path
def frame(o):
    b = json.dumps(o).encode()
    return b"Content-Length: " + str(len(b)).encode() + b"\r\n\r\n" + b
msgs = b"".join([
    frame({"jsonrpc":"2.0","id":1,"method":"initialize",
           "params":{"processId":None,"rootUri":None,"capabilities":{}}}),
    frame({"jsonrpc":"2.0","method":"initialized","params":{}}),
    frame({"jsonrpc":"2.0","method":"textDocument/didOpen",
           "params":{"textDocument":{"uri":uri,"languageId":"axiom","version":1,"text":text}}}),
    frame({"jsonrpc":"2.0","id":9,"method":"shutdown","params":{}}),
    frame({"jsonrpc":"2.0","method":"exit","params":{}}),
])
p = subprocess.run([srv, "lsp"], input=msgs, capture_output=True,
                   cwd=os.path.dirname(path), timeout=120)
out, sev = p.stdout, {1:"E", 2:"W", 3:"N", 4:"H"}
rows, i = [], 0
while True:
    j = out.find(b"Content-Length:", i)
    if j < 0: break
    k = out.find(b"\r\n\r\n", j)
    n = int(out[j+15:k].strip())
    body = out[k+4:k+4+n]; i = k + 4 + n
    try: m = json.loads(body)
    except Exception: continue
    if m.get("method") != "textDocument/publishDiagnostics": continue
    for d in m["params"].get("diagnostics", []):
        rows.append(f'{sev.get(d.get("severity",1),"E")} {d.get("code","?")} '
                    f'{d["range"]["start"]["line"] + 1}')
print("\n".join(sorted(rows)))
PY
)"
  if [[ "$lsp" != "$ref" ]]; then
    echo "FAIL $name (server and check disagree on the diagnostic set)"
    diff <(echo "$ref") <(echo "$lsp") | sed 's/^/    /' | head -8
    ok=0
  fi

  # 5. fmt preserves the verdict and the set. `fmt` rewrites its
  # argument IN PLACE and a refusal leaves it untouched, so the copy is
  # what gets formatted and the original stays the reference.
  cp "$work/$name.ax" "$work/$name.fmt.ax"
  if ( cd "$work" && "$axc" fmt "$name.fmt.ax" >/dev/null 2>&1 ); then
    ( cd "$work" && "$axc" check --diagnostic-format=ai "$name.fmt.ax" >/dev/null 2>"$work/$name.fmt.axdl" )
    fmt_st=$?
    # CODES, not lines. Reflowing is the formatter's job, so a
    # diagnostic legitimately moves; what may not change is which
    # diagnostics there are. `check-fmt.sh` makes the same comparison
    # corpus-wide and for the same reason.
    fmt_codes="$(triples < "$work/$name.fmt.axdl" | awk '{print $1, $2}' | sort)"
    ref_codes="$(echo "$ref" | awk 'NF {print $1, $2}' | sort)"
    if [[ $((check_st == 0)) -ne $((fmt_st == 0)) ]]; then
      echo "FAIL $name (check exit $check_st, formatted copy exit $fmt_st)"; ok=0
    elif [[ "$fmt_codes" != "$ref_codes" ]]; then
      echo "FAIL $name (formatting changed the diagnostic set)"
      diff <(echo "$ref_codes") <(echo "$fmt_codes") | sed 's/^/    /' | head -6
      ok=0
    fi
  else
    echo "FAIL $name (fmt refused the file)"; ok=0
  fi

  # 6. the VALUE
  if [[ -n "$want_exit" ]]; then
    ( cd "$work" && "$axc" run "$name.ax" >/dev/null 2>"$work/$name.run.err" )
    run_st=$?
    if [[ "$run_st" -ne "$want_exit" ]]; then
      echo "FAIL $name (ran to exit $run_st, expected $want_exit)"
      [[ $run_st -gt 128 ]] && echo "    killed by signal $((run_st - 128))"
      sed 's/^/    /' "$work/$name.run.err" | head -3
      ok=0
    fi
  fi

  if [[ $ok -eq 1 ]]; then pass=$((pass+1)); else fail=$((fail+1)); fi
done

echo
echo "frontend parity: $swept program(s) through check, symbols, :load, lsp and fmt; $pass passed, $fail failed"

# A sweep that reads fewer files than it should reports the silence it
# was looking for. The floor is the only thing separating that from
# success.
if [[ -z "$filter" && $swept -lt 7 ]]; then
  echo "FAIL: swept $swept programs, floor is 7 - the bank shrank or the glob stopped matching"
  exit 1
fi

[[ $fail -eq 0 ]] || exit 1
