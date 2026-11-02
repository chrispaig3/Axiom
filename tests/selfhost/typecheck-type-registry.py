#!/usr/bin/env python3
"""Check typed registry lookup and refusal with the selected compiler."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import tempfile


def witness_negative_control(compiler, repo, env, work):
    """Prove that suppressing an invalid cast witness fails the runtime probe."""
    overlay = work / "negative-core/core"
    overlay.mkdir(parents=True)
    for source in (repo / "core").iterdir():
        if source.is_file() and source.name != "typecheck.ax":
            (overlay / source.name).symlink_to(source)
    source = (repo / "core/typecheck.ax").read_text()
    old = """              (castTypeBadArgs (spineArgVec e vecNew) 0))
          }
          (Some e)))"""
    if source.count(old) != 1:
        raise SystemExit("cast witness control no longer matches its single implementation site")
    (overlay / "typecheck.ax").write_text(source.replace(old, old.replace("(Some e)", "None")))
    executable = work / "witness-negative"
    built = subprocess.run(
        [str(compiler), "--diagnostic-format=ai", "build",
         str(repo / "tests/selfhost/typecheck-witness-options.ax"),
         "--opt", "0", "--output", str(executable)],
        env=dict(env, AXIOM_PATH=str(overlay)), capture_output=True, text=True,
    )
    if built.returncode:
        raise SystemExit(built.stdout + built.stderr)
    ran = subprocess.run([str(executable)], capture_output=True, text=True)
    if ran.returncode != 3 or ran.stdout or ran.stderr:
        raise SystemExit(f"cast witness control: status={ran.returncode}, stdout={ran.stdout!r}, stderr={ran.stderr!r}")
    print("cast witness negative control rejected the missing-witness mutation (status 3)")


def field_negative_control(compiler, repo, env, work):
    """Prove that a found poison field cannot silently become a wildcard."""
    overlay = work / "negative-field-core/core"
    overlay.mkdir(parents=True)
    for source in (repo / "core").iterdir():
        if source.is_file() and source.name != "typecheck.ax":
            (overlay / source.name).symlink_to(source)
    source = (repo / "core/typecheck.ax").read_text()
    pattern = re.compile(
        r"(\(Some\s+\(if \(< index \(vecLen ctor\.fieldTys\)\)\s+"
        r"\(vecGet ctor\.fieldTys index\)\s+)mkTErr(\)\))"
    )
    if len(pattern.findall(source)) != 1:
        raise SystemExit("field poison control no longer matches its single implementation site")
    (overlay / "typecheck.ax").write_text(pattern.sub(lambda m: m[1] + "mkSilentWild" + m[2], source))
    executable = work / "field-negative"
    built = subprocess.run(
        [str(compiler), "--diagnostic-format=ai", "build",
         str(repo / "tests/selfhost/typecheck-field-options.ax"),
         "--opt", "0", "--output", str(executable)],
        env=dict(env, AXIOM_PATH=str(overlay)), capture_output=True, text=True,
    )
    if built.returncode:
        raise SystemExit(built.stdout + built.stderr)
    ran = subprocess.run([str(executable)], capture_output=True, text=True)
    if ran.returncode != 2 or ran.stdout or ran.stderr:
        raise SystemExit(f"field poison control: status={ran.returncode}, stdout={ran.stdout!r}, stderr={ran.stderr!r}")
    print("field poison negative control rejected the wildcard mutation (status 2)")


def collector_negative_control(compiler, repo, env, work):
    """Prove that built-empty caches cannot be rescanned as unbuilt."""
    overlay = work / "negative-collector-core/core"
    overlay.mkdir(parents=True)
    for source in (repo / "core").iterdir():
        if source.is_file() and source.name != "typecheck.ax":
            (overlay / source.name).symlink_to(source)
    source = (repo / "core/typecheck.ax").read_text()
    old = """(if (let (Some cached) (tcSigTags tc))
        cached"""
    if source.count(old) != 1:
        raise SystemExit("cache control no longer matches its single implementation site")
    changed = old.replace("\n        cached", "\n        (sigTagsBuild (tcAllDeclsVec tc) vecNew 0)")
    (overlay / "typecheck.ax").write_text(source.replace(old, changed))
    executable = work / "collector-negative"
    built = subprocess.run(
        [str(compiler), "--diagnostic-format=ai", "build",
         str(repo / "tests/selfhost/typecheck-collector-options.ax"),
         "--opt", "0", "--output", str(executable)],
        env=dict(env, AXIOM_PATH=str(overlay)), capture_output=True, text=True,
    )
    if built.returncode:
        raise SystemExit(built.stdout + built.stderr)
    ran = subprocess.run([str(executable)], capture_output=True, text=True)
    if ran.returncode != 2 or ran.stdout or ran.stderr:
        raise SystemExit(f"cache control: status={ran.returncode}, stdout={ran.stdout!r}, stderr={ran.stderr!r}")
    print("cache negative control rejected the built-empty rescan mutation (status 2)")


def current_decl_negative_control(compiler, repo, env, work):
    """Prove that dropping a present declaration fails the stamp layout probe."""
    overlay = work / "negative-current-decl-core/core"
    overlay.mkdir(parents=True)
    for source in (repo / "core").iterdir():
        if source.is_file() and source.name != "parser.ax":
            (overlay / source.name).symlink_to(source)
    source = (repo / "core/parser.ax").read_text()
    old = """(pub fn (nodeBuildEvstampCallOptional declaration words env)
  (nodeBuildEvstampCallPlain
    (match declaration
      ((None) nilNode)
      ((Some node) node))
    words env))"""
    if source.count(old) != 1:
        raise SystemExit("current declaration control no longer matches its single boundary site")
    (overlay / "parser.ax").write_text(source.replace(old, old.replace("((Some node) node)", "((Some node) nilNode)")))
    executable = work / "current-decl-negative"
    built = subprocess.run(
        [str(compiler), "--diagnostic-format=ai", "build",
         str(repo / "tests/selfhost/typecheck-current-decl-options.ax"),
         "--opt", "0", "--output", str(executable)],
        env=dict(env, AXIOM_PATH=str(overlay)), capture_output=True, text=True,
    )
    if built.returncode:
        raise SystemExit(built.stdout + built.stderr)
    ran = subprocess.run([str(executable)], capture_output=True, text=True)
    if ran.returncode != 2 or ran.stdout or ran.stderr:
        raise SystemExit(f"declaration stamp control: status={ran.returncode}, stdout={ran.stdout!r}, stderr={ran.stderr!r}")
    print("declaration stamp negative control rejected the discarded Some payload (status 2)")


def constructor_name_negative_control(compiler, repo, env, work):
    """Prove that a named empty variant cannot be collapsed to positional."""
    overlay = work / "negative-constructor-name-core/core"
    overlay.mkdir(parents=True)
    for source in (repo / "core").iterdir():
        if source.is_file() and source.name != "parser.ax":
            (overlay / source.name).symlink_to(source)
    source = (repo / "core/parser.ax").read_text()
    old = "(Some (nodeFieldNamesNames node))"
    if source.count(old) != 1:
        raise SystemExit("constructor metadata control no longer matches its single boundary site")
    changed = """(let names (nodeFieldNamesNames node))"""
    # Keep the binding within an expression block; only the empty case changes.
    changed = "{ " + changed + " (if (== (vecLen names) 0) None (Some names)) }"
    (overlay / "parser.ax").write_text(source.replace(old, changed))
    executable = work / "constructor-name-negative"
    built = subprocess.run(
        [str(compiler), "--diagnostic-format=ai", "build",
         str(repo / "tests/selfhost/typecheck-constructor-name-options.ax"),
         "--opt", "0", "--output", str(executable)],
        env=dict(env, AXIOM_PATH=str(overlay)), capture_output=True, text=True,
    )
    if built.returncode:
        raise SystemExit(built.stdout + built.stderr)
    ran = subprocess.run([str(executable)], capture_output=True, text=True)
    if ran.returncode != 1 or ran.stdout or ran.stderr:
        raise SystemExit(f"constructor metadata control: status={ran.returncode}, stdout={ran.stdout!r}, stderr={ran.stderr!r}")
    print("constructor metadata negative control rejected Some-empty collapse (status 1)")


def exhaustiveness_negative_control(compiler, repo, env, work):
    """Prove that an empty failure witness cannot be mistaken for success."""
    overlay = work / "negative-exhaustiveness-core/core"
    overlay.mkdir(parents=True)
    for source in (repo / "core").iterdir():
        if source.is_file() and source.name != "typecheck.ax":
            (overlay / source.name).symlink_to(source)
    source = (repo / "core/typecheck.ax").read_text()
    old = """(if (> (vecLen matrix) 0)
      None
      (Some vecNew))"""
    if source.count(old) != 1:
        raise SystemExit("matrix control no longer matches its single implementation site")
    (overlay / "typecheck.ax").write_text(source.replace(old, old.replace("(Some vecNew)", "None")))
    executable = work / "exhaustiveness-negative"
    built = subprocess.run(
        [str(compiler), "--diagnostic-format=ai", "build",
         str(repo / "tests/selfhost/typecheck-exhaustiveness-options.ax"),
         "--opt", "0", "--output", str(executable)],
        env=dict(env, AXIOM_PATH=str(overlay)), capture_output=True, text=True,
    )
    if built.returncode:
        raise SystemExit(built.stdout + built.stderr)
    ran = subprocess.run([str(executable)], capture_output=True, text=True)
    if ran.returncode != 1 or ran.stdout or ran.stderr:
        raise SystemExit(f"matrix control: status={ran.returncode}, stdout={ran.stdout!r}, stderr={ran.stderr!r}")
    print("matrix negative control rejected Some-empty success conflation (status 1)")


def declaration_field_negative_control(compiler, repo, env, work):
    """Prove that an empty multi-name declaration is still present metadata."""
    overlay = work / "negative-declaration-field-core/core"
    overlay.mkdir(parents=True)
    for source in (repo / "core").iterdir():
        if source.is_file() and source.name != "typecheck.ax":
            (overlay / source.name).symlink_to(source)
    source = (repo / "core/typecheck.ax").read_text()
    old = """(if (== (nodeTag d) TAG_D_EFFECT)
    (Some (nodeCChildren d))"""
    if source.count(old) != 1:
        raise SystemExit("declaration field control no longer matches its single implementation site")
    changed = old.replace("(Some (nodeCChildren d))", "(if (== (vecLen (nodeCChildren d)) 0) None (Some (nodeCChildren d)))")
    (overlay / "typecheck.ax").write_text(source.replace(old, changed))
    executable = work / "declaration-field-negative"
    built = subprocess.run(
        [str(compiler), "--diagnostic-format=ai", "build",
         str(repo / "tests/selfhost/typecheck-declaration-field-options.ax"),
         "--opt", "0", "--output", str(executable)],
        env=dict(env, AXIOM_PATH=str(overlay)), capture_output=True, text=True,
    )
    if built.returncode:
        raise SystemExit(built.stdout + built.stderr)
    ran = subprocess.run([str(executable)], capture_output=True, text=True)
    if ran.returncode != 1 or ran.stdout or ran.stderr:
        raise SystemExit(f"declaration field control: status={ran.returncode}, stdout={ran.stdout!r}, stderr={ran.stderr!r}")
    print("declaration field negative control rejected empty metadata collapse (status 1)")


def semantic_string_negative_control(compiler, repo, env, work):
    """Prove that present empty ISR metadata is distinct from absence."""
    overlay = work / "negative-semantic-string-core/core"
    overlay.mkdir(parents=True)
    for source in (repo / "core").iterdir():
        if source.is_file() and source.name != "typecheck.ax":
            (overlay / source.name).symlink_to(source)
    source = (repo / "core/typecheck.ax").read_text()
    old = "(Some (strTrim (strSlice content 4 (- (strLen content) 5))))"
    if source.count(old) != 1:
        raise SystemExit("ISR metadata control no longer matches its single implementation site")
    changed = "{ (let value (strTrim (strSlice content 4 (- (strLen content) 5)))) (if (== (strLen value) 0) None (Some value)) }"
    (overlay / "typecheck.ax").write_text(source.replace(old, changed))
    executable = work / "semantic-string-negative"
    built = subprocess.run(
        [str(compiler), "--diagnostic-format=ai", "build",
         str(repo / "tests/selfhost/typecheck-semantic-string-options.ax"),
         "--opt", "0", "--output", str(executable)],
        env=dict(env, AXIOM_PATH=str(overlay)), capture_output=True, text=True,
    )
    if built.returncode:
        raise SystemExit(built.stdout + built.stderr)
    ran = subprocess.run([str(executable)], capture_output=True, text=True)
    if ran.returncode != 2 or ran.stdout or ran.stderr:
        raise SystemExit(f"ISR metadata control: status={ran.returncode}, stdout={ran.stdout!r}, stderr={ran.stderr!r}")
    print("ISR metadata negative control rejected Some-empty collapse (status 2)")


def capture_name_negative_control(compiler, repo, env, work):
    """Prove that an empty captured name is still a successful lookup."""
    overlay = work / "negative-capture-name-core/core"
    overlay.mkdir(parents=True)
    for source in (repo / "core").iterdir():
        if source.is_file() and source.name != "typecheck.ax":
            (overlay / source.name).symlink_to(source)
    source = (repo / "core/typecheck.ax").read_text()
    old = """(pub fn (rgnCaptureFrom names masks bit i)
  (if (>= i (vecLen names))
    None
    (if (!= (& (vecGet masks i) (<< 1 bit)) 0)
      (Some (vecGet names i))
      (rgnCaptureFrom names masks bit (+ i 1)))))"""
    if source.count(old) != 1:
        raise SystemExit("capture name control no longer matches its single lookup site")
    changed = old.replace("(Some (vecGet names i))", "{ (let name (vecGet names i)) (if (== (strLen name) 0) None (Some name)) }")
    (overlay / "typecheck.ax").write_text(source.replace(old, changed))
    executable = work / "capture-name-negative"
    built = subprocess.run(
        [str(compiler), "--diagnostic-format=ai", "build",
         str(repo / "tests/selfhost/typecheck-capture-name-options.ax"),
         "--opt", "0", "--output", str(executable)],
        env=dict(env, AXIOM_PATH=str(overlay)), capture_output=True, text=True,
    )
    if built.returncode:
        raise SystemExit(built.stdout + built.stderr)
    ran = subprocess.run([str(executable)], capture_output=True, text=True)
    if ran.returncode != 2 or ran.stdout or ran.stderr:
        raise SystemExit(f"capture name control: status={ran.returncode}, stdout={ran.stdout!r}, stderr={ran.stderr!r}")
    print("capture name negative control rejected Some-empty collapse (status 2)")



def signature_tag_negative_control(compiler, repo, env, work):
    """Prove a present empty signature tag vector cannot become None."""
    overlay = work / "negative-signature-tag-core/core"
    overlay.mkdir(parents=True)
    for source in (repo / "core").iterdir():
        if source.is_file() and source.name != "typecheck.ax":
            (overlay / source.name).symlink_to(source)
    source = (repo / "core/typecheck.ax").read_text()
    start = source.index("(pub fn (sigAxtagsFrom ")
    end = source.index("\n\n", start)
    body = source[start:end]
    old = "(nodeAxtagsOpt d)"
    if body.count(old) != 1:
        raise SystemExit("signature tag control no longer matches its single lookup site")
    changed = "(if (== (vecLen (nodeAxtagsOf d)) 0) None (nodeAxtagsOpt d))"
    (overlay / "typecheck.ax").write_text(source[:start] + body.replace(old, changed) + source[end:])
    executable = work / "signature-tag-negative"
    built = subprocess.run(
        [str(compiler), "--diagnostic-format=ai", "build",
         str(repo / "tests/selfhost/typecheck-signature-tag-options.ax"),
         "--opt", "0", "--output", str(executable)],
        env=dict(env, AXIOM_PATH=str(overlay)), capture_output=True, text=True,
    )
    if built.returncode:
        raise SystemExit(built.stdout + built.stderr)
    ran = subprocess.run([str(executable)], capture_output=True, text=True)
    if ran.returncode != 1 or ran.stdout or ran.stderr:
        raise SystemExit(f"signature tag control: status={ran.returncode}, stdout={ran.stdout!r}, stderr={ran.stderr!r}")
    print("signature tag negative control rejected Some-empty collapse (status 1)")



def struct_fields_negative_control(compiler, repo, env, work):
    """Prove the packed missing field slot becomes a real empty collection."""
    overlay = work / "negative-struct-fields-core/core"
    overlay.mkdir(parents=True)
    for source in (repo / "core").iterdir():
        if source.is_file() and source.name != "parser.ax":
            (overlay / source.name).symlink_to(source)
    source = (repo / "core/parser.ax").read_text()
    old = """(pub fn (nodeStructFields node)
  (if (== (nodeB node) 0)
    vecNew
    (nodeBChildren node)))"""
    if source.count(old) != 1:
        raise SystemExit("struct fields control no longer matches its single normalisation site")
    (overlay / "parser.ax").write_text(source.replace(old, old.replace("    vecNew", "    (nodeBChildren node)")))
    executable = work / "struct-fields-negative"
    built = subprocess.run(
        [str(compiler), "--diagnostic-format=ai", "build",
         str(repo / "tests/selfhost/typecheck-struct-fields.ax"),
         "--opt", "0", "--output", str(executable)],
        env=dict(env, AXIOM_PATH=str(overlay)), capture_output=True, text=True,
    )
    if built.returncode:
        raise SystemExit(built.stdout + built.stderr)
    ran = subprocess.run([str(executable)], capture_output=True, text=True)
    if ran.returncode != 2 or ran.stdout or ran.stderr:
        raise SystemExit(f"struct fields control: status={ran.returncode}, stdout={ran.stdout!r}, stderr={ran.stderr!r}")
    print("struct fields negative control rejected missing boundary normalisation (status 2)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--axiom", required=True, type=Path)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    compiler = args.axiom.resolve()
    repo = Path(__file__).resolve().parents[2]
    env = dict(os.environ, AXIOM_PATH=str(repo / "core"), AXIOM_STDLIB=str(repo / "stdlib"))
    fixtures = [repo / "tests/selfhost" / name for name in [
        "typecheck-type-registry.ax", "typecheck-module-options.ax",
        "typecheck-function-registry.ax", "typecheck-private-state.ax",
        "typecheck-witness-options.ax", "typecheck-field-options.ax",
        "typecheck-collector-options.ax", "typecheck-current-decl-options.ax",
        "typecheck-constructor-name-options.ax", "typecheck-exhaustiveness-options.ax",
        "typecheck-declaration-field-options.ax", "typecheck-semantic-string-options.ax",
        "typecheck-capture-name-options.ax", "typecheck-signature-tag-options.ax",
        "region-fact-projections.ax", "typecheck-struct-fields.ax",
    ]]
    refusals = [
        ("typecheck-type-registry-payload.axp", "AX3004", ("DataEnt", "StructEnt")),
        ("typecheck-graph-options-exhaustive.axp", "AX3005", ("None",)),
        ("typecheck-context-refusal.axp", "AX3004", ("TC", "Int")),
        ("typecheck-private-context-refusal.axp", "AX3004", ("ContractContext", "Int")),
        ("typecheck-witness-exhaustive.axp", "AX3005", ("None",)),
        ("typecheck-field-exhaustive.axp", "AX3005", ("None",)),
        ("typecheck-collector-refusal.axp", "AX3004", ("Option", "Int")),
        ("typecheck-current-decl-refusal.axp", "AX3004", ("Option", "Int")),
        ("typecheck-constructor-name-refusal.axp", "AX3004", ("Option", "Vec")),
        ("typecheck-exhaustiveness-result-refusal.axp", "AX3005", ("None",)),
        ("typecheck-declaration-field-refusal.axp", "AX3005", ("None",)),
        ("typecheck-semantic-string-refusal.axp", "AX3005", ("None",)),
        ("typecheck-capture-name-refusal.axp", "AX3005", ("None",)),
        ("typecheck-capture-seen-refusal.axp", "AX3004", ("String", "Int")),
        ("typecheck-signature-tag-refusal.axp", "AX3005", ("None",)),
        ("typecheck-struct-fields-refusal.axp", "AX3004", ("Vec", "ASTNode", "Option")),
    ]
    with tempfile.TemporaryDirectory(prefix="axiom-type-registry-") as work:
        for fixture in fixtures:
            executable = Path(work) / "registry"
            built = subprocess.run(
                [str(compiler), "--diagnostic-format=ai", "build", str(fixture),
                 "--opt", "0", "--output", str(executable)],
                env=env, capture_output=True, text=True,
            )
            if built.returncode:
                raise SystemExit(built.stdout + built.stderr)
            ran = subprocess.run([str(executable)], capture_output=True, text=True)
            if ran.returncode != 42 or ran.stdout or ran.stderr:
                raise SystemExit(f"registry fixture: status={ran.returncode}, stdout={ran.stdout!r}, stderr={ran.stderr!r}")
        for name, code, expected_names in refusals:
            refusal = repo / "tests/selfhost" / name
            checked = subprocess.run(
                [str(compiler), "--diagnostic-format=ai", "check", str(refusal)],
                env=env, capture_output=True, text=True,
            )
            errors = [line for line in checked.stderr.splitlines() if line.startswith("E ")]
            if checked.returncode != 1 or len(errors) != 1 or f"E {code} " not in errors[0]:
                raise SystemExit(f"{name}: status={checked.returncode}\n{checked.stdout}{checked.stderr}")
            if any(expected not in errors[0] for expected in expected_names):
                raise SystemExit(f"{name}: unexpected refusal: {errors[0]}")
        if args.negative_controls:
            witness_negative_control(compiler, repo, env, Path(work))
            field_negative_control(compiler, repo, env, Path(work))
            collector_negative_control(compiler, repo, env, Path(work))
            current_decl_negative_control(compiler, repo, env, Path(work))
            constructor_name_negative_control(compiler, repo, env, Path(work))
            exhaustiveness_negative_control(compiler, repo, env, Path(work))
            declaration_field_negative_control(compiler, repo, env, Path(work))
            semantic_string_negative_control(compiler, repo, env, Path(work))
            capture_name_negative_control(compiler, repo, env, Path(work))
            signature_tag_negative_control(compiler, repo, env, Path(work))
            struct_fields_negative_control(compiler, repo, env, Path(work))
    print(f"typed checker: {len(fixtures)} runtime fixtures returned 42; {len(refusals)} typed/exhaustiveness refusals passed")


if __name__ == "__main__":
    main()
