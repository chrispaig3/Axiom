#!/usr/bin/env python3
"""Check optional contract parsing, lowering, exact refusals and malformed input."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


# Unmodified cbedacac parser/checker/lowering, same nine parsed source cases.
DIAGNOSTICS = 'DIAGNOSTICS\nE AX3050 contract-empty.ax:1:1-12 contract-malformed "`;@axiom:pre` states a contract with no expression" ?"a `;@axiom:pre(...)` or `;@axiom:post(...)` is a claim the COMPILER cannot decide - there is no value analysis here - so it is compiled into the body and checked at run time, on every call, and a failure writes `axiom: precondition failed in `f`: ...` on fd 2 and exits 80. That is why the expression has to parse, has to be `Bool`, and has to PERFORM nothing: a contract that allocates or writes changes the program by being stated. Comparison, indexing, `strEq`, `strLen`, `vecLen` and `vecGet` are allocation-free and are what a predicate is written from; `concat`, `fmtInt` and `vecNew` are not. `result` names the declared result of a `post` and nothing anywhere else"\nE AX3050 contract-empty.ax:2:1-15 contract-malformed "`;@axiom:post()` states a contract with no expression" ?"a `;@axiom:pre(...)` or `;@axiom:post(...)` is a claim the COMPILER cannot decide - there is no value analysis here - so it is compiled into the body and checked at run time, on every call, and a failure writes `axiom: precondition failed in `f`: ...` on fd 2 and exits 80. That is why the expression has to parse, has to be `Bool`, and has to PERFORM nothing: a contract that allocates or writes changes the program by being stated. Comparison, indexing, `strEq`, `strLen`, `vecLen` and `vecGet` are allocation-free and are what a predicate is written from; `concat`, `fmtInt` and `vecNew` are not. `result` names the declared result of a `post` and nothing anywhere else"\nE AX3050 contract-whitespace.ax:1:13-15 contract-malformed "`  ` is not one expression, and a contract is exactly one" ?"a `;@axiom:pre(...)` or `;@axiom:post(...)` is a claim the COMPILER cannot decide - there is no value analysis here - so it is compiled into the body and checked at run time, on every call, and a failure writes `axiom: precondition failed in `f`: ...` on fd 2 and exits 80. That is why the expression has to parse, has to be `Bool`, and has to PERFORM nothing: a contract that allocates or writes changes the program by being stated. Comparison, indexing, `strEq`, `strLen`, `vecLen` and `vecGet` are allocation-free and are what a predicate is written from; `concat`, `fmtInt` and `vecNew` are not. `result` names the declared result of a `post` and nothing anywhere else"\nE AX3050 contract-malformed.ax:1:13-19 contract-malformed "`(> n 0` is not one expression, and a contract is exactly one" ?"a `;@axiom:pre(...)` or `;@axiom:post(...)` is a claim the COMPILER cannot decide - there is no value analysis here - so it is compiled into the body and checked at run time, on every call, and a failure writes `axiom: precondition failed in `f`: ...` on fd 2 and exits 80. That is why the expression has to parse, has to be `Bool`, and has to PERFORM nothing: a contract that allocates or writes changes the program by being stated. Comparison, indexing, `strEq`, `strLen`, `vecLen` and `vecGet` are allocation-free and are what a predicate is written from; `concat`, `fmtInt` and `vecNew` are not. `result` names the declared result of a `post` and nothing anywhere else"\nE AX3050 contract-trailing.ax:1:13-23 contract-malformed "`true false` is not one expression, and a contract is exactly one" ?"a `;@axiom:pre(...)` or `;@axiom:post(...)` is a claim the COMPILER cannot decide - there is no value analysis here - so it is compiled into the body and checked at run time, on every call, and a failure writes `axiom: precondition failed in `f`: ...` on fd 2 and exits 80. That is why the expression has to parse, has to be `Bool`, and has to PERFORM nothing: a contract that allocates or writes changes the program by being stated. Comparison, indexing, `strEq`, `strLen`, `vecLen` and `vecGet` are allocation-free and are what a predicate is written from; `concat`, `fmtInt` and `vecNew` are not. `result` names the declared result of a `post` and nothing anywhere else"\nE AX3001 contract-poison.ax:1:13-20 undefined-variable "undefined variable `unknown`" #"no binding named `unknown` in scope" ?"variables must be defined (via `fn`, a `let` binding, or a lambda parameter) before they are used; check for typos"\nE AX3050 contract-unit.ax:1:13-15 contract-malformed "`()` is the `pre` on `f` and has type `()`, not `Bool`" ?"a `;@axiom:pre(...)` or `;@axiom:post(...)` is a claim the COMPILER cannot decide - there is no value analysis here - so it is compiled into the body and checked at run time, on every call, and a failure writes `axiom: precondition failed in `f`: ...` on fd 2 and exits 80. That is why the expression has to parse, has to be `Bool`, and has to PERFORM nothing: a contract that allocates or writes changes the program by being stated. Comparison, indexing, `strEq`, `strLen`, `vecLen` and `vecGet` are allocation-free and are what a predicate is written from; `concat`, `fmtInt` and `vecNew` are not. `result` names the declared result of a `post` and nothing anywhere else"\nE AX3050 contract-order.ax:1:1-14 contract-malformed "`;@axiom:pre()` states a contract with no expression" ?"a `;@axiom:pre(...)` or `;@axiom:post(...)` is a claim the COMPILER cannot decide - there is no value analysis here - so it is compiled into the body and checked at run time, on every call, and a failure writes `axiom: precondition failed in `f`: ...` on fd 2 and exits 80. That is why the expression has to parse, has to be `Bool`, and has to PERFORM nothing: a contract that allocates or writes changes the program by being stated. Comparison, indexing, `strEq`, `strLen`, `vecLen` and `vecGet` are allocation-free and are what a predicate is written from; `concat`, `fmtInt` and `vecNew` are not. `result` names the declared result of a `post` and nothing anywhere else"\nE AX3050 contract-order.ax:2:13-26 contract-malformed "`true trailing` is not one expression, and a contract is exactly one" ?"a `;@axiom:pre(...)` or `;@axiom:post(...)` is a claim the COMPILER cannot decide - there is no value analysis here - so it is compiled into the body and checked at run time, on every call, and a failure writes `axiom: precondition failed in `f`: ...` on fd 2 and exits 80. That is why the expression has to parse, has to be `Bool`, and has to PERFORM nothing: a contract that allocates or writes changes the program by being stated. Comparison, indexing, `strEq`, `strLen`, `vecLen` and `vecGet` are allocation-free and are what a predicate is written from; `concat`, `fmtInt` and `vecNew` are not. `result` names the declared result of a `post` and nothing anywhere else"\nE AX3050 contract-order.ax:3:14-20 contract-malformed "`result` is the `post` on `f` and has type `Int`, not `Bool`" ?"a `;@axiom:pre(...)` or `;@axiom:post(...)` is a claim the COMPILER cannot decide - there is no value analysis here - so it is compiled into the body and checked at run time, on every call, and a failure writes `axiom: precondition failed in `f`: ...` on fd 2 and exits 80. That is why the expression has to parse, has to be `Bool`, and has to PERFORM nothing: a contract that allocates or writes changes the program by being stated. Comparison, indexing, `strEq`, `strLen`, `vecLen` and `vecGet` are allocation-free and are what a predicate is written from; `concat`, `fmtInt` and `vecNew` are not. `result` names the declared result of a `post` and nothing anywhere else"\nE AX3050 contract-purity.ax:4:13-28 contract-malformed "`(> (boxed n) 0)` is the `pre` on `f` and performs Alloc" ?"a `;@axiom:pre(...)` or `;@axiom:post(...)` is a claim the COMPILER cannot decide - there is no value analysis here - so it is compiled into the body and checked at run time, on every call, and a failure writes `axiom: precondition failed in `f`: ...` on fd 2 and exits 80. That is why the expression has to parse, has to be `Bool`, and has to PERFORM nothing: a contract that allocates or writes changes the program by being stated. Comparison, indexing, `strEq`, `strLen`, `vecLen` and `vecGet` are allocation-free and are what a predicate is written from; `concat`, `fmtInt` and `vecNew` are not. `result` names the declared result of a `post` and nothing anywhere else"\n'
EXPECTED = "".join(f"{index} true\n" for index in range(1, 28)) + DIAGNOSTICS


def execute(arguments, env):
    return subprocess.run(arguments, env=env, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/selfhost/typecheck-contract-expr-options.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    originals = {name: (root / "core" / name).read_text()
                 for name in ("parser.ax", "typecheck.ax", "expand.ax")}
    with tempfile.TemporaryDirectory(prefix="axiom-contract-expr-options-") as directory:
        work = Path(directory)

        def native(name, local, level, first_false=None, malformed_removed=False):
            binary = work / name
            built = execute([compiler, "--diagnostic-format=ai", "build", str(fixture),
                             "--opt", str(level), "--alloc-poison", "-o", str(binary)], local)
            assert built.returncode == 0, (name, built.returncode, built.stdout, built.stderr)
            ran = execute([str(binary)], local)
            assert ran.returncode == 0 and not ran.stderr and "PARSE_FAILURE" not in ran.stdout, (
                name, ran.returncode, ran.stdout, ran.stderr)
            if first_false is None and not malformed_removed:
                assert ran.stdout == EXPECTED, (name, ran.stdout)
            else:
                cases, marker, diagnostics = ran.stdout.partition("DIAGNOSTICS\n")
                assert marker and len(cases.splitlines()) == 27, (name, ran.stdout)
                failed = [i + 1 for i, line in enumerate(cases.splitlines()) if line != f"{i + 1} true"]
                if malformed_removed:
                    assert not failed and diagnostics.count("E AX3050 ") < DIAGNOSTICS.count("E AX3050 "), (
                        name, failed, diagnostics)
                    assert diagnostics.count("E AX3001 ") == DIAGNOSTICS.count("E AX3001 "), name
                else:
                    assert failed and failed[0] == first_false, (name, failed, ran.stdout)
            print("ok   " + name, flush=True)

        for level in (0, 2):
            native("positive-O" + str(level), env, level)

        refused = {
            "unchecked-query": ('(:: bad (-> AxtagEnt Int)) (fn (bad tag) (nodeTag (contractExprOf tag)))', "AX3004"),
            "missing-none": ('(:: bad (-> AxtagEnt ASTNode)) (fn (bad tag) (match (contractExprOf tag) '
                             '((Some expression) expression)))', "AX3005"),
            "wrong-handle": ('(:: bad (-> String (Option ASTNode))) (fn (bad tag) (contractExprOf tag))', "AX3004"),
        }
        for name, (declaration, code) in refused.items():
            source = work / (name + ".ax")
            source.write_text("(import core)\n(import parser)\n" + declaration +
                              "\n(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print("ok   " + name + ": " + code, flush=True)

        if args.negative_controls:
            controls = (
                ("trailing-expression-accepted", "parser.ax", "contractExprOf",
                 "(peekIs toks parsedPos126 TK_EOF)", "true", 5, False),
                ("present-expression-discarded", "parser.ax", "contractExprOf",
                 "(Some parsedValue126)", "None", 6, False),
                ("malformed-diagnostic-suppressed", "typecheck.ax", "checkOneContract",
                 "ELSE_BRANCH", "0", None, True),
                ("lowered-predicate-discarded", "expand.ax", "expSplitContracts",
                 "(vecPush pres (expContractCheck d t p))",
                 '(vecPush pres (expContractCheck d t (mkEVarAt "false" (nodeSpan p))))', 16, False),
            )
            for name, module, function, old, new, failed, removed in controls:
                text = originals[module]
                start = text.index("(pub fn (" + function + " ")
                end = text.index("\n\n", start)
                body = text[start:end]
                if old == "ELSE_BRANCH":
                    old = body[body.rindex("    (emitContractMalformed"):]
                    # The refused branch closes both the outer if and function.
                    new = "    0))"
                assert body.count(old) == 1, (name, body.count(old))
                changed = text[:start] + body.replace(old, new) + text[end:]
                overlay = work / (name + "-core/core")
                overlay.mkdir(parents=True)
                for path in (root / "core").iterdir():
                    if path.name == module:
                        (overlay / path.name).write_text(changed)
                    else:
                        (overlay / path.name).symlink_to(path, target_is_directory=path.is_dir())
                native(name, dict(env, AXIOM_PATH=str(overlay)), 0, failed, removed)
    print("ok   contract expression Options: 27 native cases O0/O2 poison, exact nine-source diagnostics, three refusals")


if __name__ == "__main__":
    main()
