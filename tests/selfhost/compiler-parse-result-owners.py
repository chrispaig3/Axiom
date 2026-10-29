#!/usr/bin/env python3
"""Check owning generic parse results, exact failures and REPL retries."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

# Thirteen lexer/parser/editor inputs and three REPL failures. Token
# kinds print as global constructor tags, so a new constructor in an
# imported module renumbers every TOKEN line at once.
BASELINE = 'SOURCE token-empty.ax\nTOKEN 16 0 0\nRECOVERY 0 0\nSOURCE token-valid.ax\nTOKEN 4 0 1\nTOKEN 6 1 3\nTOKEN 4 4 5\nTOKEN 6 5 6\nTOKEN 5 6 7\nTOKEN 7 8 10\nTOKEN 5 10 11\nTOKEN 16 11 11\nHL 6 0 1\nHL 1 1 3\nHL 0 3 4\nHL 6 4 5\nHL 2 5 6\nHL 6 6 7\nHL 0 7 8\nHL 3 8 10\nHL 6 10 11\nRECOVERY 1 7\nSOURCE token-unexpected.ax\nTOKEN 17 0 1\nTOKEN 23 3 5\nTOKEN 16 6 6\nE AX1001 token-unexpected.ax:1:1-2 unexpected-char "unexpected character `@`" #"`@` is not valid here" ?"an identifier is letters, digits, `_`, `\'` and `+ - * / % < > = ! & | ^`, and cannot begin with a digit or `\'`; operators are not a separate class - `+` is simply an identifier - and `?`, `~` and `@` are not identifier characters at all"\nHL 7 0 1\nHL 0 1 3\nHL 7 3 5\nHL 0 5 6\nRECOVERY 0 -2\nSOURCE token-escape.ax\nTOKEN 23 1 3\nTOKEN 17 5 6\nTOKEN 16 6 6\nE AX1005 token-escape.ax:1:2-4 invalid-escape-sequence "invalid escape sequence `\\\\q`" #"unrecognized escape sequence" ?"valid escapes are \\\\n \\\\t \\\\r \\\\\\\\ \\\\\\" \\\\\' \\\\0"\nHL 0 0 1\nHL 7 1 3\nHL 0 3 5\nHL 7 5 6\nRECOVERY 0 -2\nSOURCE token-string.ax\nTOKEN 17 0 5\nTOKEN 16 5 5\nE AX1002 token-string.ax:1:1-6 unterminated-string "unterminated string literal" #"string literal starts here but is never closed" ?"add a closing `\\"`, or escape an embedded quote as `\\\\\\"`"\nHL 8 0 5\nRECOVERY 0 -2\nSOURCE token-char.ax\nTOKEN 17 0 2\nTOKEN 16 2 2\nE AX1003 token-char.ax:1:1-3 unterminated-char "unterminated char literal" #"character literal starts here but is never closed" ?"character literals must contain exactly one character, e.g. `\'a\'` or `\'\\\\n\'`"\nHL 8 0 2\nRECOVERY 0 -2\nSOURCE token-number.ax\nTOKEN 17 0 5\nTOKEN 16 5 5\nE AX1004 token-number.ax:1:1-6 invalid-number-literal "invalid number literal `12bad`" #"`12bad` cannot be parsed as Int or Float" ?"check for a value that overflows i64/f64 or a malformed exponent"\nHL 7 0 5\nRECOVERY 0 -2\nSOURCE token-eof.ax\nTOKEN 4 0 1\nTOKEN 6 1 3\nTOKEN 4 4 5\nTOKEN 6 5 6\nTOKEN 5 6 7\nTOKEN 7 8 9\nTOKEN 16 9 9\nE AX2002 token-eof.ax:1:10 unexpected-eof "unexpected end of file" #"file ends here while a form is still open" ?"count `(`/`[`/`{` against `)`/`]`/`}` working backward from the end of the file"\nHL 6 0 1\nHL 1 1 3\nHL 0 3 4\nHL 6 4 5\nHL 2 5 6\nHL 6 6 7\nHL 0 7 8\nHL 3 8 9\nRECOVERY 1 -1\nSOURCE token-unmatched.ax\nTOKEN 5 0 1\nTOKEN 16 1 1\nE AX2001 token-unmatched.ax:1:1-2 unexpected-token "unmatched `)`" #"this `)` closes nothing" ?"remove this `)`, or add the `(` it was meant to close"\nHL 6 0 1\nRECOVERY 0 -2\nSOURCE token-binder.ax\nTOKEN 4 0 1\nTOKEN 6 1 3\nTOKEN 4 4 5\nTOKEN 6 5 6\nTOKEN 5 6 7\nTOKEN 14 8 9\nTOKEN 4 10 11\nTOKEN 6 11 14\nTOKEN 6 15 18\nTOKEN 6 19 20\nTOKEN 7 21 22\nTOKEN 5 22 23\nTOKEN 4 24 25\nTOKEN 6 25 28\nTOKEN 6 29 30\nTOKEN 7 31 32\nTOKEN 5 32 33\nTOKEN 6 34 35\nTOKEN 15 36 37\nTOKEN 5 37 38\nTOKEN 16 38 38\nHL 6 0 1\nHL 1 1 3\nHL 0 3 4\nHL 6 4 5\nHL 2 5 6\nHL 6 6 7\nHL 0 7 8\nHL 6 8 9\nHL 0 9 10\nHL 6 10 11\nHL 1 11 14\nHL 0 14 15\nHL 1 15 18\nHL 0 18 19\nHL 2 19 20\nHL 0 20 21\nHL 3 21 22\nHL 6 22 23\nHL 0 23 24\nHL 6 24 25\nHL 1 25 28\nHL 0 28 29\nHL 2 29 30\nHL 0 30 31\nHL 3 31 32\nHL 6 32 33\nHL 0 33 34\nHL 2 34 35\nHL 0 35 36\nHL 6 36 37\nHL 6 37 38\nRECOVERY 1 20\nSOURCE token-member.ax\nTOKEN 4 0 1\nTOKEN 6 1 3\nTOKEN 4 4 5\nTOKEN 6 5 6\nTOKEN 5 6 7\nTOKEN 4 8 9\nTOKEN 6 9 12\nTOKEN 9 13 14\nTOKEN 6 14 19\nTOKEN 7 20 21\nTOKEN 5 21 22\nTOKEN 5 22 23\nTOKEN 16 23 23\nHL 6 0 1\nHL 1 1 3\nHL 0 3 4\nHL 6 4 5\nHL 2 5 6\nHL 6 6 7\nHL 0 7 8\nHL 6 8 9\nHL 12 9 12\nHL 0 12 13\nHL 6 13 14\nHL 15 14 19\nHL 0 19 20\nHL 3 20 21\nHL 6 21 22\nHL 6 22 23\nRECOVERY 1 12\nSOURCE token-recovery.ax\nTOKEN 4 0 1\nTOKEN 6 1 3\nTOKEN 4 4 5\nTOKEN 6 5 10\nTOKEN 5 10 11\nTOKEN 7 12 13\nTOKEN 5 13 14\nTOKEN 4 15 16\nTOKEN 6 16 18\nTOKEN 4 19 20\nTOKEN 6 20 26\nTOKEN 5 26 27\nTOKEN 4 28 29\nTOKEN 6 29 31\nTOKEN 4 32 33\nTOKEN 6 33 37\nTOKEN 5 37 38\nTOKEN 7 39 40\nTOKEN 5 40 41\nTOKEN 16 41 41\nE AX2004 token-recovery.ax:3:2-4 removed-construct "`fn` in expression position is refused: an anonymous function is `lambda`" #"an anonymous function had two spellings, `(fn (x) ...)` and `(lambda (x) ...)`; `lambda` is the one, and `fn` only declares" ?"write `lambda` for an anonymous function: `(lambda (x) (+ x 1))`"\nHL 6 0 1\nHL 1 1 3\nHL 0 3 4\nHL 6 4 5\nHL 2 5 10\nHL 6 10 11\nHL 0 11 12\nHL 3 12 13\nHL 6 13 14\nHL 0 14 15\nHL 6 15 16\nHL 1 16 18\nHL 0 18 19\nHL 6 19 20\nHL 2 20 26\nHL 6 26 27\nHL 0 27 28\nHL 6 28 29\nHL 1 29 31\nHL 0 31 32\nHL 6 32 33\nHL 2 33 37\nHL 6 37 38\nHL 0 38 39\nHL 3 39 40\nHL 6 40 41\nRECOVERY 3 -1\nSOURCE token-utf8.ax\nTOKEN 19 0 4\nTOKEN 18 5 8\nTOKEN 6 9 10\nTOKEN 12 10 11\nTOKEN 6 11 12\nTOKEN 24 12 13\nTOKEN 16 13 13\nE AX2001 token-utf8.ax:1:1-4 unexpected-token "expected (, found `\'é\'`" #"found `\'é\'` here" ?"Axiom expected ( at this position"\nHL 4 0 4\nHL 0 4 5\nHL 3 5 8\nHL 0 8 9\nHL 2 9 10\nHL 6 10 11\nHL 2 11 12\nHL 6 12 13\nRECOVERY 0 -2\nREPL_FAILURES\nParse error: the line does not parse as an expression\nError: parsing failed\nError: undefined variable `unknown`\n'
EXPECTED = "".join(f"{index} true\n" for index in range(1, 36))


def execute(arguments, env):
    return subprocess.run(arguments, env=env, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--negative-controls", action="store_true")
    parser.add_argument("--skip-positive", action="store_true", help="Run only refusal and mutation checks.")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/selfhost/compiler-parse-result-owners.axp"
    diagnostics = root / "tests/selfhost/compiler-parse-result-diagnostics.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    originals = {name: (root / "core" / name).read_text() for name in ("parser.ax", "repl.ax")}
    with tempfile.TemporaryDirectory(prefix="axiom-parse-result-owners-") as directory:
        work = Path(directory)

        def native(name, local, level, source=fixture):
            binary = work / name
            built = execute([compiler, "--diagnostic-format=ai", "build", str(source),
                             "--opt", str(level), "--alloc-poison", "-o", str(binary)], local)
            assert built.returncode == 0, (name, built.returncode, built.stdout, built.stderr)
            ran = execute([str(binary)], local)
            assert ran.returncode == 0 and not ran.stderr, (name, ran.returncode, ran.stdout, ran.stderr)
            return ran.stdout

        for level in (() if args.skip_positive else (0, 2)):
            name = "positive-O" + str(level)
            actual = native(name, env, level)
            assert actual == EXPECTED, (name, actual)
            print("ok   " + name, flush=True)
            name = "diagnostics-O" + str(level)
            actual = native(name, env, level, diagnostics)
            assert actual == BASELINE, (name, actual)
            print("ok   " + name + ": exact 4829-byte parser/editor/REPL baseline", flush=True)

        refused = {
            "erased-owner": ('(:: bad (-> (PResult String) Int)) (fn (bad result) result)', "AX3004"),
            "wrong-payload": ('(:: bad (PResult Nodes)) (fn (bad) (parseExpr (lex "1") 0))', "AX3004"),
            "unchecked-payload": ('(:: bad Int) (fn (bad) (nodeTag (pResNode (parseExpr (lex "1") 0))))', "AX3004"),
            "missing-failure": ('(:: bad ASTNode) (fn (bad) (match (parseExpr (lex "1") 0) '
                                '((ParseSuccess node pos) node)))', "AX3005"),
            "missing-success": ('(:: bad ASTNode) (fn (bad) (match (parseExpr (lex "1") 0) '
                                '((ParseFailed error) (mkTErr))))', "AX3005"),
            "missing-repl-diagnostics": ('(:: bad String)\n;@axiom:effect(io)\n(fn (bad) (match (replTryCompile "(") '
                                         '((ReplCompiled ir) ir)))', "AX3005"),
            "unchecked-repl": ('(:: bad String)\n;@axiom:effect(io)\n(fn (bad) (replCompile "("))', "AX3004"),
            "payload-in-position": ('(:: bad (PResult String)) (fn (bad) (pErr vecNew))', "AX3004"),
        }
        for name, (declaration, code) in refused.items():
            source = work / (name + ".ax")
            source.write_text("(import core)\n(import parser)\n(import lexer)\n(import repl)\n" + declaration +
                              "\n(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print("ok   " + name + ": " + code, flush=True)

        if args.negative_controls:
            controls = (
                ("present-query-lost", "parser.ax", "pResValue", "(Some value)", "None", 1),
                ("failure-expectation-lost", "parser.ax", "pErrExp", ":exp exp", ':exp ""', 7),
                ("eof-position-shifted", "parser.ax", "parseDecl", "(pOk None pos)", "(pOk None (+ pos 1))", 15),
                ("dual-template-expression-lost", "parser.ax", "parseRuleTemplates",
                 "(RuleTemplates :declarations declarations :expression (Some expression))",
                 "(RuleTemplates :declarations declarations :expression None)", 21),
                ("io-retry-disabled", "repl.ax", "replCompileExpr", "(replIoRetryNeeded diagnostics)", "false", 34),
                ("failure-context-copied", "parser.ax", "pResExp", "error.exp", "(strDup error.exp)", 28),
            )
            for name, module, function, old, new, first_false in controls:
                text = originals[module]
                start = text.index("(pub fn (" + function + " ")
                end = text.index("\n\n", start)
                body = text[start:end]
                assert body.count(old) == 1, (name, body.count(old))
                overlay = work / (name + "-core")
                overlay.mkdir()
                changed = text[:start] + body.replace(old, new) + text[end:]
                for path in (root / "core").iterdir():
                    if path.name == module:
                        (overlay / path.name).write_text(changed)
                    else:
                        (overlay / path.name).symlink_to(path, target_is_directory=path.is_dir())
                actual = native(name, dict(env, AXIOM_PATH=str(overlay)), 0)
                lines = [line for line in actual.splitlines() if line.split(" ", 1)[0].isdigit()]
                assert len(lines) == 35, (name, actual)
                failed = [i + 1 for i, line in enumerate(lines) if line != f"{i + 1} true"]
                assert failed and failed[0] == first_false, (name, failed, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   PResult ownership: 35 cases O0/O2 poison, exact parser/editor/REPL baseline, eight refusals")


if __name__ == "__main__":
    main()
