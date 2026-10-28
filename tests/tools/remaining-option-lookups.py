#!/usr/bin/env python3
"""Check typed absence across the remaining compiler and tool lookups."""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile


BRIDGES = {
    "nolint.ax": '''
(pub :: optionProbeOwner (-> Nodes Int (Option String)))
(pub fn (optionProbeOwner declarations offset) (nolintOwnerAt declarations offset))
''',
    "lsp.ax": '''
(pub :: optionProbeCompletionAt (-> Int String Nodes ASTNode (Option Int)))
(pub fn (optionProbeCompletionAt item source declarations declaration)
  (lspComplResolveAt item source declarations declaration))
(pub :: optionProbeCompletion (-> LspWorkspace String String Int (Option Int)))
;@axiom:effect(io)
(pub fn (optionProbeCompletion workspace uri source item)
  (lspComplResolve workspace uri source item))
''',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.compiler.resolve())
    base_environment = dict(os.environ, AXIOM_STDLIB=str(root / "stdlib"))
    expected = "".join(f"{index} true\n" for index in range(1, 27))

    def execute(arguments, environment, timeout=240):
        return subprocess.run(arguments, cwd=root, env=environment, capture_output=True,
                              text=True, timeout=timeout)

    with tempfile.TemporaryDirectory(prefix="axiom-remaining-option-lookups-") as directory:
        work = Path(directory)
        modules = work / "core"
        modules.mkdir()
        for path in (root / "core").iterdir():
            target = modules / path.name
            if path.name in BRIDGES:
                target.write_text(path.read_text() + BRIDGES[path.name])
            else:
                target.symlink_to(path, target_is_directory=path.is_dir())
        environment = dict(base_environment, AXIOM_PATH=str(modules))
        fixture = root / "tests/tools/remaining-option-lookups.axp"

        for level in (0, 2):
            binary = work / f"positive-O{level}"
            built = execute([compiler, "--diagnostic-format=ai", "build", str(fixture),
                             "--opt", str(level), "--alloc-poison", "-o", str(binary)], environment)
            assert built.returncode == 0, (level, built.stdout, built.stderr)
            ran = execute([str(binary)], environment, timeout=30)
            assert ran.returncode == 0 and not ran.stderr, (level, ran.returncode, ran.stderr)
            assert ran.stdout == expected, (level, ran.stdout)
            print(f"ok   O{level}: 26 present/absent lookup cases", flush=True)

        common = ("(import core)\n(import parser)\n(import expand)\n(import typecheck)\n"
                  "(import nolint)\n(import lsp)\n(import Vec)\n")
        refusals = {
            "format-run-as-node": ("(:: bad (-> MEnv ASTNode))\n"
                                   "(fn (bad env) (expFmtCatRun env None \"\" 0))", "AX3004"),
            "format-null-accumulator": ("(:: bad (-> MEnv ASTNode))\n"
                                        "(fn (bad env) (expFmtCat env nilNode (mkEInt 1) 0))", "AX3004"),
            "assembler-as-node": ("(:: bad ASTNode)\n"
                                  "(fn (bad) (expAsmOptNode vecNew vecNew \"pure\"))", "AX3004"),
            "macro-as-node": ("(:: bad ASTNode)\n(fn (bad) (expFirstMacroCall vecNew 0))", "AX3004"),
            "lint-owner-as-string": ("(:: bad String)\n(fn (bad) (optionProbeOwner vecNew 0))", "AX3004"),
            "completion-as-handle": ("(:: bad Int)\n"
                                     "(fn (bad) (optionProbeCompletionAt 0 \"\" vecNew nilNode))", "AX3004"),
            "node-missing-none": ("(:: bad ASTNode)\n"
                                  "(fn (bad) (match (expFirstMacroCall vecNew 0) ((Some node) node)))", "AX3005"),
            "node-missing-some": ("(:: bad Bool)\n"
                                  "(fn (bad) (match (expAsmOptNode vecNew vecNew \"pure\") ((None) true)))", "AX3005"),
        }
        for name, (declaration, code) in refusals.items():
            source = work / f"{name}.ax"
            source.write_text(common + declaration + "\n(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)],
                              environment, timeout=90)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print(f"ok   {name}: {code}", flush=True)

        # Removing an actual lookup result must be visible to the fixture.
        original = (root / "core/expand.ax").read_text()
        start = original.index("(pub fn (expFirstMacroCall ")
        end = original.index("\n\n", start)
        body = original[start:end]
        assert body.count("(Some (vecGet decls i))") == 1
        mutated = original[:start] + body.replace("(Some (vecGet decls i))", "None") + original[end:]
        control_modules = work / "control-core"
        control_modules.mkdir()
        for path in (root / "core").iterdir():
            target = control_modules / path.name
            if path.name == "expand.ax":
                target.write_text(mutated)
            elif path.name in BRIDGES:
                target.write_text(path.read_text() + BRIDGES[path.name])
            else:
                target.symlink_to(path, target_is_directory=path.is_dir())
        binary = work / "lost-macro-call"
        built = execute([compiler, "--diagnostic-format=ai", "build", str(fixture),
                         "--opt", "0", "--alloc-poison", "-o", str(binary)],
                        dict(base_environment, AXIOM_PATH=str(control_modules)))
        assert built.returncode == 0, (built.stdout, built.stderr)
        ran = execute([str(binary)], environment, timeout=30)
        rows = ran.stdout.splitlines()
        expected_rows = expected.splitlines()
        expected_rows[12] = "13 false"
        assert ran.returncode == 0 and not ran.stderr and rows == expected_rows, (
            ran.returncode, ran.stdout, ran.stderr)
        print("ok   lost-macro-call: case 13 detects the mutation", flush=True)

    print("ok   remaining lookups: 26 cases O0/O2 poison; 8 type/exhaustiveness refusals; one effective control")


if __name__ == "__main__":
    main()
