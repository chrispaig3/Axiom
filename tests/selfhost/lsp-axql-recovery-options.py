#!/usr/bin/env python3
"""Check optional AXQL and recovery lookups with exact editor diagnostics."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import tempfile

# Exact editor output from unchanged 26104a19, including incomplete headers and CRLF edits.
BASELINE = 'CASE empty\n[]\n{"data":[]}\nlossy false\n[]\nCASE query-valid\n[{"name":"run","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":30}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}}]\n{"data":[0,1,2,9,0,0,4,3,7,3,0,6,6,7,0,0,7,1,11,0,0,1,6,9,0,0,6,1,11,0,0,1,1,12,0,0,1,1,11,0]}\nlossy false\n[]\nCASE query-refused\n[{"name":"run","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":35}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}}]\n{"data":[0,1,2,9,0,0,4,3,7,3,0,6,6,7,0,0,7,1,11,0,0,1,6,9,0,0,6,1,11,0,0,1,1,13,0,0,1,1,11,0,0,1,4,9,0,0,4,1,11,0]}\nlossy false\n[{"range":{"start":{"line":0,"character":19},"end":{"line":0,"character":32}},"severity":4,"code":"lint-axql","source":"axiom","message":"`SELECT * FROM` is not a statement AXQL reads: line 1, column 14: expected a table name, found the end of the statement"}]\nCASE query-second-arg\n[{"name":"run","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":33}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}}]\n{"data":[0,1,2,9,0,0,4,3,7,3,0,6,7,7,0,0,8,2,4,0,0,3,1,11,0,0,1,3,9,0,0,3,1,11,0,0,1,3,4,0,0,3,1,11,0]}\nlossy false\n[{"range":{"start":{"line":0,"character":23},"end":{"line":0,"character":26}},"severity":4,"code":"lint-axql","source":"axiom","message":"`not` is not a statement AXQL reads: line 1, column 1: expected a statement, found \\"not\\"; a statement starts with SELECT, INSERT, UPSERT, UPDATE, DELETE, CREATE, DROP, ALTER, BEGIN, COMMIT or ROLLBACK"}]\nCASE query-wrong-arg\n[{"name":"run","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":30}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}}]\n{"data":[0,1,2,9,0,0,4,3,7,3,0,6,7,7,0,0,8,9,11,0]}\nlossy false\n[]\nCASE query-script\n[{"name":"run","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":49}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}}]\n{"data":[0,1,2,9,0,0,4,3,7,3,0,6,12,7,0,0,13,2,4,0,0,3,1,11,0,0,1,6,9,0,0,6,1,11,0,0,1,1,12,0,0,1,1,13,0,0,1,1,11,0,0,1,6,9,0,0,6,1,11,0,0,1,1,12,0,0,1,1,11,0]}\nlossy false\n[]\nCASE query-escaped\n[{"name":"run","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":34}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}}]\n{"data":[0,1,2,9,0,0,4,3,7,3,0,6,6,7,0,0,7,14,11,0]}\nlossy false\n[{"range":{"start":{"line":0,"character":19},"end":{"line":0,"character":31}},"severity":4,"code":"lint-axql","source":"axiom","message":"`SELECT\\\\nFROM` is not a statement AXQL reads: line 2, column 1: expected an expression, found \\"FROM\\""}]\nCASE query-qualified\n[{"name":"run","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":41}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}}]\n{"data":[0,1,2,9,0,0,4,3,7,3,0,6,4,0,0,0,6,6,7,0,0,7,1,11,0,0,1,6,9,0,0,6,1,11,0,0,1,1,13,0,0,1,1,11,0,0,1,4,9,0,0,4,1,11,0]}\nlossy false\n[{"range":{"start":{"line":0,"character":25},"end":{"line":0,"character":38}},"severity":4,"code":"lint-axql","source":"axiom","message":"`SELECT * FROM` is not a statement AXQL reads: line 1, column 14: expected a table name, found the end of the statement"}]\nCASE open-string\n[{"name":"run","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":1,"character":13}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}},{"name":"next","kind":12,"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":13}},"selectionRange":{"start":{"line":1,"character":5},"end":{"line":1,"character":9}}}]\n{"data":[0,1,2,9,0,0,4,3,7,3,0,5,11,11,0,1,0,13,11,0]}\nlossy true\n[]\nCASE open-form\n[{"name":"run","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":19}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}}]\n{"data":[0,1,2,9,0,0,4,3,7,3,0,4,1,3,1,0,4,1,13,64,0,2,1,3,0,0,2,1,12,0]}\nlossy false\n[]\nCASE bad-nested\n[{"name":"run","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":23}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}},{"name":"next","kind":12,"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":13}},"selectionRange":{"start":{"line":1,"character":5},"end":{"line":1,"character":9}}}]\n{"data":[0,1,2,9,0,0,4,3,7,3,0,6,1,13,64,0,2,1,12,0,0,3,1,13,64,0,2,1,12,0,1,1,2,9,0,0,4,4,7,3,0,6,1,12,0]}\nlossy false\n[]\nCASE stray-close\n[{"name":"run","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":12}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}},{"name":"next","kind":12,"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":13}},"selectionRange":{"start":{"line":1,"character":5},"end":{"line":1,"character":9}}}]\n{"data":[0,1,2,9,0,0,4,3,7,3,0,5,1,12,0,1,1,2,9,0,0,4,4,7,3,0,6,1,12,0]}\nlossy true\n[]\nCASE open-vector\n[{"name":"run","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":15}},"selectionRange":{"start":{"line":0,"character":5},"end":{"line":0,"character":8}}},{"name":"next","kind":12,"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":13}},"selectionRange":{"start":{"line":1,"character":5},"end":{"line":1,"character":9}}}]\n{"data":[0,1,2,9,0,0,4,3,7,3,0,6,1,12,0,0,2,1,12,0,1,1,2,9,0,0,4,4,7,3,0,6,1,12,0]}\nlossy true\n[]\nCASE unbound-quote\n[]\n{"data":[0,0,11,11,0]}\nlossy true\n[]\n'
EXPECTED = "".join(f"{i} true\n" for i in range(1, 64))


def execute(arguments, env):
    return subprocess.run(arguments, env=env, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--negative-controls", action="store_true")
    parser.add_argument("--skip-positive", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/selfhost/lsp-axql-recovery-options.axp"
    goldens = root / "tests/selfhost/lsp-axql-recovery-goldens.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    original = (root / "core/lsp.ax").read_text()
    with tempfile.TemporaryDirectory(prefix="axiom-lsp-axql-recovery-options-") as directory:
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
            print("ok   " + name + ": 63 query/recovery cases", flush=True)
            name = "editor-bytes-O" + str(level)
            actual = native(name, env, level, goldens)
            assert actual == BASELINE, (name, actual)
            print("ok   " + name + f": exact {len(BASELINE.encode())} bytes, 14 editor scenarios", flush=True)

        queries = {
            "query-argument": 'lspAxqlArgIndex "axqSql"',
            "error-offset": 'lspAxqlErrOffset "" "line 1, column 1"',
            "digits": 'lspAxqlDigitsAt "0" 0',
            "open-string": 'lspRecOpenString "" vecNew',
            "enclosing": 'lspRecEnclosing vecNew 0',
            "repair-group": 'lspRecGroupOf vecNew 0',
        }
        refusals = {"unchecked-" + name: ('(:: bad Int) (fn (bad) (' + query + '))', 'AX3004')
                    for name, query in queries.items()}
        refusals.update({
            "unchecked-refusal": ('(:: bad String) (fn (bad) (lspAxqlRefusal "SELECT 1" false))', 'AX3004'),
            "raw-repair-group": ('(:: bad Tokens) (fn (bad) (lspRepairWiden vecNew 0 vecNew))', 'AX3004'),
            "missing-none": ('(:: bad Bool) (fn (bad) (match (lspAxqlDigitsAt "0" 0) ((Some i) true)))', 'AX3005'),
            "missing-some": ('(:: bad Bool) (fn (bad) (match (lspRecEnclosing vecNew 0) ((None) false)))', 'AX3005'),
        })
        for name, (declaration, code) in refusals.items():
            source = work / (name + ".ax")
            source.write_text("(import core)\n(import lsp)\n" + declaration +
                              "\n(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print("ok   " + name + ": " + code, flush=True)

        if args.negative_controls:
            controls = (
                ('argument-zero-lost', 'lspAxqlArgIndex', '(Some 0)', 'None', False),
                ('digits-zero-lost', 'lspAxqlDigitsAt', '(Some v)', 'None', False),
                ('error-offset-lost', 'lspAxqlErrOffset', '(Some (if (> (+ i (- col 1)) n) n (+ i (- col 1))))', 'None', False),
                ('refusal-lost', 'lspAxqlRefusal', '((Err e) (Some (errMessage e)))', '((Err e) None)', False),
                ('literal-hit-lost', 'lspAxqlLitAt', '(set hit (Some i))', '(set hit None)', False),
                ('literal-open-lost', 'lspAxqlLitOf', '(set open (Some j))', '(set open None)', False),
                ('lint-argument-lost', 'lspLintAxql', '(if (!= wanted idx) 0', '(if true 0', True),
                ('open-string-lost', 'lspRecOpenString', '(set at (Some s))', '(set at None)', False),
                ('enclosing-lost', 'lspRecEnclosing', '(set at (Some i))', '(set at None)', False),
                ('repair-group-lost', 'lspRecGroupOf', '(Some e)', 'None', False),
                ('missing-repair-forged', 'lspRepairWiden', '((None) vecNew)', '((None) toks)', False),
                ('string-repair-lost', 'lspRecoverStrings', '(if (>= round 8) toks', '(if true toks', True),
                ('recovery-loss-marker-lost', 'lspRecover', '(isSome (lspRecOpenString src toks))', 'false', True),
                ('query-head-classification', 'lspHlHeadCode', '(+ 25 index)', '(+ 24 index)', True),
            )
            for name, function, old, new, wire in controls:
                start = original.index("(pub fn (" + function + " ")
                end = original.index("\n\n", start)
                body = original[start:end]
                pattern = re.compile(r"\s*".join(re.escape(part) for part in re.findall(r'"(?:\\.|[^"\\])*"|[(){}]|[^\s(){}]+', old)))
                want = 2 if name == "refusal-lost" else 1
                assert len(pattern.findall(body)) == want, (name, len(pattern.findall(body)))
                changed = original[:start] + pattern.sub(lambda match: new, body) + original[end:]
                overlay = work / (name + "-core/core")
                overlay.mkdir(parents=True)
                for path in (root / "core").iterdir():
                    if path.name == "lsp.ax":
                        (overlay / path.name).write_text(changed)
                    else:
                        (overlay / path.name).symlink_to(path, target_is_directory=path.is_dir())
                actual = native(name, dict(env, AXIOM_PATH=str(overlay)), 0, goldens if wire else fixture)
                if wire:
                    assert actual != BASELINE and actual.count("CASE ") == 14 and len(actual.splitlines()) == len(BASELINE.splitlines()), (name, actual)
                else:
                    assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 63, (name, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   LSP AXQL/recovery Options: 63 cases O0/O2 poison, exact editor bytes, 10 refusals")


if __name__ == "__main__":
    main()
