#!/usr/bin/env python3
"""Check checker AXTAG owners, optional metadata and exact claim diagnostics."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

# Untouched 3d1f7937: sixteen source cases, including ordering and malformed claims.
BASELINE = 'SOURCE pure.ax\nSOURCE dedup.ax\nE AX3010 dedup.ax:4:10-14 axtag-mismatch "AXTAG mismatch on `liar`: `effect(pure)` claim contradicted: body performs IO" ?"an AXTAG is a CLAIM, and this is the compiler answering it: make the body match the tag, or correct the tag to what the body does. Deleting the tag also silences this, and an untagged function is never checked - but that WITHDRAWS the claim rather than answering it, and every reader that trusted the tag loses the guarantee. A claim the walk cannot check is AX3037 and stays a warning; this code fires only where the walk has an answer"\nSOURCE unsafe.ax\nSOURCE missing-io.ax\nE AX3042 missing-io.ax:1:10-15 undeclared-effect "`count` performs IO and its declaration does not say so" !"effects are INFERRED transitively, so this fires on every function up the call chain, and each one is a place a reader would otherwise have to open the callee to learn it. If the effect is not wanted here the fix is to stop performing it, not to stop saying so. `IO`, `Entropy`, `Spawn` and `Block` are required; `Alloc` and `Mut` are ambient and never need declaring" ?1:1:"write `;@axiom:effect(io)` above the declaration"~>";@axiom:effect(io)\\n"\nSOURCE typo.ax\nE AX3039 typo.ax:2:10-14 axtag-key-typo "AXTAG key typo on `test`: unrecognised key `effct`; did you mean `effect`?" ?"an unrecognised key is recorded and never checked, so the claim this looks like was not made. Fix the spelling, or namespace a key of your own, such as `;@axiom:my:KEY(...)`, so it cannot be mistaken for a claim"\nSOURCE misplaced.ax\nE AX3077 misplaced.ax:2:7-12 axtag-misplaced "the `effect` tag on `Shape` is never checked: it is a `data` declaration" #"tag not checked here" !"the tag was recorded and nothing read it, so the claim it looks like was never made; an unrecognised key is still legal metadata" ?"a checked claim belongs above the function it describes - its `(:: ...)` or its `(fn ...)`; move it there, or drop it"\nSOURCE field.ax\nSOURCE contract-type.ax\nE AX3050 contract-type.ax:1:13-14 contract-malformed "`1` is the `pre` on `test` and has type `Int`, not `Bool`" ?"a `;@axiom:pre(...)` or `;@axiom:post(...)` is a claim the COMPILER cannot decide - there is no value analysis here - so it is compiled into the body and checked at run time, on every call, and a failure writes `axiom: precondition failed in `f`: ...` on fd 2 and exits 80. That is why the expression has to parse, has to be `Bool`, and has to PERFORM nothing: a contract that allocates or writes changes the program by being stated. Comparison, indexing, `strEq`, `strLen`, `vecLen` and `vecGet` are allocation-free and are what a predicate is written from; `concat`, `fmtInt` and `vecNew` are not. `result` names the declared result of a `post` and nothing anywhere else"\nSOURCE contract-empty.ax\nE AX3050 contract-empty.ax:1:1-14 contract-malformed "`;@axiom:pre()` states a contract with no expression" ?"a `;@axiom:pre(...)` or `;@axiom:post(...)` is a claim the COMPILER cannot decide - there is no value analysis here - so it is compiled into the body and checked at run time, on every call, and a failure writes `axiom: precondition failed in `f`: ...` on fd 2 and exits 80. That is why the expression has to parse, has to be `Bool`, and has to PERFORM nothing: a contract that allocates or writes changes the program by being stated. Comparison, indexing, `strEq`, `strLen`, `vecLen` and `vecGet` are allocation-free and are what a predicate is written from; `concat`, `fmtInt` and `vecNew` are not. `result` names the declared result of a `post` and nothing anywhere else"\nSOURCE contract-trailing.ax\nE AX3050 contract-trailing.ax:1:13-23 contract-malformed "`true false` is not one expression, and a contract is exactly one" ?"a `;@axiom:pre(...)` or `;@axiom:post(...)` is a claim the COMPILER cannot decide - there is no value analysis here - so it is compiled into the body and checked at run time, on every call, and a failure writes `axiom: precondition failed in `f`: ...` on fd 2 and exits 80. That is why the expression has to parse, has to be `Bool`, and has to PERFORM nothing: a contract that allocates or writes changes the program by being stated. Comparison, indexing, `strEq`, `strLen`, `vecLen` and `vecGet` are allocation-free and are what a predicate is written from; `concat`, `fmtInt` and `vecNew` are not. `result` names the declared result of a `post` and nothing anywhere else"\nSOURCE post-result.ax\nSOURCE post-missing.ax\nSOURCE deprecated.ax\nW AX3048 deprecated.ax:3:19-22 deprecated-name "`old` is deprecated" #"declared `;@axiom:deprecated(use newer)`" !"It still works, and it still compiles - a deprecation is a notice, not a refusal. It may be removed in a later release, and `compat/BREAKING`\'s rule lets that happen without a declared break precisely because this notice shipped first" ?"the declaration says: use newer"\nSOURCE restrict.ax\nE AX3049 restrict.ax:2:10-14 restriction-violated "`test` claims `restrict(no-io)` and the body performs IO: test -> __argc" ^-:"__argc" ?"a restriction is a CLAIM the author wrote, and this is the compiler answering it. `no-io`, `no-alloc`, `no-unsafe`, `no-foreign`, `no-cast:deep` and `no-recursion` are transitive - the effect row and the call graph are fixpoints over every callee - and the path in the message is the chain of resolved calls (`symbols --calls` spells each hop the same way) from this declaration to where the effect enters, or around the cycle, so the fix is at a named place rather than somewhere below. Make the body keep the claim, or delete the tag, which WITHDRAWS the claim rather than answering it; an unrestricted function is never asked"\nE AX3042 restrict.ax:2:10-14 undeclared-effect "`test` performs IO and its declaration does not say so" !"effects are INFERRED transitively, so this fires on every function up the call chain, and each one is a place a reader would otherwise have to open the callee to learn it. If the effect is not wanted here the fix is to stop performing it, not to stop saying so. `IO`, `Entropy`, `Spawn` and `Block` are required; `Alloc` and `Mut` are ambient and never need declaring" ?2:1:"write `;@axiom:effect(io)` above the declaration"~>";@axiom:effect(io)\\n"\nSOURCE isr.ax\nE AX3010 isr.ax:2:10-17 axtag-mismatch "AXTAG mismatch on `handler`: `isr` marks an interrupt entry point, which the hardware calls by name with no arguments - this declaration takes parameters, so it cannot be one. Remove the parameters, or drop the tag" ?"an AXTAG is a CLAIM, and this is the compiler answering it: make the body match the tag, or correct the tag to what the body does. Deleting the tag also silences this, and an untagged function is never checked - but that WITHDRAWS the claim rather than answering it, and every reader that trusted the tag loses the guarantee. A claim the walk cannot check is AX3037 and stays a warning; this code fires only where the walk has an answer"\nSOURCE ct.ax\nE AX3093 ct.ax:2:10-14 ct-claim-malformed "`test` claims `ct(missing)`, and `missing` isn\'t one of its parameters" ?"`ct(...)` names the parameters that carry secrets: `name` for a secret value, `*name` for an address whose memory is secret. Name only this function\'s own parameters"\n'
EXPECTED = "".join(f"{i} true\n" for i in range(1, 43))


def execute(arguments, env):
    return subprocess.run(arguments, env=env, capture_output=True, text=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", type=Path, required=True)
    parser.add_argument("--negative-controls", action="store_true")
    parser.add_argument("--dependency-core", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.axiom.resolve())
    fixture = root / "tests/selfhost/checker-axtag-owners.axp"
    diagnostics = root / "tests/selfhost/checker-axtag-diagnostics.axp"
    module_root = args.dependency_core.resolve() if args.dependency_core else root / "core"
    env = dict(os.environ, AXIOM_PATH=str(module_root), AXIOM_STDLIB=str(root / "stdlib"))
    original = (module_root / "typecheck.ax").read_text()
    with tempfile.TemporaryDirectory(prefix="axiom-checker-axtag-owners-") as directory:
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
            print("ok   " + name + ": exact 7221 bytes from sixteen sources", flush=True)

        refusals = {
            "word-entry": ('(:: bad (-> Int String)) (fn (bad tag) (axtagKeyOf tag))', 'AX3004'),
            "word-list": ('(:: bad (-> Ints Int)) (fn (bad tags) (tagsClaimPure tags vecNew))', 'AX3004'),
            "string-list": ('(:: bad Int) (fn (bad) (tagsClaimPure (vecPush vecNew "pure") vecNew))', 'AX3004'),
            "unchecked-signature": ('(:: bad (-> TC Axtags)) (fn (bad tc) (sigAxtagsFor tc "f"))', 'AX3004'),
            "missing-none": ('(:: bad (-> TC Int)) (fn (bad tc) (match (sigAxtagsFor tc "f") '
                             '((Some tags) (vecLen tags))))', 'AX3005'),
            "string-offset": ('(:: bad AxtagEnt) (fn (bad) (AxtagEnt :off "0" :content "pure"))', 'AX3004'),
        }
        for name, (declaration, code) in refusals.items():
            source = work / (name + ".ax")
            source.write_text("(import core)\n(import parser)\n(import typecheck)\n(import Vec)\n" + declaration +
                              "\n(:: main Int) (fn (main) 0)\n")
            checked = execute([compiler, "--diagnostic-format=ai", "check", str(source)], env)
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            assert checked.returncode == 1 and len(errors) == 1 and f"E {code} " in errors[0], (
                name, checked.returncode, checked.stdout, checked.stderr)
            print("ok   " + name + ": " + code, flush=True)

        # The asserted-valid test factory stops at parse failure, before constructing TC.
        death = work / "parse-assertion.axp"
        source = fixture.read_text()
        start = source.index("(:: main Int)")
        death.write_text(source[:start] + '(:: main Int) (fn (main) { (context "(") 0 })\n')
        binary = work / "parse-assertion"
        built = execute([compiler, "--diagnostic-format=ai", "build", str(death), "--opt", "0", "-o", str(binary)], env)
        assert built.returncode == 0, (built.stdout, built.stderr)
        stopped = execute([str(binary)], env)
        assert stopped.returncode == 77, (stopped.returncode, stopped.stdout, stopped.stderr)
        print("ok   invalid test factory: checked trap 77 before TC", flush=True)

        if args.negative_controls:
            controls = (
                ("content-discarded", "axtagContent", "t.content", '\"\"'),
                ("empty-signature-lost", "sigAxtagsFrom", "(nodeAxtagsOpt d)",
                 "(if (== (vecLen (nodeAxtagsOf d)) 0) None (nodeAxtagsOpt d))"),
                ("purity-claim-lost", "tagsClaimPure", "BODY", "0"),
                ("dedup-content-lost", "axtagContentSeen", "BODY", "0"),
                ("contract-span-shifted", "contractSpanOf", "(contractBaseOf t)", "(+ (contractBaseOf t) 1)"),
                ("malformed-refusal-lost", "checkOneContract", "MALFORMED", "0"),
            )
            for name, function, old, new in controls:
                start = original.index("(pub fn (" + function + " ") if function != "axtagContent" else original.index("(fn (axtagContent ")
                end = original.index("\n\n", start)
                body = original[start:end]
                if old == "BODY":
                    first_line = body.index("\n")
                    changed_body = body[:first_line] + "\n  " + new + ")"
                elif old == "MALFORMED":
                    offset = body.rindex("    (emitContractMalformed")
                    changed_body = body[:offset] + "    0))"
                else:
                    assert body.count(old) >= 1, (name, body.count(old))
                    changed_body = body.replace(old, new)
                changed = original[:start] + changed_body + original[end:]
                overlay = work / (name + "-core/core")
                overlay.mkdir(parents=True)
                for path in module_root.iterdir():
                    if path.name == "typecheck.ax":
                        (overlay / path.name).write_text(changed)
                    else:
                        (overlay / path.name).symlink_to(path, target_is_directory=path.is_dir())
                actual = native(name, dict(env, AXIOM_PATH=str(overlay)), 0)
                assert actual != EXPECTED and "false" in actual and len(actual.splitlines()) == 42, (name, actual)
                print("ok   " + name + ": effective mutation", flush=True)
    print("ok   checker AXTAG owners: 42 native cases O0/O2 poison, sixteen diagnostics, six typing refusals")


if __name__ == "__main__":
    main()
