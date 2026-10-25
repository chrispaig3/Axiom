#!/usr/bin/env python3
"""Check typed Token ownership, lexer/parser output and editor recovery."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

# Exact lexer/parser/highlighter/recovery output for thirteen source cases.
BASELINE = 'SOURCE token-empty.ax\nTOKEN TK_EOF 0 0\nRECOVERY 0 0\nSOURCE token-valid.ax\nTOKEN TK_LPAREN 0 1\nTOKEN TK_IDENT 1 3\nTOKEN TK_LPAREN 4 5\nTOKEN TK_IDENT 5 6\nTOKEN TK_RPAREN 6 7\nTOKEN TK_INT 8 10\nTOKEN TK_RPAREN 10 11\nTOKEN TK_EOF 11 11\nHL 6 0 1\nHL 1 1 3\nHL 0 3 4\nHL 6 4 5\nHL 2 5 6\nHL 6 6 7\nHL 0 7 8\nHL 3 8 10\nHL 6 10 11\nRECOVERY 1 7\nSOURCE token-unexpected.ax\nTOKEN TK_ERROR 0 1\nTOKEN TK_ERROR_ESC 3 5\nTOKEN TK_EOF 6 6\nE AX1001 token-unexpected.ax:1:1-2 unexpected-char "unexpected character `@`" #"`@` is not valid here" ?"an identifier is letters, digits, `_`, `\'` and `+ - * / % < > = ! & | ^`, and cannot begin with a digit or `\'`; operators are not a separate class - `+` is simply an identifier - and `?`, `~` and `@` are not identifier characters at all"\nHL 7 0 1\nHL 0 1 3\nHL 7 3 5\nHL 0 5 6\nRECOVERY 0 -2\nSOURCE token-escape.ax\nTOKEN TK_ERROR_ESC 1 3\nTOKEN TK_ERROR 5 6\nTOKEN TK_EOF 6 6\nE AX1005 token-escape.ax:1:2-4 invalid-escape-sequence "invalid escape sequence `\\\\q`" #"unrecognized escape sequence" ?"valid escapes are \\\\n \\\\t \\\\r \\\\\\\\ \\\\\\" \\\\\' \\\\0"\nHL 0 0 1\nHL 7 1 3\nHL 0 3 5\nHL 7 5 6\nRECOVERY 0 -2\nSOURCE token-string.ax\nTOKEN TK_ERROR 0 5\nTOKEN TK_EOF 5 5\nE AX1002 token-string.ax:1:1-6 unterminated-string "unterminated string literal" #"string literal starts here but is never closed" ?"add a closing `\\"`, or escape an embedded quote as `\\\\\\"`"\nHL 8 0 5\nRECOVERY 0 -2\nSOURCE token-char.ax\nTOKEN TK_ERROR 0 2\nTOKEN TK_EOF 2 2\nE AX1003 token-char.ax:1:1-3 unterminated-char "unterminated char literal" #"character literal starts here but is never closed" ?"character literals must contain exactly one character, e.g. `\'a\'` or `\'\\\\n\'`"\nHL 8 0 2\nRECOVERY 0 -2\nSOURCE token-number.ax\nTOKEN TK_ERROR 0 5\nTOKEN TK_EOF 5 5\nE AX1004 token-number.ax:1:1-6 invalid-number-literal "invalid number literal `12bad`" #"`12bad` cannot be parsed as Int or Float" ?"check for a value that overflows i64/f64 or a malformed exponent"\nHL 7 0 5\nRECOVERY 0 -2\nSOURCE token-eof.ax\nTOKEN TK_LPAREN 0 1\nTOKEN TK_IDENT 1 3\nTOKEN TK_LPAREN 4 5\nTOKEN TK_IDENT 5 6\nTOKEN TK_RPAREN 6 7\nTOKEN TK_INT 8 9\nTOKEN TK_EOF 9 9\nE AX2002 token-eof.ax:1:10 unexpected-eof "unexpected end of file" #"file ends here while a form is still open" ?"count `(`/`[`/`{` against `)`/`]`/`}` working backward from the end of the file"\nHL 6 0 1\nHL 1 1 3\nHL 0 3 4\nHL 6 4 5\nHL 2 5 6\nHL 6 6 7\nHL 0 7 8\nHL 3 8 9\nRECOVERY 1 -1\nSOURCE token-unmatched.ax\nTOKEN TK_RPAREN 0 1\nTOKEN TK_EOF 1 1\nE AX2001 token-unmatched.ax:1:1-2 unexpected-token "unmatched `)`" #"this `)` closes nothing" ?"remove this `)`, or add the `(` it was meant to close"\nHL 6 0 1\nRECOVERY 0 -2\nSOURCE token-binder.ax\nTOKEN TK_LPAREN 0 1\nTOKEN TK_IDENT 1 3\nTOKEN TK_LPAREN 4 5\nTOKEN TK_IDENT 5 6\nTOKEN TK_RPAREN 6 7\nTOKEN TK_LBRACE 8 9\nTOKEN TK_LPAREN 10 11\nTOKEN TK_IDENT 11 14\nTOKEN TK_IDENT 15 18\nTOKEN TK_IDENT 19 20\nTOKEN TK_INT 21 22\nTOKEN TK_RPAREN 22 23\nTOKEN TK_LPAREN 24 25\nTOKEN TK_IDENT 25 28\nTOKEN TK_IDENT 29 30\nTOKEN TK_INT 31 32\nTOKEN TK_RPAREN 32 33\nTOKEN TK_IDENT 34 35\nTOKEN TK_RBRACE 36 37\nTOKEN TK_RPAREN 37 38\nTOKEN TK_EOF 38 38\nHL 6 0 1\nHL 1 1 3\nHL 0 3 4\nHL 6 4 5\nHL 2 5 6\nHL 6 6 7\nHL 0 7 8\nHL 6 8 9\nHL 0 9 10\nHL 6 10 11\nHL 1 11 14\nHL 0 14 15\nHL 1 15 18\nHL 0 18 19\nHL 2 19 20\nHL 0 20 21\nHL 3 21 22\nHL 6 22 23\nHL 0 23 24\nHL 6 24 25\nHL 1 25 28\nHL 0 28 29\nHL 2 29 30\nHL 0 30 31\nHL 3 31 32\nHL 6 32 33\nHL 0 33 34\nHL 2 34 35\nHL 0 35 36\nHL 6 36 37\nHL 6 37 38\nRECOVERY 1 20\nSOURCE token-member.ax\nTOKEN TK_LPAREN 0 1\nTOKEN TK_IDENT 1 3\nTOKEN TK_LPAREN 4 5\nTOKEN TK_IDENT 5 6\nTOKEN TK_RPAREN 6 7\nTOKEN TK_LPAREN 8 9\nTOKEN TK_IDENT 9 12\nTOKEN TK_COLON 13 14\nTOKEN TK_IDENT 14 19\nTOKEN TK_INT 20 21\nTOKEN TK_RPAREN 21 22\nTOKEN TK_RPAREN 22 23\nTOKEN TK_EOF 23 23\nHL 6 0 1\nHL 1 1 3\nHL 0 3 4\nHL 6 4 5\nHL 2 5 6\nHL 6 6 7\nHL 0 7 8\nHL 6 8 9\nHL 12 9 12\nHL 0 12 13\nHL 6 13 14\nHL 15 14 19\nHL 0 19 20\nHL 3 20 21\nHL 6 21 22\nHL 6 22 23\nRECOVERY 1 12\nSOURCE token-recovery.ax\nTOKEN TK_LPAREN 0 1\nTOKEN TK_IDENT 1 3\nTOKEN TK_LPAREN 4 5\nTOKEN TK_IDENT 5 10\nTOKEN TK_RPAREN 10 11\nTOKEN TK_INT 12 13\nTOKEN TK_RPAREN 13 14\nTOKEN TK_LPAREN 15 16\nTOKEN TK_IDENT 16 18\nTOKEN TK_LPAREN 19 20\nTOKEN TK_IDENT 20 26\nTOKEN TK_RPAREN 26 27\nTOKEN TK_LPAREN 28 29\nTOKEN TK_IDENT 29 31\nTOKEN TK_LPAREN 32 33\nTOKEN TK_IDENT 33 37\nTOKEN TK_RPAREN 37 38\nTOKEN TK_INT 39 40\nTOKEN TK_RPAREN 40 41\nTOKEN TK_EOF 41 41\nE AX2004 token-recovery.ax:3:2-4 removed-construct "`fn` in expression position is refused: an anonymous function is `lambda`" #"an anonymous function had two spellings, `(fn (x) ...)` and `(lambda (x) ...)`; `lambda` is the one, and `fn` only declares" ?"write `lambda` for an anonymous function: `(lambda (x) (+ x 1))`"\nHL 6 0 1\nHL 1 1 3\nHL 0 3 4\nHL 6 4 5\nHL 2 5 10\nHL 6 10 11\nHL 0 11 12\nHL 3 12 13\nHL 6 13 14\nHL 0 14 15\nHL 6 15 16\nHL 1 16 18\nHL 0 18 19\nHL 6 19 20\nHL 2 20 26\nHL 6 26 27\nHL 0 27 28\nHL 6 28 29\nHL 1 29 31\nHL 0 31 32\nHL 6 32 33\nHL 2 33 37\nHL 6 37 38\nHL 0 38 39\nHL 3 39 40\nHL 6 40 41\nRECOVERY 3 -1\nSOURCE token-utf8.ax\nTOKEN TK_CHARLIT 0 4\nTOKEN TK_FLOAT 5 8\nTOKEN TK_IDENT 9 10\nTOKEN TK_DOT 10 11\nTOKEN TK_IDENT 11 12\nTOKEN TK_QUESTION 12 13\nTOKEN TK_EOF 13 13\nE AX2001 token-utf8.ax:1:1-4 unexpected-token "expected (, found `\'é\'`" #"found `\'é\'` here" ?"Axiom expected ( at this position"\nHL 4 0 4\nHL 0 4 5\nHL 3 5 8\nHL 0 8 9\nHL 2 9 10\nHL 6 10 11\nHL 2 11 12\nHL 6 12 13\nRECOVERY 0 -2\n'
EXPECTED = "".join(f"{index} true\n" for index in range(1, 45))


def execute(arguments, env):
    return subprocess.run(arguments, env=env, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/selfhost/compiler-token-owners.axp"
    diagnostics = root / "tests/selfhost/compiler-token-diagnostics.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    originals = {name: (root / "core" / name).read_text()
                 for name in ("core.ax", "parser.ax", "replhl.ax", "lsp.ax")}
    with tempfile.TemporaryDirectory(prefix="axiom-token-owners-") as directory:
        work = Path(directory)

        def native(name, local, level, source=fixture):
            binary = work / name
            built = execute([compiler, "--diagnostic-format=ai", "build", str(source),
                             "--opt", str(level), "--alloc-poison", "-o", str(binary)], local)
            assert built.returncode == 0, (name, built.returncode, built.stdout, built.stderr)
            ran = execute([str(binary)], local)
            assert ran.returncode == 0 and not ran.stderr, (name, ran.returncode, ran.stdout, ran.stderr)
            return ran.stdout

        for level in (0, 2):
            name = "positive-O" + str(level)
            actual = native(name, env, level)
            assert actual == EXPECTED, (name, actual)
            print("ok   " + name, flush=True)
            name = "diagnostics-O" + str(level)
            actual = native(name, env, level, diagnostics)
            assert actual == BASELINE, (name, actual)
            print("ok   " + name + ": exact thirteen-source baseline", flush=True)

        refused = {
            "word-token": ('(:: bad (-> Int String)) (fn (bad token) (tokenLexeme token))', "AX3004"),
            "word-constructor": ('(:: bad Int) (fn (bad) (mkToken TK_IDENT "x" 0))', "AX3004"),
            "word-stream": ('(:: bad (-> Ints (PResult Nodes))) (fn (bad tokens) (parseModule tokens))', "AX3004"),
            "unchecked-lookahead": ('(:: bad (-> Tokens Int String)) (fn (bad tokens i) '
                                    '(tokenLexeme (peekToken tokens i)))', "AX3004"),
            "missing-none": ('(:: bad (-> Tokens Int String)) (fn (bad tokens i) '
                             '(match (peekToken tokens i) ((Some token) (tokenLexeme token))))', "AX3005"),
        }
        for name, (declaration, code) in refused.items():
            source = work / (name + ".ax")
            source.write_text("(import core)\n(import parser)\n(import lexer)\n" + declaration +
                              "\n(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print("ok   " + name + ": " + code, flush=True)

        if args.negative_controls:
            controls = (
                ("present-lookahead-lost", "parser.ax", "(Some (vecGet tokens pos))", "None", fixture),
                ("first-error-lost", "parser.ax", "(while (&& (< i (vecLen tokens)) (isNone found))",
                 "(while (< i (vecLen tokens))", fixture),
                ("lexeme-owner-copied", "core.ax", "(Token :kind kind :lexeme lexeme :span span)",
                 "(Token :kind kind :lexeme (strDup lexeme) :span span)", fixture),
                ("previous-token-lost", "replhl.ax", "(Some (vecGet toks (- i 1)))", "None", diagnostics),
                ("repair-eof-lost", "lsp.ax", '(vecPush out (mkToken TK_EOF "" (mkSpan at at)))',
                 "out", fixture),
            )
            for name, module, old, new, source in controls:
                text = originals[module]
                assert text.count(old) == 1, (name, text.count(old))
                overlay = work / (name + "-core")
                overlay.mkdir()
                for path in (root / "core").iterdir():
                    if path.name == module:
                        (overlay / path.name).write_text(text.replace(old, new))
                    else:
                        (overlay / path.name).symlink_to(path, target_is_directory=path.is_dir())
                actual = native(name, dict(env, AXIOM_PATH=str(overlay)), 0, source)
                if source == fixture:
                    assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 44, (name, actual)
                else:
                    assert actual != BASELINE and "HL " in actual and "RECOVERY " in actual, (name, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   Token ownership: 44 native cases O0/O2 poison, exact diagnostics/recovery, five refusals")


if __name__ == "__main__":
    main()
