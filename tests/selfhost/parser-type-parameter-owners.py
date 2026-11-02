#!/usr/bin/env python3
"""Check owning data type parameter vectors and unchanged parser packets/errors."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

# Untouched 24d33195: eight data/struct inputs, five packets and three errors.
BASELINE = bytes.fromhex("534f5552434520286461746120506c61696e2028506c61696e29290a32505841000000001400000000000000286461746120506c61696e2028506c61696e29290000000001000000000000008c150000000000000500000000000000506c61696e000000010000000000000094160000000000000500000000000000506c61696e0000000000000000000000120000000d00000000000000000000000b0000000600000000000000000000000a534f5552434520286461746120456d7074792028292028456d70747929290a32505841000000001700000000000000286461746120456d7074792028292028456d70747929290001000000000000008c150000000000000500000000000000456d707479000000010000000000000094160000000000000500000000000000456d7074790000000000000000000000150000001000000000000000000000000b0000000600000000000000000000000a534f555243452028646174612050616972206120622028506169722061206229290a32505841000000001a00000000000000286461746120506169722061206220285061697220612062292900000000000001000000000000008c15000000000000040000000000000050616972000000000100000000000000941700000000000004000000000000005061697200000000020000000000000002000000000000000000000000000000000000000000000014000000100000000200000000000000a00000000000000001000000000000006100000000000000a000000000000000010000000000000062000000000000000a00000006000000020000000000000001000000000000006100000000000000010000000000000062000000000000000a534f55524345202873747275637420506c61696e202876616c7565203a20496e7429290a32505841000000001c000000000000002873747275637420506c61696e202876616c7565203a20496e7429290000000001000000000000008d050000000000000500000000000000506c61696e00000001000000000000009514000000000000050000000000000076616c7565000000140000000f000000a1010000000000000300000000000000496e74000000000000000000000000000d000000080000000a534f55524345202873747275637420456d707479202829202876616c7565203a20496e7429290a45204158323030312074797065706172616d732e61783a313a31362d313720756e65787065637465642d746f6b656e20226578706563746564206964656e7469666965722c20666f756e642060296022202322666f756e6420602960206865726522203f224178696f6d206578706563746564206964656e746966696572206174207468697320706f736974696f6e220a4e4f5f5041434b45540a534f55524345202873747275637420426f7820286129202876616c7565203a206129290a32505841000000001c000000000000002873747275637420426f7820286129202876616c7565203a206129290000000001000000000000008d150000000000000300000000000000426f78000000000001000000000000009514000000000000050000000000000076616c75650000001600000011000000a000000000000000010000000000000061000000000000000b000000080000000100000000000000010000000000000061000000000000000a534f555243452028646174610a45204158323030312074797065706172616d732e61783a313a3620756e65787065637465642d746f6b656e20226578706563746564206964656e7469666965722c20666f756e642060454f466022202322666f756e642060454f4660206865726522203f224178696f6d206578706563746564206964656e746966696572206174207468697320706f736974696f6e220a4e4f5f5041434b45540a534f55524345202864617461205820286129202843746f722061290a45204158323030312074797065706172616d732e61783a313a323120756e65787065637465642d746f6b656e20226578706563746564206964656e7469666965722c20666f756e642060454f466022202322666f756e642060454f4660206865726522203f224178696f6d206578706563746564206964656e746966696572206174207468697320706f736974696f6e220a4e4f5f5041434b45540a")
EXPECTED = "".join(f"{i} true\n" for i in range(1, 21)).encode()


def execute(arguments, env):
    return subprocess.run(arguments, env=env, capture_output=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/selfhost/parser-type-parameter-owners.axp"
    diagnostics = root / "tests/selfhost/parser-type-parameter-diagnostics.axp"
    env = dict(os.environ, AXIOM_PATH=str(root / "core"), AXIOM_STDLIB=str(root / "stdlib"))
    original = (root / "core/parser.ax").read_text()
    with tempfile.TemporaryDirectory(prefix="axiom-type-parameter-owners-") as directory:
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
            assert native(name, env, level) == EXPECTED, name
            print("ok   " + name, flush=True)
            name = "packets-errors-O" + str(level)
            actual = native(name, env, level, diagnostics)
            assert actual == BASELINE, (name, actual)
            print("ok   " + name + ": exact 1596 bytes", flush=True)

        refusals = {
            "word-parameters": "(parseConstructors (lex \")\") 0 \"X\" 0 vecNew 0)",
            "integer-parameters": "(parseConstructors (lex \")\") 0 \"X\" 0 vecNew (vecPush vecNew 1))",
        }
        for name, expression in refusals.items():
            source = work / (name + ".ax")
            source.write_text("(import core)\n(import lexer)\n(import parser)\n(import Vec)\n" +
                              "(:: bad (PResult ASTNode)) (fn (bad) " + expression + ")\n" +
                              "(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith(b"E ")]
            assert checked.returncode == 1 and len(errors) == 1 and b"E AX3004 " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print("ok   " + name + ": AX3004", flush=True)

        if args.negative_controls:
            old = "(setNodeTyNames (mkDDataAt dataName acc nameSpan) tvs)"
            assert original.count(old) == 1
            controls = (
                ("owner-map-lost", "(setNodeTyWord (mkDDataAt dataName acc nameSpan) (as tvs Int))"),
                ("parameter-content-lost", "(setNodeTyNames (mkDDataAt dataName acc nameSpan) vecNew)"),
                ("empty-presence-lost", "(if (== (vecLen tvs) 0) (mkDDataAt dataName acc nameSpan) " + old + ")"),
            )
            for name, replacement in controls:
                overlay = work / (name + "-core/core")
                overlay.mkdir(parents=True)
                for path in (root / "core").iterdir():
                    if path.name == "parser.ax":
                        (overlay / path.name).write_text(original.replace(old, replacement))
                    else:
                        (overlay / path.name).symlink_to(path, target_is_directory=path.is_dir())
                actual = native(name, dict(env, AXIOM_PATH=str(overlay)), 0)
                assert actual != EXPECTED and b"false" in actual and len(actual.splitlines()) == 20, (name, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   type parameter owners: 20 cases O0/O2 poison, five packets, three errors, two refusals")


if __name__ == "__main__":
    main()
